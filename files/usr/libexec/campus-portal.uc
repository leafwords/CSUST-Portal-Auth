#!/usr/bin/ucode

import * as fs from "fs";

const APP = "campus-portal";
const STATUS_FILE = "/tmp/campus-portal.status";

const PORTAL_BASE_URL = "https://login.csust.edu.cn:802";
const PORTAL_HOST = "login.csust.edu.cn";
const PORTAL_FALLBACK_IP = "192.168.7.221";
const LOGIN_PATH = "/eportal/portal/login";
const STATUS_URL = "https://login.csust.edu.cn/drcom/chkstatus";

const ACCOUNT_PREFIX = ",0,";
const GATEWAY_IP = "192.168.130.254";
const GATEWAY_NAME = "ME60-X8-1";
const JS_VERSION = "4.2.1";
const TERMINAL_TYPE = "1";
const LOGIN_METHOD = "1";
const LOGIN_CALLBACK = "dr_login";

const CONNECT_TIMEOUT = 5;
const REQUEST_TIMEOUT = 12;
const DEFAULT_INTERVAL = 30;

let last_log_state = null;

function byte_at(value, index) {
	return index < length(value) ? ord(substr(value, index, 1)) : 0;
}

function run_capture(argv) {
	let command = [];

	for (let index = 0; index < length(argv); index++) {
		let value = replace(`${argv[index]}`, /'/g, "'\\''");
		push(command, `'${value}'`);
	}

	let proc = fs.popen(join(" ", command), "r");
	if (!proc)
		return { code: 127, output: "" };

	let output = proc.read("all") || "";
	let code = proc.close();

	return { code: code, output: output };
}

function uci_get(option, fallback) {
	let result = run_capture([
		"/sbin/uci", "-q", "get", `campus_portal.main.${option}`
	]);
	let value = trim(result.output);

	return result.code == 0 && length(value) ? value : fallback;
}

function load_config() {
	return {
		enabled: uci_get("enabled", "0") == "1",
		interface: uci_get("interface", "wan"),
		username: uci_get("username", ""),
		password: uci_get("password", ""),
		interval: +uci_get("interval", `${DEFAULT_INTERVAL}`)
	};
}

function log_message(level, message) {
	run_capture([
		"/usr/bin/logger", "-t", APP, "-p", `daemon.${level}`, "--", message
	]);
}

function ascii_lower(value) {
	let output = "";

	for (let index = 0; index < length(value); index++) {
		let byte = byte_at(value, index);
		output += chr(byte >= 65 && byte <= 90 ? byte + 32 : byte);
	}

	return output;
}

function write_status(state, message, extra) {
	let data = {
		state: state,
		message: message,
		timestamp: time()
	};

	if (extra)
		for (let key in extra)
			data[key] = extra[key];

	let temporary = `${STATUS_FILE}.new`;
	let file = fs.open(temporary, "w", 0600);

	if (file) {
		file.write(sprintf("%J\n", data));
		file.close();
		fs.rename(temporary, STATUS_FILE);
	}

	if (state != last_log_state) {
		log_message(state == "error" ? "err" : "notice",
			`${state}: ${message}`);
		last_log_state = state;
	}
}

function normalize_account(value) {
	let account = trim(value);

	if (substr(account, 0, length(ACCOUNT_PREFIX)) == ACCOUNT_PREFIX)
		account = substr(account, length(ACCOUNT_PREFIX));

	let suffix = index(account, "@");
	if (suffix >= 0)
		account = substr(account, 0, suffix);

	return `${ACCOUNT_PREFIX}${account}`;
}

function normalize_mac(raw) {
	let cleaned = "";

	for (let index = 0; index < length(raw); index++) {
		let character = substr(raw, index, 1);
		let byte = ord(character);

		if ((byte >= 48 && byte <= 57) ||
		    (byte >= 65 && byte <= 70) ||
		    (byte >= 97 && byte <= 102))
			cleaned += character;
	}

	if (length(cleaned) != 12)
		return null;

	let output = "";

	for (let index = 0; index < length(cleaned); index++) {
		let byte = ord(substr(cleaned, index, 1));
		output += chr(byte >= 97 && byte <= 102 ? byte - 32 : byte);
	}

	return output;
}

function read_mac(device) {
	if (!device)
		return null;

	let result = run_capture(["/bin/cat", `/sys/class/net/${device}/address`]);
	if (result.code != 0)
		return null;

	return normalize_mac(trim(result.output));
}

function nslookup_ipv4(output) {
	let saw_name = false;

	for (let line in split(output, "\n")) {
		line = trim(line);

		if (match(line, /^Name:/))
			saw_name = true;

		let matched = match(line, /^Address:\s*([0-9.]+)/);
		if (saw_name && matched)
			return matched[1];
	}

	return null;
}

function resolve_host(host, servers) {
	if (match(host, /^[0-9.]+$/))
		return host;

	for (let server in servers) {
		let result = run_capture(["nslookup", host, server]);

		if (result.code == 0) {
			let address = nslookup_ipv4(result.output);
			if (address)
				return address;
		}
	}

	return null;
}

function get_wan_info(cfg) {
	let info = {
		interface: cfg.interface,
		device: cfg.interface,
		ip: null,
		mac: null,
		dns_servers: [],
		portal_ip: PORTAL_FALLBACK_IP
	};

	let result = run_capture([
		"ubus", "call", `network.interface.${cfg.interface}`, "status"
	]);

	if (result.code == 0 && length(trim(result.output))) {
		try {
			let status = json(result.output);

			if (status.l3_device)
				info.device = status.l3_device;
			else if (status.device)
				info.device = status.device;

			if (status["ipv4-address"] && length(status["ipv4-address"]))
				info.ip = status["ipv4-address"][0].address;

			if (status["dns-server"])
				info.dns_servers = status["dns-server"];

			info.mac = read_mac(status.device) ||
				read_mac(status.l3_device) ||
				read_mac(info.device);
		}
		catch (error) {
			info.error = `无法解析 WAN 状态: ${error}`;
		}
	}

	if (!info.mac)
		info.mac = read_mac(info.device) || read_mac(cfg.interface);

	if (!info.ip) {
		let address = run_capture([
			"/sbin/ip", "-4", "-o", "addr", "show", "dev", info.device
		]);

		if (address.code == 0) {
			let matched = match(address.output, /inet ([0-9.]+)\//);
			if (matched)
				info.ip = matched[1];
		}
	}

	info.portal_ip = resolve_host(PORTAL_HOST, info.dns_servers) ||
		PORTAL_FALLBACK_IP;

	if (!info.ip)
		info.error = `未从接口 ${cfg.interface} 获取到 IPv4 地址`;
	else if (!info.mac)
		info.error = `未从接口 ${cfg.interface} 获取到 MAC 地址`;

	return info;
}

function urlencode(value) {
	let output = "";

	for (let index = 0; index < length(value); index++) {
		let byte = byte_at(value, index);

		if ((byte >= 48 && byte <= 57) ||
		    (byte >= 65 && byte <= 90) ||
		    (byte >= 97 && byte <= 122) ||
		    byte == 45 || byte == 46 || byte == 95 || byte == 126)
			output += chr(byte);
		else
			output += sprintf("%%%02X", byte);
	}

	return output;
}

function curl_base(cfg, wan) {
	let argv = [
		"/usr/bin/curl",
		"-4",
		"--noproxy", "*",
		"--silent",
		"--show-error",
		"--connect-timeout", `${CONNECT_TIMEOUT}`,
		"--max-time", `${REQUEST_TIMEOUT}`
	];

	let device = wan && wan.device ? wan.device : cfg.interface;
	if (device) {
		push(argv, "--interface");
		push(argv, device);
	}

	return argv;
}

function curl_add_resolve(argv, wan, url) {
	let matched = match(url, /^(https?):\/\/([A-Za-z0-9._-]+):([0-9]+)/);
	let host;
	let port;

	if (matched) {
		host = matched[2];
		port = matched[3];
	}
	else {
		matched = match(url, /^(https?):\/\/([A-Za-z0-9._-]+)/);
		if (!matched)
			return;

		host = matched[2];
		port = matched[1] == "https" ? "443" : "80";
	}

	if (host != PORTAL_HOST || !wan.portal_ip)
		return;

	push(argv, "--resolve");
	push(argv, `${host}:${port}:${wan.portal_ip}`);
}

function curl_get(cfg, wan, url, pairs) {
	let argv = curl_base(cfg, wan);
	curl_add_resolve(argv, wan, url);
	push(argv, "--get");

	for (let index = 0; index < length(pairs); index++) {
		push(argv, "--data-urlencode");
		push(argv, `${pairs[index].key}=${pairs[index].value}`);
	}

	push(argv, url);
	return run_capture(argv);
}

function parse_jsonp(text) {
	let value = trim(text);

	if (!length(value))
		return null;

	try {
		return json(value);
	}
	catch (error) {
		let matched = match(value, /^\s*[^\(]*\((.*)\)\s*;?\s*$/);

		if (!matched)
			return null;

		try {
			return json(matched[1]);
		}
		catch (inner_error) {
			return null;
		}
	}
}

function first_value(object, keys) {
	for (let key in keys) {
		if (object && object[key] != null && `${object[key]}` != "")
			return object[key];
	}

	return null;
}

function response_success(object) {
	if (!object)
		return false;

	let result = first_value(object, [ "result", "code", "status" ]);
	let success = first_value(object, [ "success", "ok" ]);

	if (success === true || `${success}` == "true" || `${success}` == "1")
		return true;

	return result == 1 || `${result}` == "1" ||
		ascii_lower(`${result}`) == "ok" ||
		ascii_lower(`${result}`) == "success";
}

function response_message(object, text) {
	let message = first_value(object, [
		"msg", "message", "error_msg", "errorMsg", "res", "error"
	]);

	if (message != null)
		return `${message}`;

	let shortened = trim(text);
	return length(shortened) > 160 ? substr(shortened, 0, 160) : shortened;
}

function build_login_pairs(cfg, wan) {
	let mac = normalize_mac(wan.mac);

	return [
		{ key: "callback", value: LOGIN_CALLBACK },
		{ key: "login_method", value: LOGIN_METHOD },
		{ key: "user_account", value: normalize_account(cfg.username) },
		{ key: "user_password", value: cfg.password },
		{ key: "wlan_user_ip", value: wan.ip },
		{ key: "wlan_user_ipv6", value: "" },
		{ key: "wlan_user_mac", value: mac },
		{ key: "wlan_ac_ip", value: GATEWAY_IP },
		{ key: "wlan_ac_name", value: GATEWAY_NAME },
		{ key: "jsVersion", value: JS_VERSION },
		{ key: "terminal_type", value: TERMINAL_TYPE },
		{ key: "lang", value: "zh-cn" },
		{ key: "v", value: `${time()}` }
	];
}

function check_online(cfg, wan) {
	let result = curl_get(cfg, wan, STATUS_URL, [
		{ key: "callback", value: "dr_status" },
		{ key: "jsVersion", value: JS_VERSION },
		{ key: "v", value: `${time()}` }
	]);

	if (result.code != 0)
		return {
			state: "unknown",
			message: `在线状态接口请求失败 (curl ${result.code})`
		};

	let data = parse_jsonp(result.output);
	if (!data)
		return { state: "unknown", message: "在线状态接口返回无法解析" };

	if (response_success(data))
		return { state: "online", data: data };

	return { state: "offline", data: data };
}

function login(cfg, wan) {
	let result = curl_get(
		cfg,
		wan,
		`${PORTAL_BASE_URL}${LOGIN_PATH}`,
		build_login_pairs(cfg, wan)
	);

	if (result.code != 0)
		return {
			ok: false,
			message: `登录请求失败 (curl ${result.code})`
		};

	let data = parse_jsonp(result.output);

	if (response_success(data))
		return { ok: true, message: "认证接口返回成功" };

	return {
		ok: false,
		message: `认证接口拒绝: ${response_message(data, result.output)}`
	};
}

function validate_config(cfg) {
	if (!cfg.username)
		die("账号不能为空\n");
	if (!cfg.password)
		die("密码不能为空\n");
	if (!match(cfg.interface, /^[A-Za-z0-9_.:-]+$/))
		die("WAN 接口名称无效\n");

	if (cfg.interval < 10)
		cfg.interval = 10;
	if (cfg.interval > 3600)
		cfg.interval = 3600;
}

function ensure_online(cfg, probe_only) {
	let wan = get_wan_info(cfg);

	if (!wan.ip || !wan.mac) {
		write_status("error", wan.error || "无法读取 WAN IP/MAC");
		return false;
	}

	let current = check_online(cfg, wan);

	if (current.state == "online") {
		write_status("online", "校园网已在线", {
			username: normalize_account(cfg.username),
			ip: wan.ip,
			mac: normalize_mac(wan.mac),
			device: wan.device,
			portal_ip: wan.portal_ip
		});
		return true;
	}

	if (current.state == "unknown") {
		write_status("error", current.message || "无法判断校园网在线状态", {
			ip: wan.ip,
			mac: normalize_mac(wan.mac),
			device: wan.device,
			portal_ip: wan.portal_ip
		});
		return false;
	}

	if (probe_only) {
		write_status("offline", "校园网离线（探针模式未认证）", {
			ip: wan.ip,
			mac: normalize_mac(wan.mac),
			device: wan.device,
			portal_ip: wan.portal_ip
		});
		return false;
	}

	write_status("authenticating", "检测到离线，正在认证", {
		username: normalize_account(cfg.username),
		ip: wan.ip,
		mac: normalize_mac(wan.mac),
		device: wan.device,
		portal_ip: wan.portal_ip
	});

	let auth = login(cfg, wan);

	if (!auth.ok) {
		write_status("error", auth.message, {
			ip: wan.ip,
			mac: normalize_mac(wan.mac),
			device: wan.device,
			portal_ip: wan.portal_ip
		});
		return false;
	}

	for (let attempt = 0; attempt < 5; attempt++) {
		sleep(1000);

		let verified = check_online(cfg, wan);
		if (verified.state == "online") {
			write_status("online", "认证成功并已确认在线", {
				username: normalize_account(cfg.username),
				ip: wan.ip,
				mac: normalize_mac(wan.mac),
				device: wan.device,
				portal_ip: wan.portal_ip
			});
			return true;
		}
	}

	write_status("error", "认证接口返回成功，但在线检查仍未通过", {
		ip: wan.ip,
		mac: normalize_mac(wan.mac),
		device: wan.device,
		portal_ip: wan.portal_ip
	});
	return false;
}

function selftest() {
	let cfg = {
		username: "student001",
		password: "dummy"
	};
	let wan = {
		ip: "10.1.2.3",
		mac: "AA:BB:CC:DD:EE:FF",
		device: "wan",
		portal_ip: PORTAL_FALLBACK_IP
	};
	let pairs = build_login_pairs(cfg, wan);
	let account_ok = false;
	let ip_ok = false;
	let mac_ok = false;
	let gateway_ip_ok = false;
	let gateway_name_ok = false;
	let method_ok = false;

	for (let index = 0; index < length(pairs); index++) {
		if (pairs[index].key == "user_account" &&
		    pairs[index].value == ",0,student001")
			account_ok = true;
		if (pairs[index].key == "wlan_user_ip" &&
		    pairs[index].value == "10.1.2.3")
			ip_ok = true;
		if (pairs[index].key == "wlan_user_mac" &&
		    pairs[index].value == "AABBCCDDEEFF")
			mac_ok = true;
		if (pairs[index].key == "wlan_ac_ip" &&
		    pairs[index].value == "192.168.130.254")
			gateway_ip_ok = true;
		if (pairs[index].key == "wlan_ac_name" &&
		    pairs[index].value == "ME60-X8-1")
			gateway_name_ok = true;
		if (pairs[index].key == "login_method" &&
		    pairs[index].value == "1")
			method_ok = true;
	}

	let normalize_ok =
		normalize_account("student001@isp") == ",0,student001" &&
		normalize_account(",0,student001") == ",0,student001";
	let url_ok = urlencode("a b+c&d") == "a%20b%2Bc%26d";
	let jsonp_ok = response_success(parse_jsonp('dr_login({"result":1});'));
	let ok = account_ok && ip_ok && mac_ok &&
		gateway_ip_ok && gateway_name_ok &&
		method_ok && normalize_ok && url_ok && jsonp_ok;

	printf("selftest=%s account=%s ip=%s mac=%s gateway_ip=%s gateway_name=%s method=%s normalize=%s url=%s jsonp=%s\n",
		ok ? "ok" : "failed",
		account_ok ? "ok" : "failed",
		ip_ok ? "ok" : "failed",
		mac_ok ? "ok" : "failed",
		gateway_ip_ok ? "ok" : "failed",
		gateway_name_ok ? "ok" : "failed",
		method_ok ? "ok" : "failed",
		normalize_ok ? "ok" : "failed",
		url_ok ? "ok" : "failed",
		jsonp_ok ? "ok" : "failed");

	return ok ? 0 : 1;
}

function main() {
	let mode = ARGV[0] || "once";

	if (mode == "selftest")
		return selftest();

	let cfg = load_config();
	validate_config(cfg);

	if (mode == "probe")
		return ensure_online(cfg, true) ? 0 : 1;

	if (mode == "once")
		return ensure_online(cfg, false) ? 0 : 1;

	if (mode != "daemon")
		die("用法: campus-portal.uc [selftest|probe|once|daemon]\n");

	let backoff = [ 15, 30, 60, 120, 300 ];
	let failures = 0;

	while (true) {
		let online = false;

		try {
			online = ensure_online(cfg, false);
		}
		catch (error) {
			write_status("error", `未处理异常: ${error}`);
		}

		if (online) {
			failures = 0;
			sleep(cfg.interval * 1000);
		}
		else {
			let index = failures < length(backoff) ? failures : length(backoff) - 1;
			sleep(backoff[index] * 1000);
			failures++;
		}
	}
}

exit(main());
