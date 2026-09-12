# luci-app-campus-portal

面向 OpenWrt 24.10 及以下版本的 IPK，以及 OpenWrt 25.12 及以上版本的 APK。

当前版本按长沙理工大学认证环境简化：

- Portal：`https://login.csust.edu.cn:802`
- 登录接口：`/eportal/portal/login`
- 在线检查：`https://login.csust.edu.cn/drcom/chkstatus`
- 网关：`ME60-X8-1 / 192.168.130.254`
- 账号提交格式：`,0,学号`

## LuCI 配置项

LuCI 只保留必要配置：

- 启用自动认证
- WAN 逻辑接口
- 账号
- 密码
- 在线检查间隔

账号只填写校园网账号，例如：

```text
student001
```

程序会自动提交：

```text
,0,student001
```

即使误填运营商后缀，例如 `student001@isp`，程序也会自动去掉 `@isp`。该后缀不需要填写。

## 自动处理

- 自动读取 WAN IPv4 和 WAN MAC
- MAC 使用明文大写格式
- 自动通过校园 DNS 解析 Portal 域名
- 自动使用 `curl --resolve` 绕过 DNS rebind
- 自动包含 Portal 地址、登录路径、网关 IP、网关名称和 JS 版本
- 断线自动认证，失败自动退避重试
- WAN 重新上线后自动重启认证服务

## 构建

构建 APK：

```sh
./tools/build-apk.sh
```

构建 IPK：

```sh
./tools/build-ipk.sh
```

也可以把源码放入 OpenWrt 源码或 SDK 的 `package/` 目录：

```sh
make package/luci-app-campus-portal/compile V=s
```

## 安装

OpenWrt 25.12 及以上：

```sh
apk add --allow-untrusted ./luci-app-campus-portal-1.2.0-r1.apk
```

OpenWrt 24.10 及以下：

```sh
opkg install ./luci-app-campus-portal_1.2.0-r1_all.ipk
```

安装后启用服务：

```sh
/etc/init.d/campus-portal enable
```

随后进入 LuCI：

```text
服务 -> 校园网 Portal 认证
```

## 安全

密码保存在 `/etc/config/campus_portal`，配置文件权限为 `0600`。服务日志和 LuCI 状态不会输出密码。

## 最后

代码都是 DeepSeek 写的，我只抓了个包，让我们感谢 D 老师。