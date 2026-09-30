# openwrt-oxidns

[OxiDNS](https://github.com/svenshi/oxidns) 的 OpenWrt 打包仓库：在 OpenWrt 构建系统中从源码交叉编译出 `oxidns` 核心二进制。**非官方第三方打包**，构建时按 `PKG_SOURCE_URL` + `PKG_HASH` 下载并校验上游对应版本的 tag 归档，不重新分发源码；非 OpenWrt 平台请用上游官方安装方式。

## 安装（设备上）

与 [luci-app-oxidns](https://github.com/hahaher123/luci-app-oxidns) 配合使用。两个包文件零重叠（本包只装 `/usr/bin/oxidns`、`/etc/oxidns/config.yaml`（conffile）与 `/usr/share/oxidns/webui/` 下的 WebUI 静态资源；服务脚本与 UCI 由 luci-app-oxidns 提供），可同时安装：

```sh
apk add oxidns luci-app-oxidns      # 需要 OpenWrt 25.12 或更新版本
/etc/init.d/rpcd restart            # 打开 LuCI：Services -> OxiDNS
```

装好后 `/usr/share/oxidns/webui/` 里已经有可直接访问的 WebUI，不必再去 LuCI `Core` 页上传官方归档。`Remove Core` 只删核心二进制、不会动包提供的 WebUI 资源。

默认配置监听 `:5335`（避开 dnsmasq 的 53）。

## WebUI 来源

WebUI 是独立构建的 Next.js 静态产物，上游只随 Release 归档分发预构建的 `webui/`，源码 tag 归档里只有未构建的前端源码。本包在构建时下载官方 `oxidns-x86_64-unknown-linux-musl.tar.gz` 并只取其中的 `webui/` 装入 `/usr/share/oxidns/webui/`——与官方 Docker 镜像、Debian 包取的是同一份产物。前端资源平台无关，全架构共用一份，也免去在 buildroot 里跑 pnpm。

## 从源码构建

前置条件：**OpenWrt 25.12+**（24.10 及更早的 rust 是 1.94，低于 `sysinfo 0.39` 要求的 1.95，无法编译）；完整 buildroot / SDK，feeds 已 update+install；Linux x86_64 主机；**磁盘 ≥ 40 GB，首次编译数小时**（要从源码构建 Rust 工具链，OpenWrt Rust 包的固有代价，之后有缓存）。注意官方 Release SDK 的 feed 钉死在发布时刻的提交上，直接用会拿到过旧的 rust——`build-sdk.sh` 已自动改指到 release 分支；手工搭环境请先 `./scripts/feeds update packages`。

方式一，作为 feed 加入：

```sh
# 本仓库是扁平布局（Makefile 就在仓库根），而 feed 扫描不认 feed 根目录自身的
# Makefile，所以要垫一层目录，用符号链接把包目录指过去
mkdir -p /tmp/oxidns-feed
ln -sfn /path/to/openwrt-oxidns /tmp/oxidns-feed/oxidns
echo "src-link oxidns /tmp/oxidns-feed" >> feeds.conf
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

`upstream-watch.yml` 每 24 小时探测上游 release：有新版本就改写 `PKG_VERSION` / `PKG_HASH` / `OXIDNS_WEBUI_HASH`、用 SDK 编译 x86/64 并发布 Release（tag `v<PKG_VERSION>-r<PKG_RELEASE>`，附件 .apk）。手动补跑在 Actions 的 upstream-watch 里（勾 `force` 可强制重编）。手工跟进版本：`sh scripts/sync-upstream.sh`。

## 已知限制

- 仅支持 OpenWrt 官方 Rust 包覆盖的架构（aarch64 / x86_64 / mipsel / riscv64 等）；自动化只产出 x86/64，其它架构用 `build-sdk.sh -t <目标>` 自编。
- OpenWrt 24.10 及更早无法编译（rust 过旧）。
- WebUI 取自上游 Release 归档，无法脱离上游构建；上游若某版本漏发 musl 归档，该版本构建会失败（`build` 阶段直接报错，不会静默出空目录）。
