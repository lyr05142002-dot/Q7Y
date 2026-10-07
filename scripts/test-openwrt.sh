#!/bin/sh
# 在 Docker 里的 OpenWrt 21.02（和 GL 官方固件同一版本）上把 LiteBox 完整装一遍并检查。
# GitHub Actions 发布前自动运行；本机有 Docker 也可以手动运行：sh scripts/test-openwrt.sh
#
# 跑两轮：
#   offline：容器断网，规则下载全部失败，走「交给内核经代理下载」那条路
#   online ：容器能上网，走正常下载
# 每轮检查：安装、服务、DNS 接管、TUN、doctor、QUIC / 协议栈开关、看门狗自愈、升级保留配置、--reset-config、卸载还原

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=openwrt/rootfs:x86-64-21.02.7
# 带 ipset 和 ip-full 的 OpenWrt（ImmortalWrt），用来测完整的加速层
IMAGE_IPSET=sulinggg/openwrt:x86_64
WORK=$(mktemp -d)
FAILS=0
trap 'docker rm -f lb-offline lb-online lb-conflict lb-ipset >/dev/null 2>&1; rm -rf "$WORK"' EXIT

pinned() { sed -n "s/^$1=//p" "$ROOT/install.sh" | head -n 1; }
MIHOMO_VER=$(pinned MIHOMO_VER)
MIHOMO_SHA=$(pinned MIHOMO_SHA_amd64)

