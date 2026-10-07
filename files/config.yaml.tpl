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
    - RULE-SET,lb_chatgpt,fake-ip
    - RULE-SET,lb_claude,fake-ip
    - RULE-SET,lb_gemini,fake-ip
    - RULE-SET,lb_copilot,fake-ip
    - RULE-SET,lb_grok,fake-ip
    - RULE-SET,ms_youtube,fake-ip
    - RULE-SET,ms_netflix,fake-ip
    - RULE-SET,ms_google,fake-ip
    - RULE-SET,ms_github,fake-ip
    - RULE-SET,ms_telegram,fake-ip
    - RULE-SET,ms_twitter,fake-ip
    - RULE-SET,ms_tiktok,fake-ip
    - RULE-SET,lb_ai,fake-ip
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
  # 常用 AI 各自一个分组，默认跟随「🤖 AI」：改「🤖 AI」就全部跟着变，也可以单独给某一个换节点
  # （分组图标的来源和许可证见安装包里的 licenses/README.txt）
  - name: ChatGPT
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" fill-rule="evenodd" d="M9.205 8.658v-2.26c0-.19.072-.333.238-.428l4.543-2.616c.619-.357 1.356-.523 2.117-.523 2.854 0 4.662 2.212 4.662 4.566 0 .167 0 .357-.024.547l-4.71-2.759a.797.797 0 00-.856 0l-5.97 3.473zm10.609 8.8V12.06c0-.333-.143-.57-.429-.737l-5.97-3.473 1.95-1.118a.433.433 0 01.476 0l4.543 2.617c1.309.76 2.189 2.378 2.189 3.948 0 1.808-1.07 3.473-2.76 4.163zM7.802 12.703l-1.95-1.142c-.167-.095-.239-.238-.239-.428V5.899c0-2.545 1.95-4.472 4.591-4.472 1 0 1.927.333 2.712.928L8.23 5.067c-.285.166-.428.404-.428.737v6.898zM12 15.128l-2.795-1.57v-3.33L12 8.658l2.795 1.57v3.33L12 15.128zm1.796 7.23c-1 0-1.927-.332-2.712-.927l4.686-2.712c.285-.166.428-.404.428-.737v-6.898l1.974 1.142c.167.095.238.238.238.428v5.233c0 2.545-1.974 4.472-4.614 4.472zm-5.637-5.303l-4.544-2.617c-1.308-.761-2.188-2.378-2.188-3.948A4.482 4.482 0 014.21 6.327v5.423c0 .333.143.571.428.738l5.947 3.449-1.95 1.118a.432.432 0 01-.476 0zm-.262 3.9c-2.688 0-4.662-2.021-4.662-4.519 0-.19.024-.38.047-.57l4.686 2.71c.286.167.571.167.856 0l5.97-3.448v2.26c0 .19-.07.333-.237.428l-4.543 2.616c-.619.357-1.356.523-2.117.523zm5.899 2.83a5.947 5.947 0 005.827-4.756C22.287 18.339 24 15.84 24 13.296c0-1.665-.713-3.282-1.998-4.448.119-.5.19-.999.19-1.498 0-3.401-2.759-5.947-5.946-5.947-.642 0-1.26.095-1.88.31A5.962 5.962 0 0010.205 0a5.947 5.947 0 00-5.827 4.757C1.713 5.447 0 7.945 0 10.49c0 1.666.713 3.283 1.998 4.448-.119.5-.19 1-.19 1.499 0 3.401 2.759 5.946 5.946 5.946.642 0 1.26-.095 1.88-.309a5.96 5.96 0 004.162 1.713z"/></svg>'
    type: select
    proxies:
      - 🤖 AI
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: Claude
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb(217,119,87)" fill-rule="evenodd" d="M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z"/></svg>'
    type: select
    proxies:
      - 🤖 AI
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: Gemini
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb(66,133,244)" fill-rule="evenodd" d="M20.616 10.835a14.147 14.147 0 01-4.45-3.001 14.111 14.111 0 01-3.678-6.452.503.503 0 00-.975 0 14.134 14.134 0 01-3.679 6.452 14.155 14.155 0 01-4.45 3.001c-.65.28-1.318.505-2.002.678a.502.502 0 000 .975c.684.172 1.35.397 2.002.677a14.147 14.147 0 014.45 3.001 14.112 14.112 0 013.679 6.453.502.502 0 00.975 0c.172-.685.397-1.351.677-2.003a14.145 14.145 0 013.001-4.45 14.113 14.113 0 016.453-3.678.503.503 0 000-.975 13.245 13.245 0 01-2.003-.678z"/></svg>'
    type: select
    proxies:
      - 🤖 AI
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: Copilot
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb(0,120,212)" fill-rule="evenodd" d="M9 23l.073-.001a2.53 2.53 0 01-2.347-1.838l-.697-2.433a2.529 2.529 0 00-2.426-1.839h-.497l-.104-.002c-4.485 0-2.935-5.278-1.75-9.225l.162-.525C2.412 3.99 3.883 1 6.25 1h8.86c1.12 0 2.106.745 2.422 1.829l.715 2.453a2.53 2.53 0 002.247 1.823l.147.005.534.001c3.557.115 3.088 3.745 2.156 7.206l-.113.413c-.154.548-.315 1.089-.47 1.607l-.163.525C21.588 20.01 20.116 23 17.75 23h-8.75zm8.22-15.89l-3.856.001a2.526 2.526 0 00-2.35 1.615L9.21 15.04a2.529 2.529 0 01-2.43 1.847l3.853.002c1.056 0 1.992-.661 2.361-1.644l1.796-6.287a2.529 2.529 0 012.43-1.848z"/></svg>'
    type: select
    proxies:
      - 🤖 AI
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: Grok
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" fill-rule="evenodd" d="M9.27 15.29l7.978-5.897c.391-.29.95-.177 1.137.272.98 2.369.542 5.215-1.41 7.169-1.951 1.954-4.667 2.382-7.149 1.406l-2.711 1.257c3.889 2.661 8.611 2.003 11.562-.953 2.341-2.344 3.066-5.539 2.388-8.42l.006.007c-.983-4.232.242-5.924 2.75-9.383.06-.082.12-.164.179-.248l-3.301 3.305v-.01L9.267 15.292M7.623 16.723c-2.792-2.67-2.31-6.801.071-9.184 1.761-1.763 4.647-2.483 7.166-1.425l2.705-1.25a7.808 7.808 0 00-1.829-1A8.975 8.975 0 005.984 5.83c-2.533 2.536-3.33 6.436-1.962 9.764 1.022 2.487-.653 4.246-2.34 6.022-.599.63-1.199 1.259-1.682 1.925l7.62-6.815"/></svg>'
    type: select
    proxies:
      - 🤖 AI
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  # 常用境外应用各自一个分组，默认跟随「🚀 节点选择」，想单独换节点时在面板里改
  - name: YouTube
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb(255,0,0)" d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: Netflix
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb(229,9,20)" d="m5.398 0 8.348 23.602c2.346.059 4.856.398 4.856.398L10.113 0H5.398zm8.489 0v9.172l4.715 13.33V0h-4.715zM5.398 1.5V24c1.873-.225 2.81-.312 4.715-.398V14.83L5.398 1.5z"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: Google
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb(66,133,244)" d="M12.48 10.92v3.28h7.84c-.24 1.84-.853 3.187-1.787 4.133-1.147 1.147-2.933 2.4-6.053 2.4-4.827 0-8.6-3.893-8.6-8.72s3.773-8.72 8.6-8.72c2.6 0 4.507 1.027 5.907 2.347l2.307-2.307C18.747 1.44 16.133 0 12.48 0 5.867 0 .307 5.387.307 12s5.56 12 12.173 12c3.573 0 6.267-1.173 8.373-3.36 2.16-2.16 2.84-5.213 2.84-7.667 0-.76-.053-1.467-.173-2.053H12.48z"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: GitHub
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: Telegram
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="rgb(38,165,228)" d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: X
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" d="M14.234 10.162 22.977 0h-2.072l-7.591 8.824L7.251 0H.258l9.168 13.343L.258 24H2.33l8.016-9.318L16.749 24h6.993zm-2.837 3.299-.929-1.329L3.076 1.56h3.182l5.965 8.532.929 1.329 7.754 11.09h-3.182z"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
    use:
      - sub
  - name: TikTok
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="currentColor" d="M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>'
    type: select
    proxies:
      - 🚀 节点选择
      - ♻️ 自动选择
      - DIRECT
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
  ms_tiktok:
    type: http
    behavior: domain
    format: mrs
    url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/tiktok.mrs
    path: ./rules/ms_tiktok.mrs
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
  # 先按具体的 AI 名单分到各自分组（含它们要用的登录、静态资源域名）
  - RULE-SET,lb_chatgpt,ChatGPT
  - RULE-SET,lb_claude,Claude
  - RULE-SET,lb_gemini,Gemini
  - RULE-SET,lb_copilot,Copilot
  - RULE-SET,lb_grok,Grok
  # 常用应用排在 AI 总名单前：总名单里有 x.com、googleapis.com、gstatic.com 这类通用域名，
  # 放前面会把 X、Google 的流量抢到「🤖 AI」。各 AI 自己要用的这类域名已经在上面的具体名单里
  - RULE-SET,ms_youtube,YouTube
  - RULE-SET,ms_netflix,Netflix
  - RULE-SET,ms_google,Google
  - RULE-SET,ms_github,GitHub
  - RULE-SET,ms_telegram,Telegram
  - RULE-SET,ms_twitter,X
  - RULE-SET,ms_tiktok,TikTok
  - RULE-SET,lb_ai,🤖 AI
  - RULE-SET,ms_telegram_ip,Telegram,no-resolve
  - RULE-SET,lb_proxy,🚀 节点选择
  - RULE-SET,cn_site,DIRECT
  # no-resolve：有域名的连接只按域名判断，不为了匹配 IP 段去解析每个境外域名（更快，也不会把境外域名发给国内 DNS）
  - RULE-SET,cn_ip,DIRECT,no-resolve
  - MATCH,🐟 漏网之鱼
