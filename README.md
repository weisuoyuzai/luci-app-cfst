# luci-app-cfst

OpenWrt LuCI 插件：基于 [CloudflareSpeedTest (cfst)](https://github.com/XIU2/CloudflareSpeedTest) 对 Cloudflare IP 进行测速优选，并自动把最优 IP 写入 **PassWall / PassWall2 / OpenClash（尽力而为）** 的指定节点，支持定时任务、Web 界面一键操作。

是 [`cfst.sh`](cfst.sh)（PassWall2 专用手工脚本）的通用化 + LuCI 图形化版本。

## 功能

- 自动识别当前安装的代理插件：PassWall / PassWall2 / OpenClash，也可手动指定
- 节点匹配方式：手动勾选节点，或按备注关键字批量匹配
- 定时任务（cron 表达式）+ "立即运行" 按钮
- 自动下载 `cfst` 可执行文件（按路由器架构自动匹配），支持 GitHub 加速镜像前缀，也可手动点击更新
- 可选仅测试指定区域（按 Cloudflare colo 机场三字码，如 `HKG,LAX,NRT`）
- 测速参数（线程数、延迟测速次数、下载测速数量【默认 10 个】、时长、延迟/丢包率/速度阈值等）均可在页面配置
- 三个页签：**基础设置** / **测速结果** / **日志**，测速结果与日志支持自动刷新
- 测速时可临时关闭 PassWall/PassWall2 的本机代理，避免"测的是代理线路的速度"（OpenClash 无此开关，见下方说明）

## 目录结构

```
luci-app-cfst/
├── Makefile                                   # OpenWrt 软件包描述文件
├── root/
│   ├── etc/config/cfst                        # UCI 默认配置
│   ├── etc/init.d/cfst                        # 定时任务安装/卸载（procd）
│   └── usr/
│       ├── bin/cfst-run                       # 核心测速+应用脚本
│       ├── share/cfst/                        # 各后端实现 + 下载脚本
│       ├── share/rpcd/acl.d/luci-app-cfst.json
│       └── libexec/rpcd/luci.cfst             # ubus 后端接口
├── htdocs/luci-static/resources/              # LuCI JS 前端（view/js 模型）
└── po/                                        # 界面翻译（含 zh-cn）
```

## 安装方法

### 方式一：直接安装编译好的 ipk

1. 从本仓库 [Releases](../../releases) 页面，或 [Actions](../../actions) 最近一次构建的 Artifacts 中下载 `luci-app-cfst_*.ipk`
   （该插件不含任何编译产物，是架构无关包，任意平台的 ipk 都能装到任意架构的路由器上）
2. 上传到路由器后执行：
   ```sh
   opkg install luci-app-cfst_*.ipk
   ```
3. 刷新 LuCI 页面，在 **服务 (Services) → CloudflareST** 中找到插件

### 方式二：用 OpenWrt SDK 自行编译 ipk

适用于本机（Linux/WSL）已下载或想下载官方 SDK 的情况：

```sh
# 1. 下载与你路由器固件版本/架构匹配的 SDK，例如（以 x86/64、23.05 分支为例）：
wget https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/openwrt-sdk-23.05.5-x86-64_gcc-12.3.0_musl.Linux-x86_64.tar.xz
tar xf openwrt-sdk-*.tar.xz
cd openwrt-sdk-*/

# 2. 把本插件源码放进 package 目录（软链接或直接复制均可）
git clone https://github.com/<your-account>/luci-app-cfst.git package/luci-app-cfst

# 3. 更新 luci feed（提供 luci.mk 等公共构建脚本），并生成默认配置
./scripts/feeds update luci
./scripts/feeds install -a -p luci
make defconfig

# 4. 编译（V=s 打印详细日志，便于排错）
make package/luci-app-cfst/compile V=s

# 5. 编译产物位置
find bin/ -name 'luci-app-cfst_*.ipk'
```

因为本插件 `LUCI_PKGARCH:=all`（没有任何 C 代码，纯脚本 + JS），**只需用任意一个架构的 SDK 编译一次**，产出的 ipk 就能装到所有架构的路由器上，不需要为每种硬件单独编译。

### 方式三：随完整 OpenWrt 源码（buildroot）一起编译

把本目录放进 OpenWrt 源码的 `package/luci-app-cfst`，然后：

```sh
make menuconfig   # LuCI → Applications → 勾选 luci-app-cfst
make package/luci-app-cfst/compile V=s
```

### 方式四（快速调试用）：手动复制文件，不打包

不追求 opkg 包管理，只想快速在测试路由器上体验：

```sh
scp -r root/* htdocs root@<router-ip>:/
ssh root@<router-ip> "
  chmod +x /usr/bin/cfst-run /usr/share/cfst/*.sh /usr/libexec/rpcd/luci.cfst
  /etc/init.d/cfst enable
  /etc/init.d/cfst start
  rm -f /tmp/luci-indexcache*
  killall -HUP rpcd
"
```

### GitHub Actions 自动构建

仓库内置 [`.github/workflows/build.yml`](.github/workflows/build.yml)，推送到 `main`、发起 PR、打 `v*` 标签或手动触发（workflow_dispatch）都会用官方 [`openwrt/gh-action-sdk`](https://github.com/openwrt/gh-action-sdk) 自动编译出 ipk：

- 每次构建的产物可在 Actions 运行记录的 Artifacts 中下载
- 打 `v*` 标签（如 `v1.0.0`）时，会自动把 ipk 附加到对应的 GitHub Release

## 使用说明

### 1. 基础设置

- **启用**：总开关，关闭后定时任务不会被安装（"立即运行" 按钮不受此开关影响，随时可用）
- **代理类型**：`自动识别` 会在 PassWall2 / PassWall / OpenClash 中探测——**如果同时装了不止一个，会拒绝自动判断**，需要在这里手动选择，避免改错代理的配置
- **节点匹配方式**：
  - *手动选择节点*：从当前后端读取到的节点列表里勾选一个或多个（切换"代理类型"后需先保存、刷新页面才能重新加载节点列表）
  - *按备注关键字匹配*：填一个关键字（如 `cf优选`），运行时会匹配所有备注包含该关键字的节点
- **测速时临时关闭本机代理**：仅对 PassWall / PassWall2 生效；OpenClash 没有对应开关，测速流量可能仍会经过 OpenClash 代理，此项会在日志中留下提示

### 2. 定时任务

启用后填写标准 5 段 cron 表达式（分 时 日 月 星期），例如 `30 3 * * *` 表示每天 3:30。保存设置即会自动同步到 `/etc/crontabs/root`。

### 3. cfst 程序管理

- 首次运行若检测不到 `cfst` 可执行文件，且"缺失时自动下载"已勾选，会自动下载对应架构的版本
- **GitHub 加速前缀**：国内访问 GitHub Releases 可能较慢，可在此填入一个反代前缀（如 `https://ghproxy.com/`），留空则直连 GitHub。公共加速服务可用性会变化，用不了时请自行更换
- **自定义下载地址**（高级）：填了会直接下载该地址，忽略架构识别和加速前缀
- 点击"立即更新 cfst 程序"可随时手动更新

### 4. 测速参数

对应 CloudflareST 的命令行参数，其中"下载测速数量 (-dn)"默认 **10** 个（其余延迟测速次数、延迟/丢包率/速度阈值等均可调）。

### 5. 区域选择

"仅测试所选区域 (-cfcolo)" 提供了常见地区的机场三字码勾选（亚洲/北美/欧洲/大洋洲/南美/中东非洲），也可以在下方文本框手填其他三字码（逗号分隔）。全部留空表示测试所有 Cloudflare 节点，不做区域限制。

### 6. 立即运行 / 测速结果 / 日志

- "基础设置" 页顶部的"立即运行"按钮会在后台触发一次测速+应用，不会阻塞页面
- "测速结果" 页显示最近一次结果（IP / 发送 / 接收 / 丢包率 / 延迟 / 速度），运行中会自动刷新
- "日志" 页显示运行日志，可手动刷新或清空，格式与原始 `cfst.sh` 保持一致

## 卸载

```sh
opkg remove luci-app-cfst
```

会自动移除 cron 任务；`/etc/config/cfst`（配置）以及 `/root/cfst/`（cfst 程序、日志、测速结果）不会被删除，如需彻底清理请手动 `rm -rf /root/cfst`。

## 已知限制

- **OpenClash 支持为尽力而为**：节点信息存放在 YAML 订阅/配置文件中而非 UCI 数据库，插件按节点名做文本匹配修改 `server` 字段（优先用 `yq`，否则用内置的 awk 解析器），不同 OpenClash 版本/订阅格式可能导致匹配失败——失败时只会记录日志并跳过，不会写坏配置文件
- PassWall（旧版）节点字段结构假定与 PassWall2 相同（同一作者），运行时有基本的防御性检查，但未在所有版本上验证过
- 架构探测表以 CloudflareSpeedTest 当前发布的资源命名为准，如遇冷门架构下载失败，可用"自定义下载地址"手动指定

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。
