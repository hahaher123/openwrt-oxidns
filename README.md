# openwrt-oxidns

[OxiDNS](https://github.com/svenshi/oxidns) 的 OpenWrt 打包仓库：在 OpenWrt 构建系统中从源码交叉编译出 `oxidns` 核心二进制。**非官方第三方打包**，构建时按 `PKG_SOURCE_URL` + `PKG_HASH` 下载并校验上游 v1.5.2 tag 归档，不重新分发源码；非 OpenWrt 平台请用上游官方安装方式。

## 安装（设备上）

与 [luci-app-oxidns](https://github.com/hahaher123/luci-app-oxidns) 配合使用。两个包文件零重叠（本包只装 `/usr/bin/oxidns`、`/etc/oxidns/config.yaml`（conffile）与 `/usr/share/oxidns/webui/` 空目录；服务脚本与 UCI 由 luci-app-oxidns 提供），可同时安装：

```sh
apk add oxidns luci-app-oxidns      # 需要 OpenWrt 25.12 或更新版本
/etc/init.d/rpcd restart            # 打开 LuCI：Services -> OxiDNS
```

⚠️ 装了本包之后**不要**再用 LuCI `Core` 页的 `Install Core` / `Remove Core`：它会绕过包管理器直接读写 `/usr/bin/oxidns`，导致 apk 数据库与实际文件不一致。升级核心 = 升级 `oxidns` 包。

默认配置监听 `:5335`（避开 dnsmasq 的 53），不装 WebUI 不影响 DNS 与管理 API。

## 从源码构建

前置条件：**OpenWrt 25.12+**（24.10 及更早的 rust 是 1.94，低于 `sysinfo 0.39` 要求的 1.95，无法编译）；完整 buildroot / SDK，feeds 已 update+install；Linux x86_64 主机；**磁盘 ≥ 40 GB，首次编译数小时**（要从源码构建 Rust 工具链，OpenWrt Rust 包的固有代价，之后有缓存）。注意官方 Release SDK 的 feed 钉死在发布时刻的提交上，直接用会拿到过旧的 rust——`build-sdk.sh` 已自动改指到 release 分支；手工搭环境请先 `./scripts/feeds update packages`。

方式一，作为 feed 加入：

```sh
echo "src-link oxidns /path/to/openwrt-oxidns" >> feeds.conf
./scripts/feeds update oxidns && ./scripts/feeds install -a -p oxidns
make menuconfig      # Network -> IP Addresses and Names -> oxidns
make -j$(nproc) package/feeds/oxidns/oxidns/compile V=s
```

方式二，一条命令下官方 SDK 自动构建（自动修 feed、校验 rust 版本、收集产物到 ./out）：

```sh
sh scripts/build-sdk.sh -t x86/64 -v 25.12.5 -o ./out
```

## 编译选项

`menuconfig` 里可选 feature bundle：`full`（默认，全部功能，与上游 Release 和 luci-app-oxidns 预期一致）/ `standard`（去 HTTP/3、MikroTik、ipset/nftset）/ `minimal`（仅转发核心，无管理 API / WebUI）。选非 full 时请确认配置未引用未编译的插件，否则启动报 `not compiled in`。

## 自动化

`upstream-watch.yml` 每 24 小时探测上游 release：有新版本就改写 `PKG_VERSION` / `PKG_HASH`、用 SDK 编译 x86/64 并发布 Release（tag `v<PKG_VERSION>-r<PKG_RELEASE>`，附件 .apk）。手动补跑在 Actions 的 upstream-watch 里（勾 `force` 可强制重编）。手工跟进版本：`sh scripts/sync-upstream.sh`。

## 已知限制

- 仅支持 OpenWrt 官方 Rust 包覆盖的架构（aarch64 / x86_64 / mipsel / riscv64 等）；自动化只产出 x86/64，其它架构用 `build-sdk.sh -t <目标>` 自编。
- OpenWrt 24.10 及更早无法编译（rust 过旧）。
- 上游源码不含构建好的前端产物，`webui/` 目录为空；需要 WebUI 就在 LuCI `Core` 页上传官方归档，或自行构建前端后拷入。
