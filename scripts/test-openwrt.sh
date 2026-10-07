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
WORK=$(mktemp -d)
FAILS=0
trap 'docker rm -f lb-offline lb-online >/dev/null 2>&1; rm -rf "$WORK"' EXIT

pinned() { sed -n "s/^$1=//p" "$ROOT/install.sh" | head -n 1; }
MIHOMO_VER=$(pinned MIHOMO_VER)
MIHOMO_SHA=$(pinned MIHOMO_SHA_amd64)

# 测试用安装包：仓库里的脚本 + x86_64 内核（相当于 x86 版的离线包）
PKG=$WORK/litebox
mkdir -p "$PKG/files"
cp "$ROOT/install.sh" "$PKG/"
cp "$ROOT/files/config.yaml.tpl" "$ROOT/files/litebox" "$ROOT/files/litebox.init" "$PKG/files/"
curl -fsSL --retry 3 -o "$PKG/mihomo-linux-amd64-$MIHOMO_VER.gz" \
	"https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VER/mihomo-linux-amd64-$MIHOMO_VER.gz"
echo "$MIHOMO_SHA  $PKG/mihomo-linux-amd64-$MIHOMO_VER.gz" | sha256sum -c - >/dev/null

# 假订阅：容器里用 uhttpd 提供，节点连不上也没关系，只测安装和接管逻辑
mkdir -p "$WORK/sub"
printf 'proxies:\n  - {name: test, type: socks5, server: 127.0.0.1, port: 9}\n' > "$WORK/sub/sub.yaml"

docker pull -q "$IMAGE" >/dev/null

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

run_round offline "--network none"
run_round online ""

echo
if [ "$FAILS" = 0 ]; then
	echo "全部通过"
else
	echo "$FAILS 项失败"
	exit 1
fi
