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
bad() { echo "  ✗ $*"; FAILS=$((FAILS + 1)); }
check() { # 说明 命令…
	local what=$1
	shift
	if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi
}

run_round() { # 名字 docker网络参数
	local name=$1 net=$2 c out
	c=lb-$name
	echo
	echo "== $name"
	docker rm -f "$c" >/dev/null 2>&1 || true
	# shellcheck disable=SC2086
	docker run -d --privileged --name "$c" $net "$IMAGE" /sbin/init >/dev/null
	sleep 8
	docker cp "$PKG" "$c:/root/litebox"
	docker cp "$WORK/sub" "$c:/root/sub"
	x() { docker exec "$c" sh -c "$1"; }
	x 'uhttpd -p 127.0.0.1:8765 -h /root/sub'
	x 'mkdir -p /etc/crontabs; /etc/init.d/cron enable; /etc/init.d/cron start' >/dev/null 2>&1 || true

	out=$(x 'sh /root/litebox/install.sh --sub "http://127.0.0.1:8765/sub.yaml?token=SECRET&a=it'"'"'s" < /dev/null 2>&1') || true
	echo "$out" | sed 's/^/    | /'
	if echo "$out" | grep -qE 'parameter not set|not found|syntax error|错误：'; then bad "安装输出里有脚本错误"; fi
	if echo "$out" | grep -q '安装完成'; then ok "安装完成"; else bad "安装没有完成"; return; fi
	sleep 3

	check "服务在运行" x 'litebox status | grep -q 运行中'
	check "配置检查通过" x 'litebox check'
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
	out=$(x 'sh /root/litebox/install.sh < /dev/null 2>&1') || true
	if echo "$out" | grep -q '安装完成'; then ok "覆盖安装（升级）"; else bad "覆盖安装（升级）"; echo "$out" | tail -5; fi
	check "升级保留面板密钥" x '[ "$(. /etc/litebox/litebox.conf; echo $SECRET)" = "'"$secret"'" ]'
	check "升级不重复加定时任务" x '[ "$(grep -c "litebox watchdog" /etc/crontabs/root)" = 1 ]'
	out=$(x 'sh /root/litebox/install.sh --reset-config < /dev/null 2>&1') || true
	check "--reset-config 保留订阅" x '[ "$(litebox sub)" = "http://127.0.0.1:8765/sub.yaml?token=SECRET&a=it'"'"'s" ]'
	check "--reset-config 留下旧配置备份" x '[ -f /etc/litebox/config.yaml.old ]'

	x 'litebox uninstall --purge' >/dev/null 2>&1 || true
	check "卸载后服务和文件清除" x '[ ! -e /etc/litebox ] && [ ! -e /usr/bin/litebox ] && ! pidof mihomo'
	check "卸载后 DNS 还原" x '! uci -q get dhcp.@dnsmasq[0].server | grep -q 1053'
	check "卸载后防火墙还原" x '! uci show firewall | grep -q litebox'
	docker rm -f "$c" >/dev/null
}

# 已经装了别的代理插件（模拟 OpenClash：procd 服务 + 把 dnsmasq 指向 7874 + 订阅存在 uci 里）
run_conflict() {
	local c=lb-conflict out
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

	out=$(x 'sh /root/litebox/install.sh < /dev/null 2>&1') || true
	if echo "$out" | grep -q -- '--yes'; then ok "没有终端又没加 --yes 时拒绝安装"; else bad "没有终端又没加 --yes 时拒绝安装"; fi
	check "拒绝时什么都没改" x '/etc/init.d/openclash running && [ ! -e /usr/bin/litebox ]'

	out=$(x 'sh /root/litebox/install.sh --yes < /dev/null 2>&1') || true
	echo "$out" | sed 's/^/    | /'
	if echo "$out" | grep -q '安装完成，已启动'; then ok "加 --yes 安装完成"; else bad "加 --yes 安装完成"; return; fi
	check "沿用了 OpenClash 里的订阅" x '[ "$(litebox sub)" = "http://127.0.0.1:8765/sub.yaml?token=FROM_OPENCLASH" ]'
	check "OpenClash 已停止并关闭自启" x '! /etc/init.d/openclash running && ! /etc/init.d/openclash enabled'
	check "DNS 从 7874 换成了 LiteBox" x 'uci -q get dhcp.@dnsmasq[0].server | grep -q "127.0.0.1#1053" && ! uci -q get dhcp.@dnsmasq[0].server | grep -q 7874'
	check "LiteBox 在运行" x 'litebox status | grep -q 运行中'
	x 'litebox switch-back' >/dev/null 2>&1 || true
	sleep 1
	check "switch-back 后 OpenClash 恢复运行和自启" x '/etc/init.d/openclash running && /etc/init.d/openclash enabled'
	check "switch-back 后 LiteBox 停止且不自启" x '! pidof mihomo && ! /etc/init.d/litebox enabled'
	docker rm -f "$c" >/dev/null
}

# 带 ipset 的系统：国内 IP 不进内核 + TCP 转发，全套加速
run_ipset() {
	local c=lb-ipset out
	echo
	echo "== 带 ipset 的路由器（完整加速层）"
	docker rm -f "$c" >/dev/null 2>&1 || true
	docker run -d --privileged --name "$c" --network none "$IMAGE_IPSET" /sbin/init >/dev/null
	sleep 12
	docker cp "$PKG" "$c:/root/litebox"
	docker cp "$WORK/sub" "$c:/root/sub"
	x() { docker exec "$c" sh -c "$1"; }
	x 'mkdir -p /etc/litebox/rules'
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
	x '/etc/init.d/firewall restart >/dev/null 2>&1; for i in $(seq 1 30); do iptables -w -t nat -S PREROUTING | grep -q LITEBOX_NAT && break; sleep 1; done' || true
	check "重载防火墙后规则自动加回" x 'iptables -w -t nat -S PREROUTING | grep -q LITEBOX_NAT && iptables -w -t mangle -S PREROUTING | grep -q LITEBOX_MARK'
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