# 测试用安装包：仓库里的脚本 + x86_64 内核（相当于 x86 版的离线包）
PKG=$WORK/litebox
mkdir -p "$PKG/files"
cp "$ROOT/install.sh" "$PKG/"
cp "$ROOT"/files/* "$PKG/files/"
curl -fsSL --retry 3 -o "$PKG/mihomo-linux-amd64-$MIHOMO_VER.gz" \
	"https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VER/mihomo-linux-amd64-$MIHOMO_VER.gz"
echo "$MIHOMO_SHA  $PKG/mihomo-linux-amd64-$MIHOMO_VER.gz" | sha256sum -c - >/dev/null

# 国内 IP 列表（断网的容器下载不了，预先放进去）
curl -fsSL --retry 3 -o "$WORK/cn_ip.list" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cn.list"

# 假订阅：容器里用 uhttpd 提供，节点连不上也没关系，只测安装和接管逻辑
mkdir -p "$WORK/sub"
printf 'proxies:\n  - {name: test, type: socks5, server: 127.0.0.1, port: 9}\n' > "$WORK/sub/sub.yaml"

# 规则下载校验用的样本：出错网页、空文件、正常名单、只剩几行的名单、带作者个人条目的直连名单
mkdir -p "$WORK/sub/rules"
printf '<!DOCTYPE html>\n<html><head><title>502 Bad Gateway</title></head><body>error</body></html>\n' > "$WORK/sub/rules/bad.html"
: > "$WORK/sub/rules/empty.list"
printf 'DOMAIN-SUFFIX,grok.com\nDOMAIN-SUFFIX,x.ai\nDOMAIN,new.example\n' > "$WORK/sub/rules/good.list"
printf 'DOMAIN-SUFFIX,a.example\nDOMAIN-SUFFIX,b.example\nDOMAIN-SUFFIX,c.example\n' > "$WORK/sub/rules/short.list"
cat > "$WORK/sub/rules/direct.list" <<'EOF'
# MyList
DOMAIN-SUFFIX,angeworld.cc
DOMAIN-SUFFIX,jlip.cc
# VPS
IP-CIDR,216.40.86.112/24,no-resolve
IP-CIDR,223.5.5.5/32,no-resolve
DOMAIN-SUFFIX,bilibili.com
DOMAIN-SUFFIX,qq.com
DOMAIN-KEYWORD,baidu
EOF
cat > "$WORK/rules-test.yaml" <<'EOF'
rule-providers:
  t_html:
    type: file
    behavior: classical
    format: text
    url: http://127.0.0.1:8765/rules/bad.html
    path: ./rules/t_html.list
  t_empty:
    type: file
    behavior: classical
    format: text
    url: http://127.0.0.1:8765/rules/empty.list
    path: ./rules/t_empty.list
  t_short:
    type: file
    behavior: classical
    format: text
    url: http://127.0.0.1:8765/rules/short.list
    path: ./rules/t_short.list
  t_good:
    type: file
    behavior: classical
    format: text
    url: http://127.0.0.1:8765/rules/good.list
    path: ./rules/t_good.list
  t_mrs:
    type: file
    behavior: domain
    format: mrs
    url: http://127.0.0.1:8765/rules/good.list
    path: ./rules/t_mrs.mrs
  lb_direct:
    type: file
    behavior: classical
    format: text
    url: http://127.0.0.1:8765/rules/direct.list
    path: ./rules/t_direct.list
rules:
  - MATCH,DIRECT
EOF
# litebox update 校验用的假 Release：一个正常的、一个 get.sh 被改过的
mkdir -p "$WORK/sub/rel" "$WORK/sub/relbad"
printf '#!/bin/sh\necho "STUB_GETSH_RAN $*"\n' > "$WORK/sub/rel/get.sh"
(cd "$WORK/sub/rel" && sha256sum get.sh > SHA256SUMS)
cp "$WORK/sub/rel/SHA256SUMS" "$WORK/sub/relbad/SHA256SUMS"
printf '#!/bin/sh\necho "STUB_GETSH_RAN tampered"\n' > "$WORK/sub/relbad/get.sh"

# 本地没有才拉取；Docker Hub 偶尔限流（429），重试几次
pull() {
	docker image inspect "$1" >/dev/null 2>&1 && return 0
	for i in 1 2 3 4 5; do
		docker pull -q "$1" >/dev/null && return 0
		sleep $((i * 20))
	done
	return 1
}
pull "$IMAGE"
pull "$IMAGE_IPSET"

ok() { echo "  ✓ $*"; }
bad() {
	echo "  ✗ $*"
	FAILS=$((FAILS + 1))
	# 在 GitHub Actions 上同时记成注解：日志看不到时，从运行页面或接口也能知道哪一项失败
	if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error title=测试失败::${CUR_ROUND:-}：$*"; fi
}
check() { # 说明 命令…
	local what=$1
	shift
	if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi
}

run_round() { # 名字 docker网络参数
	local name=$1 net=$2 c out left
	CUR_ROUND=$name
	c=lb-$name
	echo
	echo "== $name"
	docker rm -f "$c" >/dev/null 2>&1 || true
	# shellcheck disable=SC2086
	docker run -d --privileged --name "$c" $net "$IMAGE" /sbin/init >/dev/null
	sleep 8
	x() { docker exec "$c" sh -c "$1"; }
	if [ -z "$net" ]; then
		# OpenWrt 开机时会把 eth0 并进 br-lan、改成 192.168.1.1，Docker 给的地址和默认路由就没了，容器其实上不了网。
		# 按真实路由器的样子配：eth0 当 wan（用 Docker 分的地址），br-lan 留作 lan
		set -- $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}/{{.IPPrefixLen}} {{.Gateway}}{{end}}' "$c")
		x "uci -q delete network.@device[0].ports; uci set network.@device[0].bridge_empty=1
			uci set network.wan=interface; uci set network.wan.device=eth0; uci set network.wan.proto=static
			uci set network.wan.ipaddr=$1; uci set network.wan.gateway=$2
			uci set network.wan.dns=\"\$(awk '/^nameserver/ { print \$2; exit }' /etc/resolv.conf)\"
			uci commit network; /etc/init.d/network restart
			for i in \$(seq 1 20); do ip route | grep -q '^default' && break; sleep 1; done" >/dev/null 2>&1 || true
		if x 'wget -q -T 15 -O /dev/null https://raw.githubusercontent.com/liandu2024/clash/main/list/AI.list' >/dev/null 2>&1; then
			ok "容器能上网（eth0 当 wan）"
		elif [ -n "${CI:-}" ]; then
			bad "容器连不上外网：$(x 'ip route; cat /etc/resolv.conf' 2>&1 | tr '\n' ' ')"
		else
			echo "  - 这台机器的容器连不上外网，下载相关的检查会跳过"
		fi
	fi
	docker cp "$PKG" "$c:/root/litebox"
	docker cp "$WORK/sub" "$c:/root/sub"
	docker cp "$WORK/rules-test.yaml" "$c:/root/rules-test.yaml"
	x 'uhttpd -p 127.0.0.1:8765 -h /root/sub'
	x 'mkdir -p /etc/crontabs; /etc/init.d/cron enable; /etc/init.d/cron start' >/dev/null 2>&1 || true

	out=$(x 'sh /root/litebox/install.sh --sub "http://127.0.0.1:8765/sub.yaml?token=SECRET&a=it'"'"'s" < /dev/null 2>&1') || true
	echo "$out" | sed 's/^/    | /'
	if echo "$out" | grep -qE 'parameter not set|not found|syntax error|错误：'; then bad "安装输出里有脚本错误"; fi
	if echo "$out" | grep -q '安装完成'; then ok "安装完成"; else bad "安装没有完成：$(echo "$out" | tail -n 6 | tr '\n' ' ')"; return; fi
	sleep 3

	check "服务在运行" x 'litebox status | grep -q 运行中'
	check "配置检查通过" x 'litebox check'
	# 这个镜像没有 ipset：安装结尾和 status 都要醒目提示降级模式和补装命令
	if echo "$out" | grep -q '当前为降级模式'; then ok "安装结尾提示降级模式"; else bad "安装结尾提示降级模式"; fi
	check "status 显示降级原因和补装命令" x 'litebox status | grep -q "当前为降级模式" && litebox status | grep -q "原因：.*没有 ipset" && litebox status | grep -q "opkg install ipset"'
	check "规则集都是 type: file（内核不自己下载）" x 'sed -n "/^rule-providers:/,/^rules:/p" /etc/litebox/config.yaml | grep -q "type: file" && ! sed -n "/^rule-providers:/,/^rules:/p" /etc/litebox/config.yaml | grep -q "type: http"'
	check "规则每天校验后更新的定时任务" x 'grep -q "^[0-9]* 4 \* \* \* /usr/bin/litebox rules-update" /etc/crontabs/root'
	check "DNS 已交给内核" x 'uci -q get dhcp.@dnsmasq[0].server | grep -q "127.0.0.1#1053"'
	check "fake-ip 解析" x 'nslookup example.com 127.0.0.1 | grep -q "198\.18\."'
	check "虚拟网卡 litebox0" x 'ip link show litebox0'
	check "防火墙 litebox 区域" x '[ "$(uci -q get firewall.litebox_zone)" = zone ]'
	check "看门狗定时任务" x 'grep -q "litebox watchdog" /etc/crontabs/root'
	x 'for i in $(seq 1 30); do [ -f /tmp/litebox-fw.state ] && break; sleep 1; done' || true
	check "加速层：没有 ipset 时自动退回（只转发 fake-ip 的 TCP）" x 'grep -q "^nobypass:没有 ipset" /tmp/litebox-fw.state && grep -q "^redir:7892" /tmp/litebox-fw.state && iptables -w -t nat -S LITEBOX_NAT | grep -q "198.18.0.0/16.*REDIRECT"'
	check "accel off 撤掉规则" x 'litebox accel off >/dev/null && [ "$(cat /tmp/litebox-fw.state)" = off ] && ! iptables -w -t nat -S | grep -q LITEBOX'
	check "accel on 恢复规则" x 'litebox accel on >/dev/null && iptables -w -t nat -S PREROUTING | grep -q LITEBOX_NAT'
	check "doctor 能跑完" x 'litebox doctor | grep -q 结论'
	check "doctor 不泄露订阅 token" x '! litebox doctor | grep -q SECRET'
	check "订阅地址原样保存（含 & 和单引号）" x '[ "$(litebox sub)" = "http://127.0.0.1:8765/sub.yaml?token=SECRET&a=it'"'"'s" ]'
	check "粘贴时带的空格和引号会去掉" x 'litebox sub "  \"http://127.0.0.1:8765/sub.yaml?p=1\"  " --no-wait && [ "$(litebox sub)" = "http://127.0.0.1:8765/sub.yaml?p=1" ]'
	check "不是网址的订阅会被拒绝" x '! litebox sub "abc" && [ "$(litebox sub)" = "http://127.0.0.1:8765/sub.yaml?p=1" ]'
	x 'litebox sub "http://127.0.0.1:8765/sub.yaml?token=SECRET&a=it'"'"'s" --no-wait' >/dev/null 2>&1 || true
	# 规则下载校验：网页、空文件、少一半以上、不是 mrs 的都不替换，旧文件原样保留；正常的照常更新
	x 'cd /etc/litebox/rules && printf "DOMAIN-SUFFIX,old.example\n" > t_html.list && printf "DOMAIN-SUFFIX,old.example\n" > t_empty.list && for i in $(seq 1 40); do echo "DOMAIN-SUFFIX,s$i.example"; done > t_short.list && printf "OLD" > t_mrs.mrs && rm -f t_good.list t_direct.list && litebox rules-update --from /root/rules-test.yaml' >/dev/null 2>&1 || true
	check "规则：下载到出错网页时不替换，旧规则保留" x 'grep -qx "DOMAIN-SUFFIX,old.example" /etc/litebox/rules/t_html.list'
	check "规则：下载到空文件时不替换" x 'grep -qx "DOMAIN-SUFFIX,old.example" /etc/litebox/rules/t_empty.list'
	check "规则：比上一版少一半以上时不替换" x '[ "$(grep -c . /etc/litebox/rules/t_short.list)" = 40 ]'
	check "规则：格式不对的 mrs 不替换" x '[ "$(cat /etc/litebox/rules/t_mrs.mrs)" = OLD ]'
	check "规则：正常的名单照常更新" x 'grep -qx "DOMAIN,new.example" /etc/litebox/rules/t_good.list'
	check "规则：更新结果写进日志" x 'tail -n 1 /etc/litebox/rules-update.log | grep -q "没更新（继续用旧版）.*t_html（下载到的是网页" && tail -n 1 /etc/litebox/rules-update.log | grep -q "t_empty（下载到的是空文件）"'
	check "个人条目：从直连名单里分出去" x '! grep -qi "angeworld\|jlip.cc\|216.40.86" /etc/litebox/rules/t_direct.list && grep -q "bilibili.com" /etc/litebox/rules/t_direct.list && grep -q "223.5.5.5" /etc/litebox/rules/t_direct.list'
	check "个人条目：放进单独的文件" x 'grep -q "angeworld.cc" /etc/litebox/rules/personal_direct.list && grep -q "216.40.86.112" /etc/litebox/rules/personal_direct.list && ! grep -q "223.5.5.5" /etc/litebox/rules/personal_direct.list'
	check "个人条目：默认不启用" x 'litebox personal | grep -q 未启用 && ! grep -q "^  - RULE-SET,personal_direct" /etc/litebox/config.yaml'
	check "个人条目：litebox personal on / off" x 'litebox personal on >/dev/null && grep -q "^  - RULE-SET,personal_direct,DIRECT" /etc/litebox/config.yaml && litebox check >/dev/null && litebox personal off >/dev/null && ! grep -q "^  - RULE-SET,personal_direct" /etc/litebox/config.yaml'
	if [ "$name" = online ] && [ -z "${CI:-}" ] && ! x '[ -s /etc/litebox/rules/lb_direct.list ]'; then
		echo "  - 跳过「真实名单里没有作者个人条目」：这台机器的容器连不上 GitHub（GitHub Actions 上会严格检查）"
	elif [ "$name" = online ]; then
		# 能上网的这一轮下载的是作者真实的名单：默认规则里要搜不到他的个人条目
		if x '[ -s /etc/litebox/rules/lb_direct.list ] && [ -s /etc/litebox/rules/lb_proxy.list ]'; then
			ok "真实名单下载到了"
			left=$(x 'grep -iE "angeworld|jlip\.cc|wan\.family|ssrdog|216\.40\.86|219\.146\.1\.66|142\.171\.133" /etc/litebox/rules/lb_direct.list /etc/litebox/rules/lb_proxy.list | head -n 5' | tr '\n' ' ')
			if [ -z "$left" ]; then ok "全新安装的默认规则里没有作者个人条目（真实名单）"; else bad "默认规则里还有作者个人条目：$left"; fi
		else
			bad "真实名单没下载到。安装时：$(echo "$out" | grep '规则' | tr '\n' ' ')；日志：$(x 'cat /etc/litebox/rules-update.log' | tr '\n' ' ')；直接下载：$(x 'curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 10 https://raw.githubusercontent.com/liandu2024/clash/main/list/Direct.list 2>&1; echo; wget -q -T 10 -O /dev/null https://raw.githubusercontent.com/liandu2024/clash/main/list/Direct.list 2>&1; echo "wget=$?"; command -v curl' | tr '\n' ' ')"
		fi
	fi
	# litebox update：先核对 get.sh 的 SHA256，对不上不运行
	check "update：校验通过才运行安装脚本" x 'LB_RELEASE_URL=http://127.0.0.1:8765/rel litebox update --yes 2>&1 | grep -q "STUB_GETSH_RAN --yes"'
	check "update：安装脚本被改过时拒绝运行" x 'out=$(LB_RELEASE_URL=http://127.0.0.1:8765/relbad litebox update 2>&1); echo "$out" | grep -q "校验不通过" && ! echo "$out" | grep -q STUB_GETSH_RAN'
	# 看门狗间隔可以改，升级后保留（后面覆盖安装时检查）
	check "看门狗间隔可以改" x 'litebox watchdog-interval 10 >/dev/null && grep -q "^\*/10 \* \* \* \* /usr/bin/litebox watchdog # litebox$" /etc/crontabs/root && grep -q "^WATCHDOG_MIN=10$" /etc/litebox/litebox.conf && [ "$(grep -c "litebox watchdog" /etc/crontabs/root)" = 1 ]'
	check "看门狗间隔超出范围时拒绝" x '! litebox watchdog-interval 0 && ! litebox watchdog-interval 61 && grep -q "^WATCHDOG_MIN=10$" /etc/litebox/litebox.conf'
	# 访客网络等能上网的区域：放行到 litebox，否则会被 TUN 路由带进来后挡掉、整个断网
	x 'uci set firewall.tguest=zone; uci set firewall.tguest.name=guest; uci set firewall.tguestfwd=forwarding; uci set firewall.tguestfwd.src=guest; uci set firewall.tguestfwd.dest=wan; uci commit firewall; litebox zones-sync' >/dev/null 2>&1 || true
	check "访客区域自动放行到 litebox" x '[ "$(uci -q get firewall.litebox_fwd_guest.src)" = guest ] && [ "$(uci -q get firewall.litebox_fwd_guest.dest)" = litebox ]'
	x 'uci delete firewall.tguestfwd; uci commit firewall; litebox zones-sync' >/dev/null 2>&1 || true
	check "访客区域不再能上网时撤掉放行" x '! uci -q get firewall.litebox_fwd_guest'
	x 'uci set firewall.tguestfwd=forwarding; uci set firewall.tguestfwd.src=guest; uci set firewall.tguestfwd.dest=wan; uci commit firewall; litebox zones-sync' >/dev/null 2>&1 || true
	check "luci-status 输出合法 JSON" x 'litebox luci-status | jsonfilter -e "@.running" | grep -q true && litebox luci-status | jsonfilter -e "@.sub" | grep -q "^http://127.0.0.1:8765/"'
	# 这个镜像自带 LuCI 21.02：后台页面要装上，菜单和权限文件要是合法 JSON
	check "LuCI 后台页面装上了" x '[ -f /www/luci-static/resources/view/litebox.js ] && jsonfilter -i /usr/share/luci/menu.d/luci-app-litebox.json -e "@[\"admin/services/litebox\"].action.path" | grep -qx litebox && jsonfilter -i /usr/share/rpcd/acl.d/luci-app-litebox.json -e "@[\"luci-app-litebox\"].write.file" >/dev/null'
	check "分组带图标" x 'grep -q "^    icon: '"'"'data:image/svg+xml," /etc/litebox/config.yaml'
	# 离线安装时面板还没下载：这时不能先建 ui/ 目录，否则内核以为面板已存在、不再下载
	check "面板没下载时不提前建面板目录" x '[ -f /etc/litebox/ui/index.html ] || [ ! -e /etc/litebox/ui ]'
	check "概览页放进了面板目录" x '[ -f /etc/litebox/ui/index.html ] || exit 0; [ -f /etc/litebox/ui/litebox/index.html ] && [ -L /etc/litebox/ui/litebox/traffic.txt ]'
	check "面板能打开概览页" x '[ -f /etc/litebox/ui/index.html ] || exit 0; wget -q -O - http://127.0.0.1:9090/ui/litebox/ | grep -q "LiteBox 概览"'
	check "面板目录被换掉后看门狗补回概览页" x '[ -f /etc/litebox/ui/index.html ] || exit 0; rm -rf /etc/litebox/ui/litebox && litebox watchdog && [ -f /etc/litebox/ui/litebox/index.html ]'
	# 下面两项要用 curl 调内核接口，镜像里没有 curl 时跳过
	check "看门狗按天记录流量" x 'command -v curl >/dev/null || exit 0; litebox watchdog; grep -q "^$(date +%F) [0-9][0-9]* [0-9][0-9]*$" /tmp/litebox-traffic.txt && [ -f /etc/litebox/traffic.txt ] && wget -q -O - http://127.0.0.1:9090/ui/litebox/traffic.txt | grep -q "^$(date +%F) "'
	check "litebox route 能跑完" x 'command -v curl >/dev/null || exit 0; litebox route example.com | grep -q 访问结果'

	check "quic off" x 'litebox quic off && litebox quic | grep -q 已放行'
	check "quic on" x 'litebox quic on && litebox quic | grep -q 已屏蔽'
	check "stack gvisor 后仍在运行" x 'litebox stack gvisor && sleep 3 && litebox status | grep -q 运行中'
	check "stack system" x 'litebox stack system && litebox stack | grep -q system'

	# 看门狗：内核彻底起不来 → 恢复 DNS；修好后 → 重新接管
	x 'mv /usr/lib/litebox/mihomo /usr/lib/litebox/mihomo.x; ubus call service delete "{\"name\":\"litebox\"}"; sleep 1; litebox watchdog' || true
	check "内核起不来时看门狗恢复 DNS" x '! uci -q get dhcp.@dnsmasq[0].server | grep -q 1053'
	x 'mv /usr/lib/litebox/mihomo.x /usr/lib/litebox/mihomo; /etc/init.d/litebox start; sleep 2; litebox dns-off; litebox watchdog' || true
	check "内核恢复后看门狗重新接管 DNS" x 'uci -q get dhcp.@dnsmasq[0].server | grep -q 1053'
	x 'litebox stop; litebox watchdog; sleep 1' || true
	check "手动 stop 后看门狗不乱接管" x '! uci -q get dhcp.@dnsmasq[0].server | grep -q 1053'
	x 'litebox start; sleep 2' || true

	local secret
	secret=$(x '. /etc/litebox/litebox.conf; echo $SECRET')
	# 模拟 v0.6 及以前的配置：规则集是 type: http（内核自己下载、不校验）
	x 'sed -i "/^rule-providers:/,/^rules:/ s/^    type: file$/    type: http/" /etc/litebox/config.yaml' || true
	out=$(x 'sh /root/litebox/install.sh < /dev/null 2>&1') || true
	if echo "$out" | grep -q '安装完成'; then ok "覆盖安装（升级）"; else bad "覆盖安装（升级）"; echo "$out" | tail -5; fi
	check "升级保留面板密钥" x '[ "$(. /etc/litebox/litebox.conf; echo $SECRET)" = "'"$secret"'" ]'
	check "升级不重复加定时任务" x '[ "$(grep -c "litebox watchdog" /etc/crontabs/root)" = 1 ] && [ "$(grep -c "litebox rules-update" /etc/crontabs/root)" = 1 ]'
	check "升级保留看门狗间隔" x 'grep -q "^\*/10 \* \* \* \* /usr/bin/litebox watchdog # litebox$" /etc/crontabs/root && grep -q "^WATCHDOG_MIN=10$" /etc/litebox/litebox.conf'
	check "升级时旧配置的规则集改成 type: file，并留备份" x '! sed -n "/^rule-providers:/,/^rules:/p" /etc/litebox/config.yaml | grep -q "type: http" && grep -q "^    type: http$" /etc/litebox/config.yaml.pre-0.7 && litebox check'
	out=$(x 'sh /root/litebox/install.sh --reset-config < /dev/null 2>&1') || true
	check "--reset-config 保留订阅" x '[ "$(litebox sub)" = "http://127.0.0.1:8765/sub.yaml?token=SECRET&a=it'"'"'s" ]'
	check "--reset-config 留下旧配置备份" x '[ -f /etc/litebox/config.yaml.old ]'
	x 'cp /etc/litebox/config.yaml /root/config.keep; sed -i "s|^    url: .*# LITEBOX_SUB\$|    url: '"'"'https://sub.invalid/litebox-placeholder'"'"' # LITEBOX_SUB|" /etc/litebox/config.yaml; /etc/init.d/litebox restart; sleep 2' >/dev/null 2>&1 || true
	check "没填订阅时不启动，DNS 不接管" x '! pidof mihomo && ! uci -q get dhcp.@dnsmasq[0].server | grep -q 1053'
	x 'cp /root/config.keep /etc/litebox/config.yaml; /etc/init.d/litebox start; sleep 2' >/dev/null 2>&1 || true

	x 'litebox uninstall --purge' >/dev/null 2>&1 || true
	check "卸载后服务和文件清除" x '[ ! -e /etc/litebox ] && [ ! -e /usr/bin/litebox ] && ! pidof mihomo'
	check "卸载后 DNS 还原" x '! uci -q get dhcp.@dnsmasq[0].server | grep -q 1053'
	check "卸载后防火墙还原（含访客区域的放行）" x '! uci show firewall | grep -q litebox'
	check "卸载后 LuCI 页面删掉" x '[ ! -e /www/luci-static/resources/view/litebox.js ] && [ ! -e /usr/share/luci/menu.d/luci-app-litebox.json ] && [ ! -e /usr/share/rpcd/acl.d/luci-app-litebox.json ]'
	docker rm -f "$c" >/dev/null
}

