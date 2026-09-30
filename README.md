# Q7Y · LiteBox

给 **GL.iNet GL-MT3600BE（Beryl 7）** 这类小内存 OpenWrt 路由器用的轻量透明代理，思路来自 [Open-Box](https://github.com/liandu2024/Open-Box) 和[这期视频](https://youtu.be/G_7AmjfSRQ8)：装好后在浏览器里切换节点、看连接和流量，分流规则直接用视频作者的[域名集](https://github.com/liandu2024/clash/tree/main/list)。

## 下载

到 [Releases 页面](https://github.com/lyr05142002-dot/Q7Y/releases/latest) 下载，或直接点：

| 文件 | 说明 |
|---|---|
| [**litebox-arm64-offline.zip**](https://github.com/lyr05142002-dot/Q7Y/releases/latest/download/litebox-arm64-offline.zip) | **推荐**。已带 mihomo 内核和面板（约 23MB），路由器连不上 GitHub 也能装。适用于 GL-MT3600BE 等 aarch64 路由器 |
| [litebox.zip](https://github.com/lyr05142002-dot/Q7Y/releases/latest/download/litebox.zip) | 只有脚本（几十 KB），安装时再联网下载内核和面板，支持 aarch64 / armv7 / x86_64 |

或者在路由器上用**一条命令**安装（需要路由器能访问 GitHub，见[方式二](#方式二路由器上一条命令安装)）。

## 为什么不直接装 Open-Box

| | GL-MT3600BE 实际情况 | Open-Box 要求 |
|---|---|---|
| CPU | MT7987A，4×Cortex-A53（`ARMv8 Processor rev 4`，aarch64） | aarch64 ✅ |
| 系统 | GL 官方固件 = OpenWrt 21.02，fw3 / iptables | OpenWrt 24+，nftables ❌ |
| 内存 | 512MB | 安装脚本要求 ≥ 约 440MB 且常驻 Node.js 面板 |

Open-Box 的面板是闭源的 Node.js 程序，无法修改，所以这里换成全部开源的组件，从头写了安装和管理脚本（**没有复制 Open-Box 的代码**）：

| 组件 | 作用 | 来源 |
|---|---|---|
| [mihomo](https://github.com/MetaCubeX/mihomo) v1.19.31 | 代理内核：订阅、分组、分流、DNS、tun 透明代理 | 官方 Release，SHA256 写死在 `install.sh` 里校验 |
| [zashboard](https://github.com/Zephyruso/zashboard) v3.29.1 | 网页面板（无字体版，约 2.7MB） | 官方 Release，同样校验 SHA256 |
| 分流规则 | AI / 直连 / 代理域名集 + 国内域名和 IP 段 | [liandu2024/clash](https://github.com/liandu2024/clash/tree/main/list)、[MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) |

## 内存

面板只是静态网页，由内核直接提供，**不另起进程**；常驻的只有 mihomo 一个进程。

- 省内存的设置：不加载 GeoSite/GeoIP 数据库（国内规则改用体积小得多的 mrs 格式）、关闭进程查找、TUN 用 system 协议栈、MTU 1500
- `GOMEMLIMIT=100MiB`：接近 100MB 时 Go 运行时会更积极地回收内存
- 看门狗：cron 每 5 分钟检查一次，常驻内存超过 **180MB** 自动重启内核
- 实测参考：在电脑上用同一份配置启动 mihomo v1.19.31（加载全部 10 个规则集，其中国内域名 11 万条、国内 IP 段 9600 条，还没有节点），常驻内存约 **41MB**。加上节点和日常连接，预计在 40–100MB 之间。**还没在 GL-MT3600BE 真机上测过**，装好后用 `litebox mem` 看实际数字

两个上限都在 `/etc/litebox/litebox.conf` 里改（`MEM_SOFT_MB`、`MEM_HARD_MB`），改完 `litebox restart`。

## 图文安装教程

![安装流程总览](docs/img/01-flow.png)

### 准备

在 GL 管理界面（默认 http://192.168.8.1）里：

1. 关闭 GL 自带的 VPN 客户端、AdGuard Home，以及其他代理插件（OpenClash、Passwall 等），否则会和 LiteBox 抢流量和 DNS
2. 「网络 → DNS」保持自动，不要设成手动 / 加密 DNS
3. 确认能用 SSH 登录路由器：用户名 `root`，密码和管理界面相同
4. 第一次安装时，最好用网线连着路由器，出问题时方便恢复

### 第 1 步：在电脑上下载安装包

打开 [Releases 页面](https://github.com/lyr05142002-dot/Q7Y/releases/latest)，下载 **litebox-arm64-offline.zip**，然后解压：

![下载安装包](docs/img/02-download.png)

### 第 2 步：把文件夹传到路由器

用 [HexHub](https://www.hexhub.cn/) 连上路由器，在 SFTP 页面把整个 `litebox` 文件夹拖到路由器的 `/tmp/` 目录：

![用 HexHub 上传](docs/img/03-upload.png)

没有 HexHub 的话，在解压目录里打开终端执行：

```bash
scp -O -r litebox root@192.168.8.1:/tmp/
```

### 第 3 步：SSH 登录路由器，运行安装脚本

```bash
sh /tmp/litebox/install.sh --sub '你的机场订阅地址'
```

![运行安装脚本](docs/img/04-install.png)

- 订阅支持 Clash / mihomo 格式，也支持 base64 节点链接
- 不加 `--sub` 也能装，安装时会询问；直接回车跳过的话，装好后不会启动，**网络不受影响**，之后执行 `litebox sub '订阅地址'` 就会启动
- 离线包里的内核和面板会优先使用，同样校验 SHA256；分流规则仍需联网下载，下载失败时内核启动后会经代理重试
- 用只有脚本的 `litebox.zip` 时，路由器访问 GitHub 慢，脚本会自动依次尝试 `ghfast.top`、`gh-proxy.com` 镜像；因为校验值写死在脚本里，镜像站换不了文件内容。也可以用 `--mirror https://你的镜像` 指定
- 面板端口默认 9090，被占用时加 `--port 9091`

### 第 4 步：打开网页面板

最省事的办法是复制安装结束时显示的**一键登录链接**，在手机或电脑浏览器里打开，会自动填好并进入面板。链接找不到了，就在路由器上运行 `litebox panel`。也可以按下图手动填写：

![打开面板](docs/img/05-panel.png)

进入面板后，在「代理」页切换节点：

![面板里的四个分组](docs/img/06-groups.png)

### 第 5 步：检查是否正常工作

![检查](docs/img/07-check.png)

上面几项都正常，就说明装好了。**上不了网时**，先执行 `litebox direct` 恢复直连，再运行下面这条命令，把输出发出来求助：

```bash
litebox status; litebox check; logread | grep -i -E 'mihomo|litebox' | tail -n 50
```

### 方式二：路由器上一条命令安装

路由器能访问 GitHub 时，不用经过电脑，SSH 登录后执行：

```bash
curl -fsSL https://raw.githubusercontent.com/lyr05142002-dot/Q7Y/main/get.sh | sh -s -- --sub '你的机场订阅地址'
```

访问 GitHub 不畅时，经镜像下载：

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/lyr05142002-dot/Q7Y/main/get.sh | sh -s -- --mirror https://ghfast.top --sub '你的机场订阅地址'
```

它会下载最新版的 `litebox.tar.gz`，校验 SHA256（校验值优先直接从 GitHub 取），然后运行同一个 `install.sh`，参数原样传过去。装好后从第 4 步继续。

## 分组和分流

| 分组 | 用途 |
|---|---|
| 🚀 节点选择 | 默认代理出口：可选「♻️ 自动选择」、直连或任意节点 |
| ♻️ 自动选择 | 每 10 分钟测一次速，自动选延迟最低的节点 |
| 🤖 AI | ChatGPT / Claude / Gemini / Copilot / Grok 等单独选节点（AI 服务通常要固定地区） |
| 🐟 漏网之鱼 | 没命中任何规则的流量，默认走代理，可改直连 |

规则从上往下匹配：局域网直连 → 作者的直连名单 → AI 名单 → 作者的代理名单 → 国内域名直连 → 国内 IP 直连 → 其余走「漏网之鱼」。

规则文件每天自动更新一次。作者的名单里有少量他自己的域名和 IP，一般不影响使用。想调整规则的话，编辑 `/etc/litebox/config.yaml` 里的 `rules:`，然后执行 `litebox check && litebox restart`。

## 常用命令

| 命令 | 作用 |
|---|---|
| `litebox status` | 运行状态、当前 / 峰值内存、面板地址 |
| `litebox mem` | 详细内存信息 |
| `litebox sub '地址'` | 更换订阅（不带地址 = 查看当前订阅） |
| `litebox panel` | 显示面板的一键登录链接和密码 |
| `litebox restart` / `stop` / `start` | 重启 / 停止 / 启动 |
| `litebox log` | 最近的内核日志 |
| `litebox direct` | **上不了网时用**：立即恢复直连并关闭开机自启 |
| `litebox uninstall` | 卸载（`--purge` 连配置和订阅一起删） |

升级：下载新版安装包，按第 2、3 步重新执行 `install.sh`（或再跑一次方式二的命令），配置、订阅、面板密钥都会保留。

## 工作原理

- **流量**：mihomo 创建 `litebox0` 虚拟网卡并接管路由（tun + auto-route），局域网设备的流量经它按规则分流；192.168.x.x 等内网地址不进内核
- **DNS**：dnsmasq 把查询转给内核（127.0.0.1:1053，fake-ip 模式）。启动时自动设置，停止或卸载时原样恢复（原设置备份在 `/etc/litebox/dnsmasq.bak`）
- **防火墙**：安装时添加 `litebox` 区域，并允许 lan → litebox 转发，卸载时删除
- **文件位置**：内核在 `/usr/lib/litebox/`，配置、规则、面板、订阅缓存在 `/etc/litebox/`

## 已知限制

- IPv6 流量不经过代理。GL 固件默认关闭 IPv6，建议保持关闭
- 访客网络（guest）默认不走代理
- 设备自己设置的 DoH（比如浏览器的「安全 DNS」）会绕过路由器 DNS，按 IP 分流时可能不准，建议关掉
- 只在 GL 固件的 OpenWrt 21.02 环境下设计，**尚未在真机上验证**。第一次安装时建议留一根网线，出问题就执行 `litebox direct`

## 许可证

本仓库的脚本和配置模板由本仓库作者编写。

离线包里附带的第三方程序原样取自官方 Release，并附上各自的许可证原文（在 `licenses/` 目录）：

- [mihomo](https://github.com/MetaCubeX/mihomo) v1.19.31：GPL-3.0。对应源码见 [官方 v1.19.31 标签](https://github.com/MetaCubeX/mihomo/tree/v1.19.31)，本仓库的 Release 里也附了一份源码包
- [zashboard](https://github.com/Zephyruso/zashboard) v3.29.1：MIT

分流规则在安装时从 [liandu2024/clash](https://github.com/liandu2024/clash) 和 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 下载，不包含在安装包里。
