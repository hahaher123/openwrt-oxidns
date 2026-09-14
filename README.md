# openwrt-oxidns

[OxiDNS](https://github.com/svenshi/oxidns) 的 OpenWrt 打包仓库：在 OpenWrt 构建系统（buildroot / SDK）中**从源码交叉编译**出 `oxidns` 核心二进制，并生成可安装的 OpenWrt 软件包。

配合 [luci-app-oxidns](https://github.com/svenshi/luci-app-oxidns) 使用，也支持纯命令行（procd + UCI）部署。

---

## 声明

**来源引用**

- 上游项目：[`svenshi/oxidns`](https://github.com/svenshi/oxidns)，作者 Sven Shi，许可证 GPL-3.0-or-later。
- 本仓库打包的上游版本：**v1.5.2**（`PKG_VERSION:=1.5.2`，源码哈希固定于 `net/oxidns/Makefile` 的 `PKG_HASH`）。
- 上游默认配置来源：[`config.yaml`](https://github.com/svenshi/oxidns/blob/main/config.yaml)，仅做 OpenWrt 路径适配。
- 包内路径约定来源：[`svenshi/luci-app-oxidns`](https://github.com/svenshi/luci-app-oxidns) 与 [上游 OpenWrt 文档](https://github.com/svenshi/oxidns/blob/main/docs/docs/openwrt.mdx)。

**用途声明**

1. 本仓库**仅用于在 OpenWrt 环境下编译 OxiDNS**。它只包含打包描述（Makefile / OpenWrt 配置）与仓库自检脚本。
2. 本仓库**不重新分发** OxiDNS 源码或任何二进制。构建时由 OpenWrt 构建系统按 `PKG_SOURCE_URL` + `PKG_HASH` 自行下载并校验上游 tag 归档。因此本仓库不是上游的发行渠道，也不提供预编译安装包。
4. 本仓库是**非官方**的第三方打包，与上游 OxiDNS 项目无隶属关系，未获其背书。OxiDNS 本体的功能、配置语义与问题反馈请以上游为准。
5. 需要非 OpenWrt 平台（Linux 通用发行版 / macOS / Windows）的安装方式时，请使用上游官方安装脚本与 Release，不要使用本仓库。

---

## 包内容

| 包名 | 安装内容 | 说明 |
| --- | --- | --- |
| `oxidns` | `/usr/bin/oxidns`<br>`/etc/oxidns/config.yaml`（conffile）<br>`/usr/share/oxidns/webui/`（空目录） | 核心二进制与默认配置，与上游 Release 归档、`luci-app-oxidns` 使用的路径一致 |
| `oxidns-service` | `/etc/init.d/oxidns`（procd）<br>`/etc/config/oxidns`（conffile） | 纯命令行部署用的服务脚本与 UCI 配置 |

> `oxidns-service` 与 `luci-app-oxidns` 提供**同名文件**，因此二者互斥（`CONFLICTS`）。

---

## 与 luci-app-oxidns 的配合

`luci-app-oxidns` 本身**不包含** OxiDNS 核心（其 `LUCI_DEPENDS` 里没有 `oxidns`）。它默认从上游 GitHub Releases 下载 musl 归档并安装到 `/usr/bin/oxidns`。本仓库提供的是同一个位置的、由 OpenWrt 构建系统自行编译的替代品。

两种组合方式：

| 组合 | 安装命令 | 适用场景 |
| --- | --- | --- |
| **LuCI 管理**（推荐） | `opkg install oxidns luci-app-oxidns` | 用 LuCI 页面管理服务、编辑配置、看日志 |
| **纯命令行** | `opkg install oxidns oxidns-service` | 无 LuCI 的精简固件，只用 UCI + `/etc/init.d/oxidns` |

⚠️ **不要同时安装** `oxidns-service` 和 `luci-app-oxidns`：两者都会提供 `/etc/init.d/oxidns` 与 `/etc/config/oxidns`，包管理器会报文件冲突。

⚠️ 核心由包管理器安装后，建议**不要**再使用 LuCI 的 `Services → OxiDNS → Core` 页面的 `Install Core` / `Remove Core`：该页面直接读写 `/usr/bin/oxidns` 与 `/usr/share/oxidns/webui`，绕过包管理器，会导致 opkg/apk 数据库与实际文件不一致。需要升级核心时请升级 `oxidns` 包本身。

---

## 快速开始

### 前置条件

- OpenWrt **24.10 或 25.12**（Rust ≥ 1.85 才能编译 `edition = "2024"`；24.10 为 rust 1.94，25.12 为 rust 1.96）。
- 完整的 buildroot 或 SDK，已执行 `./scripts/feeds update -a && ./scripts/feeds install -a`（需要 `feeds/packages/lang/rust`）。
- Linux x86_64 构建主机（或 WSL2）。
- **磁盘 ≥ 40 GB，首次编译数小时**：`PKG_BUILD_DEPENDS:=rust/host` 会从源码构建 Rust 工具链（含 LLVM）。这是 OpenWrt Rust 包的固有代价，与 OxiDNS 无关。产物会缓存在 `build_dir/` 与 `dl/cargo`，后续增量编译很快。

### 方式一：作为 feed 加入（推荐）

```sh
cd /path/to/openwrt
echo "src-link oxidns /path/to/openwrt-oxidns" >> feeds.conf
./scripts/feeds update oxidns
./scripts/feeds install -a -p oxidns

make menuconfig     # Network -> IP Addresses and Names -> oxidns / oxidns-service
make -j$(nproc) package/feeds/oxidns/oxidns/compile V=s
make -j$(nproc) package/feeds/oxidns/oxidns-service/compile V=s
```

产物：`bin/packages/<arch>/oxidns/oxidns_*.ipk`（或 `*.apk`）。

### 方式二：直接放进 package/ 目录

```sh
cp -r /path/to/openwrt-oxidns/net/oxidns /path/to/openwrt/package/
make menuconfig
make -j$(nproc) package/oxidns/compile V=s
```

### 方式三：只下 SDK，一条命令构建

```sh
sh scripts/build-sdk.sh -t x86/64 -v 25.12.5 -o ./out
```

脚本自动完成：下载并解压官方 SDK → 注册本地 feed → 拉取 `lang/rust` → 打开两个包 → 编译 → 收集产物到 `./out`。常用参数：`-t` 目标（如 `armsr/armv8`、`ramips/mt7621`）、`-v` OpenWrt 版本、`-j` 并行度、`-w` 工作目录。

CI 侧的 `.github/workflows/build.yml` 用的是同一套流程（手动/打 tag 触发）。

---

## 编译选项

`make menuconfig → Network → IP Addresses and Names → oxidns → OxiDNS compile-time feature bundle`：

| Bundle | 内容 | 说明 |
| --- | --- | --- |
| `full`（默认） | 全部功能：管理 API、WebUI、指标、DoT/DoH/DoQ/DoH3、SQLite 查询记录、MikroTik、ipset/nftset、自升级 | 与上游 Release 归档、`luci-app-oxidns` 的默认预期一致 |
| `standard` | 去掉 HTTP/3、MikroTik、ipset/nftset | 家用路由器常用组合 |
| `minimal` | 仅转发核心（UDP/TCP 监听与上游、sequence/forward/cache 等基础插件） | 最小体积，无管理 API / WebUI |

选择后构建系统会以 `--no-default-features --features <bundle>` 编译。**注意**：`luci-app-oxidns` 默认按 `full` 的功能集工作（例如配置里使用 `webui`、`query_recorder` 等），选 `minimal` / `standard` 时请自行确认配置中未引用未编译进来的插件，否则启动时会报 `not compiled in; rebuild with --features ...`。

---

## 使用

### LuCI 管理

```sh
opkg install oxidns luci-app-oxidns
/etc/init.d/rpcd restart
# 打开 LuCI：Services -> OxiDNS
```

### 纯命令行

```sh
opkg install oxidns oxidns-service

vi /etc/oxidns/config.yaml     # 默认监听 :5335，避免与 dnsmasq 抢 53
/etc/init.d/oxidns enable
/etc/init.d/oxidns start
logread -f | grep oxidns
```

UCI 选项（`/etc/config/oxidns`）：

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `config_path` | `/etc/oxidns/config.yaml` | 配置文件路径 |
| `working_dir` | `/var/lib/oxidns` | 工作目录，相对路径的基准 |
| `log_level` | 空 | 传给 `oxidns start -l` 的日志级别覆盖 |
| `probe_config` | `1` | 启动前执行 `oxidns check`，配置有误则拒绝启动（避免 crash loop） |

`reload` 语义说明：OxiDNS 未安装 `SIGHUP` 处理器，procd 的 `reload` 信号会按默认动作终止进程，因此本包把 `reload` 实现为 `restart`。

### WebUI 资源

上游源码树不含构建好的前端产物（`webui/` 是 Next.js 工程，`webui/out/` 不随 tag 归档发布），因此本包只创建 `/usr/share/oxidns/webui/` 空目录，默认配置已把 `api.http.webui.root` 指向该路径。需要内置 WebUI 时二选一：

- 在 LuCI 的 `Core` 页面用 `Upload Core` 上传官方归档（含 WebUI 产物）；
- 自行构建前端后拷贝进去：

  ```sh
  cd webui && pnpm install && pnpm build
  scp -r out/* root@router:/usr/share/oxidns/webui/
  ```

不装 WebUI 不影响 DNS 功能与管理 API。

---

## 自动化：上游版本探测 + 自动编译

`.github/workflows/upstream-watch.yml` 每 **24 小时**（UTC 02:23 / 北京时间 10:23）执行一次：

```
探测 svenshi/oxidns 最新 release
    │
    ├── 版本未变 ──► 结束（几秒钟）
    │
    └── 版本更新 ──► sync-upstream.sh 改写 PKG_VERSION / PKG_HASH
                       │
                       ├── 提交 "oxidns: update to <ver>" 并推送
                       ├── 用 OpenWrt SDK 25.12.5 编译 x86/64
                       └── 发布 GitHub Release（tag v<ver>，附件 .apk）
```

- 版本比对基于 **上游 release tag**（`https://api.github.com/repos/svenshi/oxidns/releases/latest`）与 `net/oxidns/Makefile` 的 `PKG_VERSION`。
- `PKG_HASH` 由脚本重新下载 tag 归档后计算，不与上游 Release 名猜版本；若 tag 内的 `Cargo.toml` 版本与 tag 不一致，脚本会拒绝写入并让工作流失败。
- 产物：`oxidns` 与 `oxidns-service` 的 x86/64 `.apk`，发布在 Releases 页面。
- 手工补跑：Actions → **upstream-watch** → *Run workflow*，勾选 `force` 可在上游没有新版时也重新编译并发布。

> ⚠️ 编译耗时以小时计（要现场构建 Rust 工具链含 LLVM）。若遇到 GitHub Actions 时长上限，冷启动（无缓存）可能超时失败——此时重跑一次命中缓存即可。仅变更上游版本才会触发编译，「无更新」的日子不会消耗构建资源。

---

## 仓库自检

```sh
sh scripts/validate.sh                       # 完整检查（需要可访问 GitHub）
OXIDNS_OFFLINE=1 sh scripts/validate.sh      # 跳过网络检查
OXIDNS_PROXY=http://127.0.0.1:7890 sh scripts/validate.sh
```

检查项：必需文件、`PKG_*` 元数据、`PKG_HASH` 与上游 tarball 是否一致、tarball 顶层目录是否等于 `PKG_BUILD_DIR`、`Cargo.toml` 版本是否等于 `PKG_VERSION`、install 段引用的文件是否存在、OpenWrt 包名与 UCI 名字是否只用 `[A-Za-z0-9_]`、`sh -n` 语法、YAML 无 tab、交付文件无 CRLF。

`push` / PR 时由 `.github/workflows/validate.yml` 自动执行。

---

## 目录结构

```
.
├── net/oxidns/                 # OpenWrt feed 布局：<分类>/<包名>/
│   ├── Makefile                # 包定义：oxidns + oxidns-service
│   ├── Config.in               # feature bundle 选择
│   └── files/
│       ├── oxidns.yaml         # /etc/oxidns/config.yaml
│       ├── oxidns.config       # /etc/config/oxidns
│       └── oxidns.init         # /etc/init.d/oxidns
├── scripts/
│   ├── validate.sh             # 仓库自检
│   ├── sync-upstream.sh        # 跟进上游新版本（更新 PKG_VERSION/PKG_HASH）
│   └── build-sdk.sh            # 用官方 SDK 构建
└── .github/workflows/
    ├── validate.yml            # 元数据 / 文件校验
    └── build.yml               # 手动或打 tag 触发，产出 .ipk/.apk
```

---

## 维护

上游发新版后本仓库会在 24 小时内自动跟进（见「自动化」一节），一般不需要手工操作。需要手动处理时：

```sh
sh scripts/sync-upstream.sh          # 取上游最新 release，改写 Makefile
sh scripts/sync-upstream.sh 1.5.2    # 指定版本
sh scripts/validate.sh               # 更新后校验
```

---

## 已知限制

- 仅支持 OpenWrt 官方 Rust 包覆盖的架构（`aarch64 / arm / i386 / loongarch64 / mips / mips64 / mips64el / mipsel / powerpc / powerpc64 / riscv64 / x86_64`）。其它架构在 `menuconfig` 中不可见。
- 首次编译时间与磁盘占用由 `lang/rust` 决定，无法通过本包规避。
- 23.05 及更早版本：`lang/rust` 为 1.85.0，恰好是 `edition 2024` 的最低版本，**未经验证**，不建议使用。
- 上游 tag 归档的字节内容由 GitHub 生成，若上游改变归档压缩方式，`PKG_HASH` 需要同步更新（`sync-upstream.sh` 会处理）。
- 自动化工作流只产出 **x86/64** 的 `.apk`。其它架构请自行编译：`sh scripts/build-sdk.sh -t ramips/mt7621 -o ./out`。

---

## 许可证

- 本仓库的打包描述与脚本：GPL-3.0-or-later（见 `LICENSE`），与上游 OxiDNS 保持一致。
- OxiDNS 源码：GPL-3.0-or-later，版权归上游作者所有。