# 已经装了别的代理插件（模拟 OpenClash：procd 服务 + 把 dnsmasq 指向 7874 + 订阅存在 uci 里）
run_conflict() {
	local c=lb-conflict out
	CUR_ROUND=conflict
	echo
	echo "== 已装 OpenClash 的路由器"
	docker rm -f "$c" >/dev/null 2>&1 || true
	docker run -d --privileged --name "$c" --network none "$IMAGE" /sbin/init >/dev/null
	sleep 8
	docker cp "$PKG" "$c:/root/litebox"
	docker cp "$WORK/sub" "$c:/root/sub"
	x() { docker exec "$c" sh -c "$1"; }
	x 'uhttpd -p 127.0.0.1:8765 -h /root/sub'
	x 'cat > /etc/init.d/openclash <<"EOF"
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
	procd_open_instance
	procd_set_param command /bin/sleep 100000
	procd_close_instance
	uci set dhcp.@dnsmasq[0].noresolv=1; uci -q delete dhcp.@dnsmasq[0].server; uci add_list dhcp.@dnsmasq[0].server=127.0.0.1#7874; uci commit dhcp
}
stop_service() { :; }
EOF
chmod 755 /etc/init.d/openclash; touch /etc/config/openclash
uci set openclash.sub1=config_subscribe; uci set openclash.sub1.address="http://127.0.0.1:8765/sub.yaml?token=FROM_OPENCLASH"; uci commit openclash
/etc/init.d/openclash enable; /etc/init.d/openclash start; sleep 1'
	check "（准备）假 OpenClash 在运行并接管了 DNS" x '/etc/init.d/openclash running && uci -q get dhcp.@dnsmasq[0].server | grep -q 7874'
	x 'cat > /etc/init.d/shadowsocksr <<"EOF"
