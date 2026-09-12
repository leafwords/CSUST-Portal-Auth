'use strict';
// Cache-busted view path for the simplified CSUT portal configuration.
'require view';
'require form';
'require uci';
'require fs';
'require poll';
'require rpc';

var callServiceList = rpc.declare({
	object: 'rc',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} }
});

function serviceRunning(serviceList) {
	for (var name in serviceList)
		if (serviceList[name] && serviceList[name].running)
			return true;

	return false;
}

function describeStatus(raw, running) {
	if (!raw)
		return {
			level: running ? 'notice' : 'warning',
			text: running ? '服务正在运行，等待首次状态上报' : '服务尚未运行'
		};

	try {
		var status = JSON.parse(raw);
		var labels = {
			online: '在线',
			offline: '离线',
			authenticating: '正在认证',
			error: '错误'
		};
		var details = [];

		if (status.username)
			details.push('账号 ' + status.username);
		if (status.ip)
			details.push('IP ' + status.ip);
		if (status.mac)
			details.push('MAC ' + status.mac);
		if (status.portal_ip)
			details.push('Portal ' + status.portal_ip);

		return {
			level: status.state === 'online' ? 'success' :
				status.state === 'authenticating' ? 'notice' : 'warning',
			text: (labels[status.state] || status.state || '未知') +
				' - ' + (status.message || '') +
				(details.length ? '（' + details.join('，') + '）' : '')
		};
	}
	catch (error) {
		return { level: 'warning', text: '状态文件格式无效' };
	}
}

function updateStatus(raw, running) {
	var node = document.getElementById('campus-portal-status');
	if (!node)
		return;

	var status = describeStatus(raw, running);
	node.className = 'alert-message ' + status.level;
	node.textContent = status.text;
}

return view.extend({
	load: function() {
		return Promise.all([
			callServiceList('campus-portal'),
			uci.load('campus_portal'),
			fs.read('/tmp/campus-portal.status').catch(function() { return ''; })
		]);
	},

	render: function(data) {
		var running = serviceRunning(data[0]);
		var statusNode = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ '运行状态' ]),
			E('div', {
				'id': 'campus-portal-status',
				'class': 'alert-message'
			}, [ '正在读取...' ])
		]);
		var map = new form.Map('campus_portal', '校园网 Portal 认证',
			'认证逻辑已按当前校园网网关固定配置。登录前会重新读取 WAN IPv4、WAN MAC 和 Portal IP。');
		var section = map.section(form.NamedSection, 'main', 'service', '认证设置');
		var option;

		section.anonymous = true;
		section.addremove = false;

		option = section.option(form.Flag, 'enabled', '启用自动认证');
		option.default = option.disabled;
		option.rmempty = false;

		option = section.option(form.Value, 'interface', 'WAN 逻辑接口');
		option.default = 'wan';
		option.placeholder = 'wan';
		option.rmempty = false;
		option.description = '通常保持为 wan。认证时会自动解析实际设备、IPv4 和 MAC。';

		option = section.option(form.Value, 'username', '账号');
		option.rmempty = false;
		option.description = '只填写校园网账号。程序会自动添加 ,0,，并自动移除误填的运营商后缀。';

		option = section.option(form.Value, 'password', '密码');
		option.password = true;
		option.rmempty = false;

		option = section.option(form.Value, 'interval', '在线检查间隔');
		option.datatype = 'range(10,3600)';
		option.default = '30';
		option.rmempty = false;
		option.description = '单位为秒。认证失败时服务会自动退避重试。';

		updateStatus(data[2], running);
		poll.add(function() {
			return Promise.all([
				callServiceList('campus-portal'),
				fs.read('/tmp/campus-portal.status').catch(function() { return ''; })
			]).then(function(result) {
				updateStatus(result[1], serviceRunning(result[0]));
			});
		}, 5);

		return map.render().then(function(mapNode) {
			return E([], [ statusNode, mapNode ]);
		});
	}
});
