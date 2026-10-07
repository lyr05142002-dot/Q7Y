# LiteBox 配置，由 install.sh 生成。
# 可以手动修改，改完执行 `litebox check` 检查、`litebox restart` 生效。
# 订阅地址请用 `litebox sub <新地址>` 修改（它只改带 LITEBOX_SUB 标记的那一行）。

mixed-port: __MIXED_PORT__
# TCP 由防火墙 REDIRECT 到这里（比经过 TUN 省 CPU），见 /usr/lib/litebox/firewall.sh
redir-port: 7892
allow-lan: true
bind-address: "*"
mode: rule
log-level: warning
ipv6: false
unified-delay: true
tcp-concurrent: false

# 以下几项是为了省内存：不查进程、不加载 GeoIP/GeoSite 数据库、不把 fake-ip 映射反复写进闪存
find-process-mode: 'off'
geodata-mode: false
geo-auto-update: false
profile:
  store-selected: true
  store-fake-ip: false

external-controller: 0.0.0.0:__PANEL_PORT__
secret: '__SECRET__'
external-ui: ui
external-ui-url: 'https://github.com/Zephyruso/zashboard/releases/download/v3.29.1/dist-no-fonts.zip'

# GL 官方固件是 OpenWrt 21.02（iptables），不支持 auto-redirect，只用 tun + auto-route
tun:
  enable: true
  device: litebox0
  stack: system # LITEBOX_STACK（litebox stack system|gvisor|mixed 切换）
  mtu: 1500
  auto-route: true
  auto-redirect: false
  auto-detect-interface: true
  strict-route: false
  dns-hijack:
    - any:53
    - tcp://any:53
  route-exclude-address:
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
    - 169.254.0.0/16
    - 224.0.0.0/4

# 拿到真实 IP 的连接（国内域名、直接按 IP 访问）从 TLS / HTTP / QUIC 里认出域名，按域名分流
sniffer:
  enable: true
  force-dns-mapping: true
  parse-pure-ip: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]

# 局域网设备照常向路由器的 dnsmasq 查询，dnsmasq 再转给这里（litebox 启动时自动设置，停止时恢复）
dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  # 国内域名返回真实 IP，配合防火墙让国内流量直接走 WAN、不进内核；顺序和下面的分流规则一致
  fake-ip-filter-mode: rule
  fake-ip-filter:
    - DOMAIN-SUFFIX,lan,real-ip
    - DOMAIN-SUFFIX,local,real-ip
    - DOMAIN-SUFFIX,localdomain,real-ip
    - DOMAIN-SUFFIX,msftconnecttest.com,real-ip
    - DOMAIN-SUFFIX,msftncsi.com,real-ip
    - DOMAIN-SUFFIX,pool.ntp.org,real-ip
    - DOMAIN-REGEX,^(time|ntp)\..*\.com$,real-ip
    - DOMAIN-REGEX,(^|\.)stun\.[^.]+\.[^.]+$,real-ip
    - DOMAIN,localhost.ptlogin2.qq.com,real-ip
    - RULE-SET,lb_direct,real-ip
    - RULE-SET,lb_ai,fake-ip
    - RULE-SET,lb_claude,fake-ip
    - RULE-SET,lb_chatgpt,fake-ip
    - RULE-SET,lb_gemini,fake-ip
    - RULE-SET,lb_copilot,fake-ip
    - RULE-SET,lb_grok,fake-ip
    - RULE-SET,ms_youtube,fake-ip
    - RULE-SET,ms_netflix,fake-ip
    - RULE-SET,ms_google,fake-ip
    - RULE-SET,ms_github,fake-ip
    - RULE-SET,ms_telegram,fake-ip
    - RULE-SET,ms_twitter,fake-ip
    - RULE-SET,lb_proxy,fake-ip
    - RULE-SET,cn_site,real-ip
    - MATCH,fake-ip
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  proxy-server-nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query

proxy-providers:
  sub:
    type: http
    url: '__SUB_URL__' # LITEBOX_SUB
    path: ./providers/sub.yaml
    interval: 43200
    proxy: DIRECT
    header:
      User-Agent:
        - clash.meta
    exclude-filter: '(?i)剩余|到期|官网|流量|套餐|expire|traffic'
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 600
      lazy: true

proxy-groups:
  - name: 🚀 节点选择
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.5" fill="none" stroke="rgb(47,111,222)" stroke-width="2"/><path d="M2.5 12h19M12 2.5c3.2 3.4 3.2 15.6 0 19M12 2.5c-3.2 3.4-3.2 15.6 0 19" fill="none" stroke="rgb(47,111,222)" stroke-width="1.6"/></svg>'
    type: select
    proxies:
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: ♻️ 自动选择
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M13.5 1.5 4 13.5h6.5l-1 9 9.5-12h-6.5z" fill="rgb(232,160,20)"/></svg>'
    type: url-test
    use:
      - sub
    url: https://www.gstatic.com/generate_204
    interval: 600
    tolerance: 50
    lazy: true
  - name: 🤖 AI
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 1.5l2.6 7.9L22.5 12l-7.9 2.6L12 22.5l-2.6-7.9L1.5 12l7.9-2.6z" fill="rgb(124,58,237)"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
    use:
      - sub
  - name: 📺 流媒体
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M23.5 6.2a3 3 0 0 0-2.1-2.1C19.5 3.5 12 3.5 12 3.5s-7.5 0-9.4.6A3 3 0 0 0 .5 6.2C0 8.1 0 12 0 12s0 3.9.5 5.8a3 3 0 0 0 2.1 2.1c1.9.6 9.4.6 9.4.6s7.5 0 9.4-.6a3 3 0 0 0 2.1-2.1c.5-1.9.5-5.8.5-5.8s0-3.9-.5-5.8zM9.5 15.6V8.4l6.3 3.6z" fill="rgb(255,0,0)"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
    use:
      - sub
  - name: 🐟 漏网之鱼
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M1.5 12c3-5.2 9.5-6.4 13.6-2.6L21.5 5v14l-6.4-4.4C11 18.4 4.5 17.2 1.5 12z" fill="rgb(14,165,233)"/><circle cx="7" cy="11" r="1.3" fill="rgb(255,255,255)"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - DIRECT