#!/bin/sh /etc/rc.common
START=99
running() { return 0; }
start() { :; }
stop() { :; }
EOF
chmod 755 /etc/init.d/shadowsocksr; /etc/init.d/shadowsocksr disable'

	out=$(x 'sh /root/litebox/install.sh < /dev/null 2>&1') || true
	if echo "$out" | grep -q -- '--yes'; then ok "没有终端又没加 --yes 时拒绝安装"; else bad "没有终端又没加 --yes 时拒绝安装"; fi
	check "拒绝时什么都没改" x '/etc/init.d/openclash running && [ ! -e /usr/bin/litebox ]'

	out=$(x 'sh /root/litebox/install.sh --yes < /dev/null 2>&1') || true
	echo "$out" | sed 's/^/    | /'
	if echo "$out" | grep -q '安装完成，已启动'; then ok "加 --yes 安装完成"; else bad "加 --yes 安装完成"; return; fi
	check "沿用了 OpenClash 里的订阅" x '[ "$(litebox sub)" = "http://127.0.0.1:8765/sub.yaml?token=FROM_OPENCLASH" ]'
	check "关着但 running 乱报的插件不当成冲突" x '! grep -qx shadowsocksr /etc/litebox/others-stopped && ! /etc/init.d/shadowsocksr enabled'
	check "OpenClash 已停止并关闭自启" x '! /etc/init.d/openclash running && ! /etc/init.d/openclash enabled'
	check "DNS 从 7874 换成了 LiteBox" x 'uci -q get dhcp.@dnsmasq[0].server | grep -q "127.0.0.1#1053" && ! uci -q get dhcp.@dnsmasq[0].server | grep -q 7874'
	check "LiteBox 在运行" x 'litebox status | grep -q 运行中'
	x 'litebox switch-back' >/dev/null 2>&1 || true
	sleep 1
	check "switch-back 后 OpenClash 恢复运行和自启" x '/etc/init.d/openclash running && /etc/init.d/openclash enabled'
	check "switch-back 后 LiteBox 停止且不自启" x '! pidof mihomo && ! /etc/init.d/litebox enabled'
	# 有些固件里插件脚本的 running 不管有没有进程都说「在运行」：停用后 doctor 不应误报冲突
	x 'cat > /etc/init.d/passwall <<"EOF"
