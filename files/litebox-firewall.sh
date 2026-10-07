#!/bin/sh
# LiteBox 防火墙加速层（fw3 / iptables），由 init 脚本和 fw3 的 include 调用。
#
#   1. 国内 IP 不进内核：mangle 表给去往国内 IP 的包打标记，策略路由（优先级在内核的 TUN 规则之前）
#      让它们直接走 WAN，还能用上硬件加速。需要 ipset 和完整版 ip（ip-full）
#   2. TCP 用 iptables REDIRECT 交给内核的 redir-port，比经过 TUN 省 CPU；UDP 仍走 TUN
#
# 条件不满足时（没有 ipset、fw4、旧配置没有 redir-port 等）只做能做的部分，其余流量照常走 TUN，
# 和没有加速层时完全一样。当前状态写在 /tmp/litebox-fw.state，litebox doctor 会显示。
#
# 用法：litebox-firewall.sh start | stop | reload（不带参数 = reload，fw3 重载防火墙时调用）

HOME_DIR=/etc/litebox
CONF=$HOME_DIR/litebox.conf
CONFIG=$HOME_DIR/config.yaml
CN_LIST=$HOME_DIR/rules/cn_ip.list
STATE=/tmp/litebox-fw.state
SET=litebox_cn
MARK=0x20000000
PRIO=8999
FAKE_NET=198.18.0.0/16
ACCEL=1
[ -f "$CONF" ] && . "$CONF"

IPT="iptables -w"

core_running() {
	ubus call service list '{"name":"litebox"}' 2>/dev/null | jsonfilter -e '@.litebox.instances.*.pid' >/dev/null 2>&1
}

lan_dev() {
	local d
	d=$(ubus call network.interface.lan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
	echo "${d:-br-lan}"
}

redir_port() {
	sed -n 's/^redir-port: *\([0-9][0-9]*\).*/\1/p' "$CONFIG" 2>/dev/null | head -n 1
}

port_listening() {
	netstat -ltn 2>/dev/null | awk '{ print $4 }' | grep -q "[:.]$1\$"
}

# 删掉某个表里所有跳到指定链的规则，再清空并删除这条链
drop_chain() { # 表 内置链 自定义链
	$IPT -t "$1" -S "$2" 2>/dev/null | grep -- "-j $3\$" | sed 's/^-A /-D /' | while read -r rule; do
		# shellcheck disable=SC2086
		$IPT -t "$1" $rule 2>/dev/null
	done
	$IPT -t "$1" -F "$3" 2>/dev/null
	$IPT -t "$1" -X "$3" 2>/dev/null
}

stop() {
	drop_chain nat PREROUTING LITEBOX_NAT
	drop_chain mangle PREROUTING LITEBOX_MARK
	while ip rule del fwmark "$MARK/$MARK" lookup main prio "$PRIO" 2>/dev/null; do :; done
	ipset destroy "$SET" 2>/dev/null
	ipset destroy "${SET}_new" 2>/dev/null
	rm -f "$STATE"
}

# 国内 IP 段装进 ipset：先填新集合再原子交换，不会出现半空的时刻
load_cn_set() {
	ipset create "$SET" hash:net family inet hashsize 1024 maxelem 65536 -exist || return 1
	ipset destroy "${SET}_new" 2>/dev/null
	{
		echo "create ${SET}_new hash:net family inet hashsize 1024 maxelem 65536"
		grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$' "$CN_LIST" | sed "s/^/add ${SET}_new /"
	} | ipset restore -exist || { ipset destroy "${SET}_new" 2>/dev/null; return 1; }
	ipset swap "${SET}_new" "$SET" && ipset destroy "${SET}_new"
}

bypass_ready() {
	command -v ipset >/dev/null 2>&1 || { WHY="没有 ipset"; return 1; }
	ip -V 2>/dev/null | grep -q iproute2 || { WHY="没有完整版 ip（ip-full）"; return 1; }
	[ -s "$CN_LIST" ] || { WHY="没有国内 IP 列表（旧配置，执行 litebox update --reset-config 可升级）"; return 1; }
	return 0
}

start() {
	local dev port bypass=0 redir=0 i
	stop
	if [ "$ACCEL" = 0 ]; then echo "off" > "$STATE"; return 0; fi
	if [ -x /sbin/fw4 ] || ! command -v iptables >/dev/null 2>&1; then
		echo "tun:这个系统用的是 nftables（fw4），加速层只支持 fw3" > "$STATE"
		return 0
	fi
	dev=$(lan_dev)

	WHY=""
	if bypass_ready && load_cn_set; then
		$IPT -t mangle -N LITEBOX_MARK
		$IPT -t mangle -A LITEBOX_MARK -m set --match-set "$SET" dst -j MARK --set-xmark "$MARK/$MARK"
		$IPT -t mangle -I PREROUTING -i "$dev" -j LITEBOX_MARK
		ip rule add fwmark "$MARK/$MARK" lookup main prio "$PRIO"
		bypass=1
	elif [ -z "$WHY" ]; then
		WHY="加载国内 IP 列表失败"
	fi

	# 内核刚启动时 redir-port 可能还没开始监听，最多等 15 秒；没开就不转发，免得 TCP 被转到空端口
	port=$(redir_port)
	if [ -n "$port" ]; then
		for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
			port_listening "$port" && break
			sleep 1
		done
		if port_listening "$port"; then
			$IPT -t nat -N LITEBOX_NAT
			for net in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
				$IPT -t nat -A LITEBOX_NAT -d "$net" -j RETURN
			done
			$IPT -t nat -A LITEBOX_NAT -m addrtype --dst-type LOCAL -j RETURN 2>/dev/null
			if [ "$bypass" = 1 ]; then
				$IPT -t nat -A LITEBOX_NAT -m set --match-set "$SET" dst -j RETURN
				$IPT -t nat -A LITEBOX_NAT -p tcp -j REDIRECT --to-ports "$port"
			else
				# 没有国内 IP 列表时，只转发 fake-ip（走代理的域名），其余照旧走 TUN 由内核判断
				$IPT -t nat -A LITEBOX_NAT -p tcp -d "$FAKE_NET" -j REDIRECT --to-ports "$port"
			fi
			$IPT -t nat -I PREROUTING -i "$dev" -p tcp -j LITEBOX_NAT
			redir=1
		fi
	fi

	{
		[ "$bypass" = 1 ] && echo "bypass:$(ipset list "$SET" 2>/dev/null | grep -c '^[0-9]')" || echo "nobypass:${WHY}"
		[ "$redir" = 1 ] && echo "redir:$port" || echo "noredir:${port:-旧配置没有 redir-port}"
	} > "$STATE"
}

case "${1:-reload}" in
	start) start ;;
	stop) stop ;;
	reload)
		# fw3 重载会清掉自定义规则，这里按内核是否在运行重新加上；放后台，不拖慢防火墙重载
		if core_running; then (start >/dev/null 2>&1 &) else stop; fi ;;
	*) echo "用法：$0 start|stop|reload" >&2; exit 1 ;;
esac