# lb_* 来自视频作者的域名集 https://github.com/liandu2024/clash/tree/main/list
# cn_* 来自 MetaCubeX/meta-rules-dat（mrs 二进制格式，比 GeoSite 数据库省内存得多）
# 规则文件由 install.sh 预先下载到 rules/，之后每天通过代理自动更新
rule-providers:
  lb_direct:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/Direct.list
    path: ./rules/lb_direct.list
    interval: 86400
    proxy: 🚀 节点选择
  lb_ai:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/AI.list
    path: ./rules/lb_ai.list
    interval: 86400
    proxy: 🚀 节点选择
  lb_claude:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/Claude.list
    path: ./rules/lb_claude.list
    interval: 86400
    proxy: 🚀 节点选择
  lb_chatgpt:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/ChatGPT.list
    path: ./rules/lb_chatgpt.list
    interval: 86400
    proxy: 🚀 节点选择
  lb_gemini:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/Gemini.list
    path: ./rules/lb_gemini.list
    interval: 86400
    proxy: 🚀 节点选择
  lb_copilot:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/Copilot.list
    path: ./rules/lb_copilot.list
    interval: 86400
    proxy: 🚀 节点选择
  lb_grok:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/Grok.list
    path: ./rules/lb_grok.list
    interval: 86400
    proxy: 🚀 节点选择
  lb_proxy:
    type: http
    behavior: classical
    format: text
    url: https://raw.githubusercontent.com/liandu2024/clash/main/list/Proxy.list
    path: ./rules/lb_proxy.list
    interval: 86400
    proxy: 🚀 节点选择
  # 常用境外服务，来自 MetaCubeX/meta-rules-dat
  ms_youtube:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/youtube.mrs
    path: ./rules/ms_youtube.mrs
    interval: 86400
    proxy: 🚀 节点选择
  ms_netflix:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/netflix.mrs
    path: ./rules/ms_netflix.mrs
    interval: 86400
    proxy: 🚀 节点选择
  ms_google:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/google.mrs
    path: ./rules/ms_google.mrs
    interval: 86400
    proxy: 🚀 节点选择
  ms_github:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.mrs
    path: ./rules/ms_github.mrs
    interval: 86400
    proxy: 🚀 节点选择
  ms_telegram:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/telegram.mrs
    path: ./rules/ms_telegram.mrs
    interval: 86400
    proxy: 🚀 节点选择
  ms_telegram_ip:
    type: http
    behavior: ipcidr
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/telegram.mrs
    path: ./rules/ms_telegram_ip.mrs
    interval: 86400
    proxy: 🚀 节点选择
  ms_twitter:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/twitter.mrs
    path: ./rules/ms_twitter.mrs
    interval: 86400
    proxy: 🚀 节点选择
  cn_site:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cn.mrs
    path: ./rules/cn_site.mrs
    interval: 86400
    proxy: 🚀 节点选择
  # 文本格式：防火墙也用这份列表建 ipset
  cn_ip:
    type: http
    behavior: ipcidr
    format: text
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cn.list
    path: ./rules/cn_ip.list
    interval: 86400
    proxy: 🚀 节点选择

rules:
  - DOMAIN-SUFFIX,lan,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - RULE-SET,lb_direct,DIRECT
  # 屏蔽走代理的 QUIC（UDP 443）：浏览器会自动退回 TCP；节点转发 UDP 差时 YouTube 等反而更流畅。国内站点不受影响
  - AND,((NETWORK,UDP),(DST-PORT,443),(NOT,((RULE-SET,cn_site)))),REJECT # LITEBOX_QUIC（litebox quic on|off 切换）
  - RULE-SET,lb_ai,🤖 AI
  - RULE-SET,lb_claude,🤖 AI
  - RULE-SET,lb_chatgpt,🤖 AI
  - RULE-SET,lb_gemini,🤖 AI
  - RULE-SET,lb_copilot,🤖 AI
  - RULE-SET,lb_grok,🤖 AI
  - RULE-SET,ms_youtube,📺 流媒体
  - RULE-SET,ms_netflix,📺 流媒体
  - RULE-SET,ms_google,🚀 节点选择
  - RULE-SET,ms_github,🚀 节点选择
  - RULE-SET,ms_telegram,🚀 节点选择
  - RULE-SET,ms_twitter,🚀 节点选择
  - RULE-SET,ms_telegram_ip,🚀 节点选择,no-resolve
  - RULE-SET,lb_proxy,🚀 节点选择
  - RULE-SET,cn_site,DIRECT
  # no-resolve：有域名的连接只按域名判断，不为了匹配 IP 段去解析每个境外域名（更快，也不会把境外域名发给国内 DNS）
  - RULE-SET,cn_ip,DIRECT,no-resolve
  - MATCH,🐟 漏网之鱼