#!/bin/sh /etc/rc.common
START=99
running() { return 0; }
start() { :; }
stop() { :; }
EOF
chmod 755 /etc/init.d/passwall; /etc/init.d/passwall disable; /etc/init.d/openclash stop; /etc/init.d/openclash disable; /etc/init.d/litebox enable; litebox start >/dev/null 2>&1; sleep 6' || true
	check "running 乱报的插件停用后，doctor 不误报冲突" x '! litebox doctor | grep -q "passwall.*冲突"'
	x '/etc/init.d/passwall enable' || true
	check "插件开着开机自启时，doctor 提示冲突" x 'litebox doctor | grep -q "passwall 开着开机自启"'
	docker rm -f "$c" >/dev/null
}

# 带 ipset 的系统：国内 IP 不进内核 + TCP 转发，全套加速
run_ipset() {
	local c=lb-ipset out
	CUR_ROUND=ipset
	echo
	echo "== 带 ipset 的路由器（完整加速层）"
	docker rm -f "$c" >/dev/null 2>&1 || true
	docker run -d --privileged --name "$c" --network none "$IMAGE_IPSET" /sbin/init >/dev/null
	sleep 12
	docker cp "$PKG" "$c:/root/litebox"
	docker cp "$WORK/sub" "$c:/root/sub"
	x() { docker exec "$c" sh -c "$1"; }
	# 容器没有网络下不了面板，放一个占位的面板首页，用来测概览页的安装和补回
	x 'mkdir -p /etc/litebox/rules /etc/litebox/ui && echo zashboard > /etc/litebox/ui/index.html'
	docker cp "$WORK/cn_ip.list" "$c:/etc/litebox/rules/cn_ip.list"
	x 'uhttpd -p 127.0.0.1:8765 -h /root/sub'
	out=$(x 'sh /root/litebox/install.sh --yes --sub "http://127.0.0.1:8765/sub.yaml" < /dev/null 2>&1') || true
	if echo "$out" | grep -q '安装完成，已启动'; then ok "安装完成"; else bad "安装完成"; echo "$out" | tail -8; return; fi
	x 'for i in $(seq 1 30); do [ -f /tmp/litebox-fw.state ] && break; sleep 1; done' || true
	check "国内 IP 段装进 ipset（6000 段以上）" x '[ "$(ipset list litebox_cn | grep -c "^[0-9]")" -gt 6000 ]'
	check "状态：bypass + redir" x 'grep -q "^bypass:" /tmp/litebox-fw.state && grep -q "^redir:7892" /tmp/litebox-fw.state'
	check "策略路由排在内核规则前（8999）" x 'ip rule | grep -q "^8999:.*fwmark 0x20000000/0x20000000 lookup main"'
	check "mangle 给国内 IP 打标记" x 'iptables -w -t mangle -S LITEBOX_MARK | grep -q "match-set litebox_cn dst"'
	check "nat 转发 TCP，国内 IP 跳过" x 'iptables -w -t nat -S LITEBOX_NAT | grep -q "match-set litebox_cn dst -j RETURN" && iptables -w -t nat -S LITEBOX_NAT | grep -q "REDIRECT --to-ports 7892"'
	check "doctor 显示加速生效" x 'litebox doctor | grep -q "国内 IP 直连，不进内核"'
	# 验收：下载到出错网页时，内核里正在用的规则不变；正常更新时只重读这一个规则集，内核不重启。
	# 用只含 lb_grok 的配置跑更新（容器断网，完整配置里的其他规则下载会先失败，连续失败两次就跳过后面的）
	x '. /etc/litebox/litebox.conf
		printf "rule-providers:\n  lb_grok:\n    type: file\n    behavior: classical\n    format: text\n    url: http://127.0.0.1:8765/rules/bad.html\n    path: ./rules/lb_grok.list\nrules:\n  - MATCH,DIRECT\n" > /root/grok-test.yaml
		printf "DOMAIN-SUFFIX,grok.com\nDOMAIN-SUFFIX,x.ai\n" > /etc/litebox/rules/lb_grok.list
		curl -s -X PUT -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/providers/rules/lb_grok
		pidof mihomo > /tmp/pid.before; litebox rules-update --from /root/grok-test.yaml' >/dev/null 2>&1 || true
	check "验收：下载到出错网页后，内核里的规则不变" x '. /etc/litebox/litebox.conf; [ "$(curl -s -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/providers/rules | jsonfilter -e "@.providers.lb_grok.ruleCount")" = 2 ] && grep -qx "DOMAIN-SUFFIX,x.ai" /etc/litebox/rules/lb_grok.list && tail -n 1 /etc/litebox/rules-update.log | grep -q "lb_grok（下载到的是网页"'
	x 'sed -i "s#/rules/bad.html#/rules/good.list#" /root/grok-test.yaml; litebox rules-update --from /root/grok-test.yaml' >/dev/null 2>&1 || true
	check "验收：正常更新后内核用上新规则，没有重启" x '. /etc/litebox/litebox.conf; [ "$(curl -s -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/providers/rules | jsonfilter -e "@.providers.lb_grok.ruleCount")" = 3 ] && [ "$(pidof mihomo)" = "$(cat /tmp/pid.before)" ]'
	check "加速完整时 status 不提示降级" x 'litebox status | grep -q "加速：完整" && ! litebox status | grep -q 降级'
	x 'mv /usr/sbin/ipset /usr/sbin/ipset.off' || true
	check "卸掉 ipset 后 status 醒目提示降级模式" x 'litebox status | grep -q "当前为降级模式" && litebox status | grep -q "opkg install ipset"'
	x 'mv /usr/sbin/ipset.off /usr/sbin/ipset' || true
	check "老版本 LuCI（18.06，没有 menu.d）不装后台页面" x '[ ! -e /www/luci-static/resources/view/litebox.js ] && [ ! -e /usr/share/luci/menu.d/luci-app-litebox.json ]'
	# 面板首页已在（上面放的占位文件），概览页必须到位
	check "概览页放进了面板目录" x '[ -f /etc/litebox/ui/litebox/index.html ] && [ -L /etc/litebox/ui/litebox/traffic.txt ]'
	check "面板能打开概览页和流量记录" x 'litebox watchdog; wget -q -O - http://127.0.0.1:9090/ui/litebox/ | grep -q "LiteBox 概览" && wget -q -O - http://127.0.0.1:9090/ui/litebox/traffic.txt | grep -q "^$(date +%F) "'
	check "面板目录被换掉后看门狗补回概览页" x 'rm -rf /etc/litebox/ui/litebox && litebox watchdog && [ -f /etc/litebox/ui/litebox/index.html ]'
	x '/etc/init.d/firewall restart >/dev/null 2>&1; for i in $(seq 1 30); do iptables -w -t nat -S PREROUTING | grep -q LITEBOX_NAT && break; sleep 1; done' || true
	check "重载防火墙后规则自动加回" x 'iptables -w -t nat -S PREROUTING | grep -q LITEBOX_NAT && iptables -w -t mangle -S PREROUTING | grep -q LITEBOX_MARK'
	x '/usr/lib/litebox/firewall.sh start & /usr/lib/litebox/firewall.sh start & /etc/init.d/firewall reload >/dev/null 2>&1; wait; sleep 3; for i in $(seq 1 30); do [ -d /tmp/litebox-fw.lock ] || break; sleep 1; done' >/dev/null 2>&1 || true
	check "同时启动几次，规则不重复" x '[ "$(iptables -w -t nat -S PREROUTING | grep -c LITEBOX_NAT)" = 1 ] && [ "$(iptables -w -t mangle -S PREROUTING | grep -c LITEBOX_MARK)" = 1 ] && [ "$(ip rule | grep -c "^8999:")" = 1 ] && grep -q "^bypass:" /tmp/litebox-fw.state'
	x 'litebox stop >/dev/null 2>&1; sleep 1' || true
	check "stop 后规则、策略路由、ipset 全部撤掉" x '! iptables -w -t nat -S | grep -q LITEBOX && ! ip rule | grep -q 8999 && ! ipset list -n | grep -q litebox'
	x 'litebox start >/dev/null 2>&1; for i in $(seq 1 30); do [ -f /tmp/litebox-fw.state ] && break; sleep 1; done' || true
	x 'litebox uninstall --purge >/dev/null 2>&1' || true
	check "卸载后什么都不留" x '! iptables -w -t nat -S | grep -q LITEBOX && ! iptables -w -t mangle -S | grep -q LITEBOX && ! ip rule | grep -q 8999 && ! ipset list -n | grep -q litebox && ! uci -q get firewall.litebox_inc'
	docker rm -f "$c" >/dev/null
}

run_round offline "--network none"
run_round online ""
run_conflict
run_ipset

echo
if [ "$FAILS" = 0 ]; then
	echo "全部通过"
else
	echo "$FAILS 项失败"
	exit 1
fi
