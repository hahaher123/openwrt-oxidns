# openwrt-oxidns

[OxiDNS](https://github.com/svenshi/oxidns) 的 OpenWrt 打包仓库：在 OpenWrt 构建系统（buildroot / SDK）中**从源码交叉编译**出 `oxidns` 核心二进制，产出 OpenWrt 软件包。

**设计目标：与 [luci-app-oxidns](https://github.com/svenshi/luci-app-oxidns) 配合使用。** 本包只提供核心二进制与默认配置，**不提供**服务脚本和 UCI 配置——那两样由 `luci-app-oxidns` 提供。两个包的文件集**零重叠**，可以同时安装，不存在任何冲突：

```sh
apk add oxidns luci-app-oxidns      # OpenWrt 25.12+（apk）
opkg install oxidns luci-app-oxidns # OpenWrt 24.10（opkg）
```

---

## 声明

**来源引用**

- 上游项目：[`svenshi/oxidns`](https://github.com/svenshi/oxidns)，作者 Sven Shi，许可证 GPL-3.0-or-later。
- 本仓库打包的上游版本：**v1.5.2**（`PKG_VERSION:=1.5.2`，源码哈希固定于 `net/oxidns/Makefile` 的 `PKG_HASH`）。
- 上游默认配置来源：[`config.yaml`](https://github.com/svenshi/oxidns/blob/main/config.yaml)，仅做 OpenWrt 路径适配。
- 包内路径约定来源：[`svenshi/luci-app-oxidns`](https://github.com/svenshi/luci-app-oxidns) 与 [上游 OpenWrt 文档](https://github.com/svenshi/oxidns/blob/main/docs/docs/openwrt.mdx)。

**用途声明**

1. 本仓库**仅用于在 OpenWrt 环境下编译 OxiDNS**。它只包含打包描述（Makefile / OpenWrt 配置）与仓库自检脚本。
2. 本仓库**不重新分发** OxiDNS 源码。构建时由 OpenWrt 构建系统按 `PKG_SOURCE_URL` + `PKG_HASH` 自行下载并校验上游 tag 归档。CI 发布的 `.apk` 是本仓库用官方 SDK 现场编译的产物（**不是**上游二进制），只作为便利渠道；上游发行请以 `svenshi/oxidns` 的 Release 为准。
3. 本仓库是**非官方**的第三方打包，与上游 OxiDNS 项目无隶属关系，未获其背书。OxiDNS 本体的功能、配置语义与问题反馈请以上游为准。
4. 需要非 OpenWrt 平台（Linux 通用发行版 / macOS / Windows）的安装方式时，请使用上游官方安装脚本与 Release，不要使用本仓库。

---

## 包内容

| 包名 | 安装内容 | 说明 |
| --- | --- | --- |
| `oxidns` | `/usr/bin/oxidns`<br>`/etc/oxidns/config.yaml`（conffile）<br>`/usr/share/oxidns/webui/`（目录，放 WebUI 前端产物） | 核心二进制与默认配置，路径与上游 Release 归档、`luci-app-oxidns` 完全一致 |

本仓库**只产出一个包**：`oxidns`。要完整跑起来还需要 `luci-app-oxidns`（见下）。

---

## 与 luci-app-oxidns 的配合

`luci-app-oxidns` 本身**不包含** OxiDNS 核心（它的 `LUCI_DEPENDS` 里没有 `oxidns`），默认从上游 GitHub Releases 下载 musl 归档安装到 `/usr/bin/oxidns`；它提供的是 procd 服务、UCI 配置和 LuCI 页面。本仓库提供的是同一个位置的、由 OpenWrt 构建系统自行编译的核心，用来替换那个从网上下载的二进制。

两个包各自负责的文件：

| 路径 | `oxidns`（本仓库） | `luci-app-oxidns` |
| --- | :---: | :---: |
| `/usr/bin/oxidns` | ✅ | — |
| `/etc/oxidns/config.yaml` | ✅ | — |
| `/usr/share/oxidns/webui/` | ✅（空目录） | — |
| `/etc/init.d/oxidns` | — | ✅ |
| `/etc/config/oxidns` | — | ✅ |
| `/usr/share/oxidns/targets.json` | — | ✅ |

**没有任何交集**，所以 `apk` / `opkg` 不会报文件冲突，两个包可以随时一起装、一起升：

```sh
apk add oxidns luci-app-oxidns
/etc/init.d/rpcd restart
# 打开 LuCI：Services -> OxiDNS
```

`scripts/validate.sh` 会把「包内是否出现 `luci-app-oxidns` 的文件路径」当成一项检查，将来误加文件会直接让 CI 失败。

⚠️ 装完之后**不要**再用 LuCI `Services → OxiDNS → Core` 页面的 `Install Core` / `Remove Core`：那个页面直接读写 `/usr/bin/oxidns` 与 `/usr/share/oxidns/webui`，绕过包管理器，会让 apk/opkg 数据库与实际文件不一致。需要升级或更换核心时，升级 `oxidns` 包本身即可。

---

## 快速开始

### 前置条件

- OpenWrt **24.10 或 25.12**（Rust ≥ 1.85 才能编译 `edition = "2024"`；24.10 为 rust 1.94，25.12 为 rust 1.96）。
  - **包格式跟着 OpenWrt 版本走**：24.10 用 **opkg**，产物是 `.ipk`，安装用 `opkg install`；25.12 起改用 **apk**，产物是 `.apk`，安装用 `apk add`。CI 默认构建 25.12，产出 `.apk`。
- 完整的 buildroot 或 SDK，已执行 `./scripts/feeds update -a && ./scripts/feeds install -a`（需要 `feeds/packages/lang/rust`）。
- Linux x86_64 构建主机（或 WSL2）。
- **磁盘 ≥ 40 GB，首次编译数小时**：`PKG_BUILD_DEPENDS:=rust/host` 会从源码构建 Rust 工具链（含 LLVM）。这是 OpenWrt Rust 包的固有代价，与 OxiDNS 无关。产物会缓存在 `build_dir/` 与 `dl/cargo`，后续增量编译很快。

### 方式一：作为 feed 加入（推荐）

```sh
cd /path/to/openwrt
echo "src-link oxidns /path/to/openwrt-oxidns" >> feeds.conf
./scripts/feeds update oxidns
./scripts/feeds install -a -p oxidns

make menuconfig     # Network -> IP Addresses and Names -> oxidns
make -j$(nproc) package/feeds/oxidns/oxidns/compile V=s
```

产物：

| OpenWrt | 路径 | 安装命令 |
| --- | --- | --- |
| 25.12+ | `bin/packages/<arch>/oxidns/oxidns-<ver>-r<n>.apk` | `apk add ./oxidns-<ver>-r<n>.apk` |
| 24.10 | `bin/packages/<arch>/oxidns/oxidns_<ver>-r<n>_<arch>.ipk` | `opkg install ./oxidns_*.ipk` |

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

脚本自动完成：下载并解压官方 SDK → 注册本地 feed → 拉取 `lang/rust` → 打开 `oxidns` → 编译 → 收集产物到 `./out`。常用参数：`-t` 目标（如 `armsr/armv8`、`ramips/mt7621`）、`-v` OpenWrt 版本、`-j` 并行度、`-w` 工作目录。

CI 侧的 `.github/workflows/build.yml` 用的是同一套流程（手动触发，或被上游版本探测工作流调用）。

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

### 安装

```sh
apk add oxidns luci-app-oxidns      # OpenWrt 25.12+（apk）
opkg install oxidns luci-app-oxidns # OpenWrt 24.10（opkg）

/etc/init.d/rpcd restart
# 打开 LuCI：Services -> OxiDNS
```

改配置、启停服务、看日志都在 LuCI 的 `Services → OxiDNS` 页面里。

### 服务与 UCI 选项

`/etc/init.d/oxidns` 与 `/etc/config/oxidns` 由 `luci-app-oxidns` 提供（本仓库**不提供**）。选项如下，仅供命令行排查时参考：

| 选项 | 默认值 | 说明 |
| --- | --- | --- |
| `config_path` | `/etc/oxidns/config.yaml` | 配置文件路径 |
| `working_dir` | `/var/lib/oxidns` | 工作目录，相对路径的基准 |
| `log_level` | 空 | 传给 `oxidns start -l` 的日志级别覆盖 |
| `probe_config` | `1` | 启动前执行 `oxidns check`，配置有误则拒绝启动（避免 crash loop） |

命令行下也可以直接操作：

```sh
vi /etc/oxidns/config.yaml     # 默认监听 :5335，避免与 dnsmasq 抢 53
/etc/init.d/oxidns enable
/etc/init.d/oxidns start
logread -f | grep oxidns
```

`reload` 语义说明：OxiDNS 未安装 `SIGHUP` 处理器，procd 的 `reload` 信号会按默认动作终止进程，因此服务脚本把 `reload` 实现为 `restart`。

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
- 产物：`oxidns` 的 x86/64 `.apk`，发布在 Releases 页面。安装方式：`apk add oxidns luci-app-oxidns`。
- 手工补跑：Actions → **upstream-watch** → *Run workflow*，勾选 `force` 可在上游没有新版时也重新编译并发布。

> ⚠️ 编译耗时以小时计（要现场构建 Rust 工具链含 LLVM）。若遇到 GitHub Actions 时长上限，冷启动（无缓存）可能超时失败——此时重跑一次命中缓存即可。仅变更上游版本才会触发编译，「无更新」的日子不会消耗构建资源。

---

## 目录结构

```
.
├── net/oxidns/                 # OpenWrt feed 布局：<分类>/<包名>/
│   ├── Makefile                # 包定义（只产出 oxidns 一个包）
│   ├── Config.in               # feature bundle 选择
│   └── files/
│       └── oxidns.yaml         # /etc/oxidns/config.yaml
├── scripts/
│   ├── validate.sh             # 仓库自检
│   ├── sync-upstream.sh        # 跟进上游新版本（更新 PKG_VERSION/PKG_HASH）
│   └── build-sdk.sh            # 用官方 SDK 构建
└── .github/workflows/
    ├── validate.yml            # 元数据 / 文件校验
    ├── build.yml               # 可复用：手动或由上游探测调用，产出 .apk
    └── upstream-watch.yml      # 每 24h 探测上游 → 有新版本则编译并发布 Release
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
