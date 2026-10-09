# 更新记录

每个版本的完整说明（含下载说明）在 [docs/releases](docs/releases/)，发布后也在 [Releases 页面](https://github.com/lyr05142002-dot/Q7Y/releases)。

## v0.7.1

- 从旧版升级时，配置里没有视频作者个人条目的开关就自动补上（注释行，默认不启用，分流结果不变；改完先过 `mihomo -t` 才替换，找不到插入位置就不改），`litebox personal on` 不用再 `--reset-config`。v0.2.0 到 v0.6.1 的配置模板都验证过
- README：说明为什么保持 `store-fake-ip` 关闭（实测打开后每个新域名首次解析多约 20ms，而且一个接一个排队：同时解析 40 个新域名 0.84 秒，关着 0.02 秒；放到内存里也一样，慢在内核的批量提交，和闪存无关）；更正「升级不会改动 config.yaml」的说法
- CI 的 `actions/checkout` 升到 v5（v4 用的 Node 20 已弃用）
- 测试：升级测试模拟没有个人条目开关的旧配置，检查补上开关、默认不启用、`personal on/off` 直接可用

## v0.7.0

**安全**

- 一键安装脚本 `get.sh` 随 Release 发布，并附 `SHA256SUMS`；Release 说明末尾列出所有文件的校验值。README 的推荐安装命令改为「先下载、核对 SHA256、再执行」，一行 `curl | sh` 保留为「快速方式」。README 里写的校验值由 CI 检查，和 `get.sh` 对不上会构建失败
- `litebox update` 先用同一个 Release 的 `SHA256SUMS` 核对 `get.sh`，对不上就停止，什么都不改（经镜像时校验文件优先直接从 GitHub 取）
- 分流规则改为校验后再更新：规则集都改成 `type: file`，内核不再自己下载（实测内核自己下载到出错网页或空文件时会照样覆盖，规则数变成 0）。新增 `litebox rules-update`（每天凌晨自动跑）：检查空文件、网页、格式（文本名单 90% 以上的行要像规则，mrs 文件头要对）、比上一版少一半以上；不通过就继续用旧版。通过了才原子替换文件，再只让内核重读这一个规则集（实测不重启、不断开连接、不打乱 fake-ip）。结果写进系统日志和 `/etc/litebox/rules-update.log`，`litebox doctor` 显示上次更新情况
- 视频作者名单里他个人用的条目（他的网站、他用的机场的域名、VPS 和宽带 IP、一批单独的 IP 段）从默认规则里分出去，放进 `rules/personal_direct.list`、`rules/personal_proxy.list`，默认不启用（`litebox personal on|off`）。分离清单是 `files/personal-rules.txt`
- 旧配置升级时自动把规则集从 `http` 改成 `file`，改之前备份为 `config.yaml.pre-0.7`

**可靠性**

- 修复：开着访客网络（或 Docker 等其他能上网的防火墙区域）时，这些网络**整个断网**——内核的 TUN 路由把它们的流量也带进来，防火墙却只放行了 lan。现在凡是能转发到 wan 的区域都自动放行到 litebox（安装时和每次启动时检查），和主网络按同样的规则分流
- 缺 ipset / ip-full、或者是 fw4 时的降级模式：安装结尾和 `litebox status` 醒目提示「当前为降级模式」、原因和补装命令（`firewall.sh check` 统一判断）
- 看门狗检查间隔可配置：`litebox watchdog-interval 分钟数`（1–30，默认 5），写在 `litebox.conf` 的 `WATCHDOG_MIN`，升级时保留
- 有规则文件缺失（比如离线安装时没下载到）时，看门狗每小时在后台补下载一次；安装完成时也会立即在后台补
- 评估了内核重启时 fake-ip 对应表丢失的影响（`store-fake-ip: false`），写进 README 已知限制

**文档**

- README：测试情况分开写真机数据（只验证过 v0.4.0）、x86 云端数据、还没实机验证的（手机版、GL 官方固件、LuCI 页面）；手机版页面地址改成明确的链接；已知限制补充 IPv6、访客网络、设备加密 DNS 的检查和关闭方法，以及内核重启后的影响

**测试**：自动测试新增规则校验（网页、空文件、少一半、mrs 格式、正常更新）、个人条目分离（样本和真实名单）、`litebox personal`、旧配置迁移、看门狗间隔、访客区域放行、`litebox update` 校验（正常和被改过的 `get.sh`）、降级提示，以及在内核层面验证「下载到出错网页后规则不变、正常更新不重启内核」。修正测试本身的问题：「能上网」的那一轮容器以前其实是断网的（OpenWrt 开机时把 eth0 并进了 br-lan，Docker 给的地址被换掉），所以真实下载从没测到过；现在按真实路由器配了 wan 口，规则名单、依赖和面板都在 CI 里真实下载，并严格检查默认规则里没有作者个人条目

## v0.6.1

- 概览页的 OpenAI 延迟改为 Claude（经 Claude 分组测）
- 新增「节点稳定性」：每个节点访问 Claude（或 Google、GitHub）的成功率、平均延迟和最近 20 次结果，标出当前节点和最稳的节点，可一键切换
- CI 检查概览页和 LuCI 页面的脚本能解析
- 截图更新，教程配图里的 SSH 指纹、示例密码和订阅地址打码

## v0.6.0

- 路由器后台（LuCI 21.02+）新增「服务 → LiteBox」页面：订阅地址框在最上面，显示节点数、套餐流量、到期日，可启停、打开面板
- 安装时问订阅更清楚（说明框、粘错重问、去掉多余空格和引号）；概览页加「机场订阅」卡片；新增 `litebox sub-update`、`litebox enable`
- 新增 ChatGPT、Claude、Gemini、Copilot、Grok 分组（默认跟随「🤖 AI」）
- 修复：AI 总名单排在最前，让具体的 AI 名单匹配不到，还把 x.com、googleapis.com 等抢到「🤖 AI」
- 修复：没填订阅时开机仍启动内核并接管 DNS；防火墙加速层加锁避免并发加删规则；安装时不再误判 running 乱报的插件为冲突；不再误改 AdGuard Home 的 DNS；缺 curl 时安装

## v0.5.1

- YouTube、Netflix、Google、GitHub、Telegram、X、TikTok 各自一个分组，带图标；「📺 流媒体」拆成 YouTube 和 Netflix；新增 TikTok 规则

## v0.5.0

- 新的概览页：站点延迟走势、连接 / 内存 / 速率实时曲线、分流统计、按月流量
- 路由测试（浏览器真实访问一次，显示 DNS、进入内核方式、命中规则、线路）；`litebox route 域名`
- 分组带图标（内嵌 SVG）

## v0.4.1

- YouTube、Google、GitHub、Telegram、Twitter 专门的规则，新分组「📺 流媒体」
- 修复 `litebox doctor` 误报 passwall / shadowsocksr 冲突

## v0.4.0

- 国内 IP 不进内核（ipset + 策略路由），境外 TCP 走 iptables 转发；条件不满足时自动退回全部走 TUN
- `litebox accel on|off`，`doctor` 显示加速状态

## v0.3.0

- 傻瓜式安装：一条命令、一路回车；自动停用并可切回 OpenClash 等插件（`litebox switch-back`），自动沿用已有订阅，装不上自动恢复

## v0.2.2

- `find-process-mode` 加引号，避免被 OpenClash 等工具改写成布尔值导致内核起不来

## v0.2.1

- 修复连不上规则下载地址时 v0.2.0 安装中断；新增发布前在 OpenWrt 21.02 里自动安装测试

## v0.2.0

- 手机版（安卓 FlClash / Clash Meta、iPhone Shadowrocket）
- 默认屏蔽走代理的 QUIC，国内 IP 规则 `no-resolve`，`litebox stack` 切换协议栈
- 看门狗自愈，`litebox update`、`--reset-config`

## v0.1.2

- 首次安装不再打印误导的 `Command failed`；`doctor` 在没有 curl 时不误报

## v0.1.1

- 新增 `litebox doctor` 一键自检

## v0.1.0

- 首个版本：mihomo 内核 + zashboard 面板 + 视频作者的分流规则，一键安装脚本，`litebox` 管理命令，内存看门狗
