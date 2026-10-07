<div align="center">

# LiteBox

**给 GL.iNet GL-MT3600BE（Beryl 7）等小内存 OpenWrt 路由器用的轻量透明代理，附手机版**

家里所有设备不用任何设置就能分流：国内直连、AI 单独选节点、其余走代理。常驻内存约 50MB。

[![最新版本](https://img.shields.io/github/v/release/lyr05142002-dot/Q7Y?label=%E6%9C%80%E6%96%B0%E7%89%88)](https://github.com/lyr05142002-dot/Q7Y/releases/latest)
[![OpenWrt 21.02 安装测试](https://github.com/lyr05142002-dot/Q7Y/actions/workflows/test.yml/badge.svg)](https://github.com/lyr05142002-dot/Q7Y/actions/workflows/test.yml)

[下载](#下载) · [图文安装教程](#图文安装教程) · [手机版](#手机版) · [常用命令](#常用命令) · [出问题怎么办](#装好后自检出问题怎么办)

</div>

![网页面板：代理分组](docs/img/10-panel-proxies.png)

<p align="center"><sub>路由器网页面板（zashboard），每个分组都带图标。截图来自云端测试环境，节点是演示数据</sub></p>

## 特点

- **一条命令装好**：登录路由器粘贴一条命令、一路回车。自动沿用 OpenClash 里已有的订阅、自动停用冲突插件，装不上自动切回原样
- **GL 官方固件直接装**：GL 固件是 OpenWrt 21.02，[Open-Box](https://github.com/liandu2024/Open-Box) 要求 OpenWrt 24 以上装不了；LiteBox 专门按 21.02 写，不用刷机
- **国内流量不进内核**：国内网站直接从 WAN 出去，不占代理的 CPU，还能用上路由器的硬件加速；境外 TCP 走 iptables 转发，比 TUN 省约 70% CPU
- **省内存**：只有一个 mihomo 进程，常驻约 50MB，大流量下也不涨；超过上限自动重启
- **分流规则现成的**：用[视频作者](https://youtu.be/G_7AmjfSRQ8)的[域名集](https://github.com/liandu2024/clash/tree/main/list)，每天自动更新；ChatGPT / Claude / Gemini / Grok 等走单独的 🤖 AI 分组
- **概览和路由测试页**：四个站点的延迟走势、连接 / 内存 / 流量实时曲线、规则命中统计、按月流量；输入域名就能看它实际走哪条线路、DNS 怎么解析、命中哪条规则
- **手机版**：安卓、iPhone 用同一套规则，出门在外也一样分流
- **出问题能自救**：`litebox doctor` 一键自检、`litebox direct` 一键恢复直连；内核起不来时看门狗自动恢复 DNS，不会全家断网
- **下载安全**：内核和面板锁定版本、校验 SHA256；每次发布前自动在 OpenWrt 21.02 里完整装一遍测试

<table>
  <tr>
    <td width="68%"><img src="docs/img/11-panel-connections.png" alt="连接页：每条连接走的规则和线路"></td>
    <td><img src="docs/img/12-panel-phone.png" alt="手机打开面板"></td>
  </tr>
  <tr>
    <td align="center"><sub>每条连接命中的规则和完整线路</sub></td>
    <td align="center"><sub>手机上打开面板</sub></td>
  </tr>
</table>

## 云端实测

在 OpenWrt 21.02.7（和 GL 固件同一版本）里按用户流程从头安装，局域网接一台模拟手机测试：

| 项目 | 结果 |
|---|---|
| 安装 | 连不上 GitHub 时约 65 秒（规则改由内核经代理下载）；装完 **2.5 秒**内局域网设备就能上网 |
| 内存 | 常驻约 **53MB**；40 并发、约 100MB 下载后仍是 50MB 左右 |
| DNS | 中位 **0.2ms**（fake-ip 在本地应答） |
| 打开网页 | 首字节 0.12 秒，直连同一节点是 0.14 秒，**没有额外延迟** |
| 下载速度 | 43–47 MB/s，约为直连同一节点的 **90%** |
| 分流 | ChatGPT / Claude / Gemini / Grok → 🤖 AI；百度 / B 站 / 淘宝 / QQ → 直连；Google / YouTube / GitHub → 代理 ✅ |
| 手机版 | 安卓配置启动后 2 秒下载好全部规则，分流结果同上，内存 48MB |
| 稳定性 | 崩溃自动拉起、看门狗自愈、升级保留配置、重启自启、卸载还原，全部通过 |

测试机是 x86_64。v0.4.0 已在 GL-MT3600BE 真机（OpenWrt 21.02 第三方固件）上运行：加速层生效，内核内存 43MB，换下 OpenClash 后系统可用内存从 68MB 增加到 135MB。真机的 4 核 A53 单核比测试机慢不少：处理 100MB 流量测试机约用 1 秒 CPU，按此粗估，跑满百兆宽带约占 4 个核里的 1 个，日常上网、看视频负载很轻。装好后用 `litebox mem`、`top` 看实际情况。

## 和 OpenClash 比

在云端同一台测试路由器、同一部测试手机上，用同一个 mihomo 内核（v1.19.31）、同一份订阅和分流规则，依次装 LiteBox 和最新的 OpenClash（v0.47.156，fake-ip 模式），下载同一个 22MB 文件，记录代理内核用掉的 CPU：

| | 国内网站：内核 CPU / 速度 | 境外网站：内核 CPU | 内存 |
|---|---|---|---|
| **LiteBox v0.4（默认）** | **0ms** / 1050–1310 MB/s | **70–80ms** | 51MB |
| OpenClash 默认设置 | 20–30ms / 420–740 MB/s | 60–70ms | 51MB |
| OpenClash 开「绕过中国大陆 IP」 | 0ms / 1220–1490 MB/s | 80–130ms | 51MB |
| LiteBox v0.3 及以前（只用 TUN） | 210–340ms / 75–114 MB/s | 270–390ms | 50MB |

其他方面：

| 项目 | LiteBox | OpenClash | 说明 |
|---|---|---|---|
| 新域名 DNS 解析 | **0.8ms** | 24ms | OpenClash 默认把每个 fake-ip 映射写进闪存（`store-fake-ip`），LiteBox 关掉了：把 LiteBox 也打开后同样变成 23ms |
| 重启到恢复代理 | **6–7 秒** | 9–10 秒 | |
| 占用存储（不含内核） | **约 6MB** | 约 25MB，另需 Ruby、bash、dnsmasq-full 等依赖 | |
| 功能 | 够用：分组、分流、面板、自检 | **多得多**：订阅转换、覆写、多种代理模式、LuCI 页面里改各种设置 | |

简单说：**同一个内核，速度、内存一样**；LiteBox 开箱就是 OpenClash 调好之后的水平（国内不进内核、境外走 iptables 转发），DNS 更快、更省存储、装和管更简单；OpenClash 功能更全。已经在用 OpenClash 而且满意的，没必要换。

## 下载

**一般不用手动下载**：登录路由器后粘贴一条命令就能装，见[图文安装教程](#图文安装教程)。

路由器完全连不上 GitHub 时，到 [Releases 页面](https://github.com/lyr05142002-dot/Q7Y/releases/latest) 下载离线包：

| 文件 | 说明 |
|---|---|
| [litebox-arm64-offline.zip](https://github.com/lyr05142002-dot/Q7Y/releases/latest/download/litebox-arm64-offline.zip) | 已带 mihomo 内核和面板（约 23MB），路由器不用联网。适用于 GL-MT3600BE 等 aarch64 路由器 |
| [litebox.zip](https://github.com/lyr05142002-dot/Q7Y/releases/latest/download/litebox.zip) | 只有脚本（几十 KB），安装时再联网下载内核和面板，支持 aarch64 / armv7 / x86_64 |

手机见[手机版](#手机版)。

## 为什么不直接装 Open-Box

| | GL-MT3600BE 实际情况 | Open-Box 要求 |
|---|---|---|
| CPU | MT7987A，4×Cortex-A53（`ARMv8 Processor rev 4`，aarch64） | aarch64 ✅ |
| 系统 | GL 官方固件 = OpenWrt 21.02，fw3 / iptables，musl 1.1.x | OpenWrt 24+、musl ≥ 1.2.4（安装脚本直接拒绝更老的系统），nftables ❌ |
| 内存 | 512MB | 要求 512MB 内存、512MB 存储，常驻 Node.js 面板 |

Open-Box 的面板和 App 是闭源的，没法改，所以 LiteBox 全部用开源组件，从头写了安装和管理脚本（**没有复制 Open-Box 的代码**）：

| 组件 | 作用 | 来源 |
|---|---|---|
| [mihomo](https://github.com/MetaCubeX/mihomo) v1.19.31 | 代理内核：订阅、分组、分流、DNS、tun 透明代理 | 官方 Release，SHA256 写死在 `install.sh` 里校验 |
| [zashboard](https://github.com/Zephyruso/zashboard) v3.29.1 | 网页面板（无字体版，约 2.7MB），由内核直接提供，不另起进程 | 官方 Release，同样校验 SHA256 |
| 分流规则 | AI / 直连 / 代理域名集 + YouTube、Google 等常用服务 + 国内域名和 IP 段 | [liandu2024/clash](https://github.com/liandu2024/clash/tree/main/list)、[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) |

Open-Box 有些做法很实用，LiteBox 用自己的方式实现了：

| Open-Box 的做法 | LiteBox 里 |
|---|---|
| 默认屏蔽走代理的 QUIC，浏览器退回 TCP，节点 UDP 差时更流畅 | 默认屏蔽，`litebox quic on/off` 切换；国内站点不受影响 |
| 「IP 只管 IP，域名只管域名」，不为匹配 IP 段去解析境外域名 | 国内 IP 规则加 `no-resolve` |
| 开着硬件流量卸载的联发科机器出问题时换 gvisor 协议栈 | `litebox stack gvisor`；`litebox doctor` 发现开着流量卸载会提示 |
| 安卓 App 的「本地分流」：手机按路由器同一套规则自己分流 | [手机版](#手机版)：安卓（FlClash / Clash Meta）和 iPhone（Shadowrocket）配置，不用装专门的 App |
| 一键升级 | `litebox update`（配置和订阅保留，下载包校验 SHA256） |
| 直连不进内核 | 国内域名返回真实 IP，国内 IP 由防火墙直接放行走 WAN；境外 TCP 用 iptables 转发（`litebox accel on/off`） |

### 内存控制

- 不加载 GeoSite / GeoIP 数据库（国内规则改用体积小得多的 mrs 格式）、关闭进程查找
- `GOMEMLIMIT=100MiB`：接近 100MB 时 Go 运行时更积极地回收内存
- 看门狗：cron 每 5 分钟检查一次，常驻内存超过 **180MB** 自动重启内核

两个上限都在 `/etc/litebox/litebox.conf` 里改（`MEM_SOFT_MB`、`MEM_HARD_MB`），改完 `litebox restart`。

## 图文安装教程

![安装流程总览](docs/img/01-flow.png)

**开始前**：电脑用网线或 Wi-Fi 连着这台路由器。在 GL 管理后台（http://192.168.8.1）关掉 GL 自带的 VPN 客户端和 AdGuard Home。装过 OpenClash、Passwall 的**不用自己处理**，安装时会自动停用（配置保留，随时能切回）。

### 第 1 步：登录路由器

电脑按 <kbd>Win</kbd>+<kbd>R</kbd>，输入 `powershell` 回车，在打开的窗口里输入：

```
ssh root@192.168.8.1
```

问 yes/no 就输入 `yes`，然后输入 GL 后台的管理密码（**输入时不显示**，输完回车）。

![登录路由器](docs/img/02-login.png)

提示 `REMOTE HOST IDENTIFICATION HAS CHANGED` 连不上：先执行 `ssh-keygen -R 192.168.8.1`，再重新登录。

### 第 2 步：粘贴一条命令，一路回车

复制下面这行，在 PowerShell 窗口里**点鼠标右键**粘贴，回车：

```
curl -fsSL https://raw.githubusercontent.com/lyr05142002-dot/Q7Y/main/get.sh | sh
```

接下来它会问两个问题，**都直接回车**：

1. 检测到 OpenClash / Passwall 等：回车停用它们（只是停用，下载会趁它们还在工作时先完成）
2. 检测到它们里面已有的机场订阅：回车直接用。没检测到时会让你粘贴订阅地址

然后等 1–3 分钟，看到「安装完成，已启动」就好了。

![粘贴一条命令，一路回车](docs/img/03-install.png)

- **装不上也不会断网**：LiteBox 起不来时会自动切回原来的 OpenClash，或者恢复直连
- 路由器打不开 GitHub 时，命令换成下面这条（经镜像下载）；还不行就用后面的[离线包](#方式二离线包路由器完全连不上-github-时)：
  ```
  curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/lyr05142002-dot/Q7Y/main/get.sh | sh -s -- --mirror https://ghfast.top
  ```

### 第 3 步：打开面板

把安装完显示的**一键登录链接**复制到手机或电脑浏览器，会自动填好并进入面板。链接找不到了，在路由器上运行 `litebox panel`。也可以按下图手动填：

![打开面板](docs/img/04-panel.png)

进入面板后在「代理」页切换节点：

![面板里的分组（每个都带图标）](docs/img/05-groups.png)

### 概览和路由测试

安装完还会显示一个**概览和路由测试**链接（`litebox panel` 也能看到），形如 `http://192.168.8.1:9090/ui/litebox/#secret=面板密码`。面板顶部的「节点 · 连接」可以跳回 zashboard。

- **概览**：百度 / Google / OpenAI / GitHub 的延迟和最近 24 次走势（分别经直连、🚀、🤖 AI、🚀 测，和平时访问走同一条线）；连接数、内存、上下行速率的实时曲线；规则命中排行和代理 / 直连占比；按月、按天的流量
- **路由测试**：输入域名，浏览器真实访问一次，页面从内核记录里找出这次访问的 DNS 方式、进入内核的方式、命中的规则和完整线路。正在看页面的这台手机或电脑本身就是局域网终端，所以不用另外模拟设备

![路由测试](docs/img/13-route-test.png)

<details><summary>概览页截图（测试环境只放行了 GitHub，所以另外三个站点显示超时）</summary>

![概览](docs/img/14-overview.png)

</details>

流量记录说明：看门狗每 5 分钟记一次经过内核的流量，平时写在内存里、每小时存回闪存一次。开着流量加速时国内 IP 不进内核，不计入。

### 装好后自检、出问题怎么办

在路由器上运行 `litebox doctor`，它会逐项检查，每个失败项下面都写了怎么处理：

![一键自检](docs/img/06-doctor.png)

| 遇到的情况 | 执行 |
|---|---|
| 上不了网 | `litebox direct`（立即恢复直连），再把 `litebox doctor` 的输出发出来求助（不含订阅地址和面板密码） |
| 想换回 OpenClash | `litebox switch-back`（安装时停用的插件恢复原样） |
| 升级到新版 | `litebox update` |

### 方式二：离线包（路由器完全连不上 GitHub 时）

**1. 在电脑上下载** [litebox-arm64-offline.zip](https://github.com/lyr05142002-dot/Q7Y/releases/latest/download/litebox-arm64-offline.zip)，右键「全部解压缩」，得到 `litebox` 文件夹：

![下载离线包](docs/img/offline-1-download.png)

**2. 传到路由器**：用 [HexHub](https://www.hexhub.cn/) 的 SFTP 把整个 `litebox` 文件夹拖到路由器的 `/tmp/`，或者在解压目录里打开 PowerShell 执行 `scp -O -r litebox root@192.168.8.1:/tmp/`（提示 `-O` 不认识就去掉 `-O`）：

![上传到路由器](docs/img/offline-2-upload.png)

**3. 登录路由器执行**下面这行，同样一路回车，之后从[第 3 步](#第-3-步打开面板)继续：

```
sh /tmp/litebox/install.sh
```

<details>
<summary>高级选项</summary>

- `--sub '订阅地址'`：直接指定订阅，不再询问。订阅支持 Clash / mihomo 格式和 base64 节点链接
- `--yes`：所有问题按默认回答（用检测到的订阅、停用冲突插件），适合无人值守
- `--mirror https://你的镜像`：指定 GitHub 镜像。内核和面板的 SHA256 写死在脚本里，镜像站换不了文件内容
- `--port 9091`：面板端口（默认 9090）
- 一条命令的方式是下载最新版的 `litebox.tar.gz`，校验 SHA256 后运行同一个 `install.sh`，参数原样传过去
</details>

## 手机版

和路由器**同一套分组和分流规则**（国内直连、AI 单独选节点、屏蔽走代理的 QUIC），在外面用流量也一样分流。手机自己连机场节点，不经过家里的路由器。

**最简单：手机浏览器打开 <https://lyr05142002-dot.github.io/Q7Y/>**，按页面提示操作。安卓填订阅地址就能生成配置文件，订阅地址只在手机浏览器里处理、不会上传；iPhone 一键导入 Shadowrocket。

<p>
  <img src="docs/img/08-mobile-android.png" alt="安卓：填订阅地址生成配置" width="45%">
  <img src="docs/img/09-mobile-iphone.png" alt="iPhone：一键导入 Shadowrocket" width="45%">
</p>

**安卓**（[FlClash](https://github.com/chen08209/FlClash/releases/latest) 或 [Clash Meta for Android](https://github.com/MetaCubeX/ClashMetaForAndroid/releases/latest)，下载 `arm64-v8a` 版本）：

1. 在上面的页面填订阅地址，点「生成并下载配置」，得到 `litebox-android.yaml`
   （也可以下载 [android.yaml](docs/mobile/android.yaml)，把里面的 `__SUB_URL__` 换成订阅地址）
2. App 里导入这个文件：FlClash「配置 → + → 文件」，Clash Meta「配置 → 新配置 → 导入文件」
3. 选中它，打开开关。第一次启动会经代理下载规则，等十几秒

**iPhone**（Shadowrocket）：

1. Shadowrocket 首页右上角 `+`，类型选 `Subscribe`，填订阅地址
2. 「配置」页右上角 `+`，粘贴下面的地址并下载，然后点它「使用配置」：
   ```
   https://raw.githubusercontent.com/lyr05142002-dot/Q7Y/main/docs/mobile/shadowrocket.conf
   ```
3. 首页「全局路由」选「配置」，打开开关

在家连着装了 LiteBox 的 Wi-Fi 时，手机上的代理可以关掉，路由器已经在分流了。

> 安卓配置在云端用 mihomo 内核实际跑过（FlClash / Clash Meta 用的就是 mihomo）：规则 2 秒下载完，分流正确。还没在真手机上测过；Shadowrocket 配置是按它的格式写的，没法在云端运行，有问题请反馈。

## 分组和分流

| 分组 | 用途 |
|---|---|
| 🚀 节点选择 | 默认代理出口：可选「♻️ 自动选择」、直连或任意节点 |
| ♻️ 自动选择 | 每 10 分钟测一次速，自动选延迟最低的节点 |
| 🤖 AI | ChatGPT / Claude / Gemini / Copilot / Grok 等单独选节点（AI 服务通常要固定地区） |
| YouTube、Netflix、Google、GitHub、Telegram、X、TikTok | 常用境外应用各一个分组，带应用图标，默认跟随「🚀 节点选择」；想让某个应用单独走某个节点（比如 Netflix 选解锁好的地区）就在面板里改它 |
| 🐟 漏网之鱼 | 没命中任何规则的流量，默认走代理，可改直连 |

规则从上往下匹配：局域网直连 → 作者的直连名单 → 屏蔽走代理的 QUIC → AI 名单 → YouTube / Netflix / Google / GitHub / Telegram / X / TikTok（各自的分组）→ 作者的代理名单 → 国内域名直连 → 国内 IP 直连 → 其余走「漏网之鱼」。

YouTube、Netflix、Google、GitHub、Telegram、X（Twitter）、TikTok 的规则来自 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat)（mrs 格式，每个只有几 KB），手机版 Shadowrocket 用的是 [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) 里对应的列表。手机版为了界面简洁，YouTube 和 Netflix 合成一个「📺 流媒体」分组，其余应用跟随「🚀 节点选择」。

国内 IP 规则带 `no-resolve`：有域名的连接只按域名判断，不在国内域名名单里的域名默认走代理（想直连就把「🐟 漏网之鱼」切成直连）。

规则文件每天自动更新一次。作者的名单里有少量他自己的域名和 IP，一般不影响使用。想调整规则的话，编辑 `/etc/litebox/config.yaml` 里的 `rules:`，然后执行 `litebox check && litebox restart`。

## 常用命令

| 命令 | 作用 |
|---|---|
| `litebox status` | 运行状态、当前 / 峰值内存、面板地址 |
| `litebox doctor` | **出问题时先跑这个**：一键自检并给出处理建议 |
| `litebox mem` | 详细内存信息 |
| `litebox sub '地址'` | 更换订阅（不带地址 = 查看当前订阅） |
| `litebox panel` | 显示面板的一键登录链接、密码和概览页链接 |
| `litebox route 域名` | 路由器自己访问一次，看 DNS、命中的规则和线路 |
| `litebox restart` / `stop` / `start` | 重启 / 停止 / 启动 |
| `litebox log` | 最近的内核日志 |
| `litebox direct` | **上不了网时用**：立即恢复直连并关闭开机自启 |
| `litebox update` | 升级到最新版，配置和订阅保留（连不上 GitHub 时加 `--mirror https://ghfast.top`） |
| `litebox accel` / `on` / `off` | 查看 / 开关流量加速（国内 IP 不进内核、TCP 走 iptables 转发，默认开） |
| `litebox quic on` / `off` | 屏蔽 / 放行走代理的 QUIC（默认屏蔽） |
| `litebox stack gvisor` | 切换 TUN 协议栈（`system` 默认 / `gvisor` / `mixed`），开着硬件加速出问题时用 |
| `litebox switch-back` | 停用 LiteBox，恢复安装时停用的 OpenClash 等插件 |
| `litebox uninstall` | 卸载（`--purge` 连配置和订阅一起删） |

升级：执行 `litebox update`；或下载新版安装包，按第 2、3 步重新执行 `install.sh`。配置、订阅、面板密钥都会保留。

升级时不会改动已有的 `config.yaml`。想用上新版模板里的改进（比如 QUIC 开关），执行 `litebox update --reset-config`：按新模板重新生成配置，订阅、端口、密钥保留，旧配置备份为 `config.yaml.old`。

**自动保护**：看门狗每 5 分钟检查一次。内核反复崩溃、系统放弃重启它时，看门狗会先试着拉起；拉不起来就恢复原来的 DNS，让家里设备直连上网，不会全家断网。内核恢复后自动重新接管。

## 工作原理

- **流量**：分三路
  - 国内 IP：防火墙（mangle 打标记 + 优先级 8999 的策略路由）直接走 WAN，**不进内核**，能用上硬件加速
  - 其余 TCP：iptables REDIRECT 到内核的 7892 端口，比经过 TUN 省 CPU
  - 其余 UDP：经 `litebox0` 虚拟网卡（TUN）交给内核
  - 规则由 `/usr/lib/litebox/firewall.sh` 管理，防火墙重载后自动加回。系统没有 ipset / ip-full，或者是 fw4 时，自动退回到全部走 TUN 的方式（`litebox doctor` 会写明原因），一样能用
- **分流**：国内域名在 DNS 阶段就返回真实 IP（`fake-ip-filter-mode: rule`，顺序和分流规则一致），其余域名用 fake-ip；拿到真实 IP 的连接靠嗅探 TLS / HTTP / QUIC 认出域名
- **DNS**：dnsmasq 把查询转给内核（127.0.0.1:1053，fake-ip 模式）。启动时自动设置，停止或卸载时原样恢复（原设置备份在 `/etc/litebox/dnsmasq.bak`）
- **防火墙**：安装时添加 `litebox` 区域，并允许 lan → litebox 转发，卸载时删除
- **文件位置**：内核在 `/usr/lib/litebox/`，配置、规则、面板、订阅缓存在 `/etc/litebox/`

## 已知限制

- IPv6 流量不经过代理。GL 固件默认关闭 IPv6，建议保持关闭
- 国内 IP 不进内核需要 ipset 和 ip-full（GL 固件一般自带）。没有时国内流量照常经过内核，只是多占 CPU
- 路由器自己发出的流量（比如 `litebox update`）仍全部经过内核，不影响局域网设备
- 访客网络（guest）默认不走代理
- 设备自己设置的 DoH（比如浏览器的「安全 DNS」）会绕过路由器 DNS，按 IP 分流时可能不准，建议关掉
- 按 GL 固件的 OpenWrt 21.02 设计，在云端的 OpenWrt 21.02.7 上完整测试过，v0.4.0 起已在一台 GL-MT3600BE 上实际运行。第一次安装时建议留一根网线，出问题就执行 `litebox direct`

## 许可证

本仓库的脚本和配置模板由本仓库作者编写。

离线包里附带的第三方程序原样取自官方 Release，并附上各自的许可证原文（在 `licenses/` 目录）：

- [mihomo](https://github.com/MetaCubeX/mihomo) v1.19.31：GPL-3.0。对应源码见 [官方 v1.19.31 标签](https://github.com/MetaCubeX/mihomo/tree/v1.19.31)，本仓库的 Release 里也附了一份源码包
- [zashboard](https://github.com/Zephyruso/zashboard) v3.29.1：MIT

分流规则在安装时从 [liandu2024/clash](https://github.com/liandu2024/clash) 和 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 下载，不包含在安装包里。
