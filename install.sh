#!/bin/sh
# LiteBox 安装 / 升级脚本
#
# 在 OpenWrt（含 GL.iNet 官方固件，如 GL-MT3600BE / Beryl 7）上安装：
#   mihomo 内核（透明代理 + 分流）+ zashboard 网页面板 + 视频作者的域名集规则
# 目标是整套常驻内存控制在 200MB 以内（内核软上限 100MB，超过 180MB 由看门狗重启）。
#
# 用法（先把整个仓库目录上传到路由器，例如 /tmp/Q7Y）：
#   sh /tmp/Q7Y/install.sh [--sub 订阅地址] [--port 面板端口] [--mirror 镜像前缀]
#
# 下载的 mihomo 与面板都锁定版本并校验 SHA256（校验值写死在本脚本里），
# 所以经过镜像站下载也不会被替换内容。重复执行即为升级，已有配置和订阅会保留。

set -u

MIHOMO_VER=v1.19.31
MIHOMO_SHA_arm64=9e0f11afbf38426b8bd88fdc594678f8161c57eccb4e1b77acb12b493904f1d4
MIHOMO_SHA_armv7=a61115819d9ebd568788b0f1bddfa6c9c03458071abdbda80f79291cac0276e1
MIHOMO_SHA_amd64=d5e74bbddbdfff49a1aef7775bf5911da59f0d7196ed509a0ac914b3653dd5f1
UI_VER=v3.29.1
UI_ASSET=dist-no-fonts.zip
UI_SHA=21371cd111b6b3d87774f3ea3ddeacdcb0f6aff8690a16d652daa3ea6e3b0145

BIN_DIR=/usr/lib/litebox
HOME_DIR=/etc/litebox
CONF=$HOME_DIR/litebox.conf
CONFIG=$HOME_DIR/config.yaml
MIN_FREE_KB=81920
SUB_PLACEHOLDER=https://sub.invalid/litebox-placeholder
BUILTIN_MIRRORS="https://ghfast.top https://gh-proxy.com"
LB_LIST=https://raw.githubusercontent.com/liandu2024/clash/main/list
META_GEO=https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TMP=""

info() { echo "[litebox] $*"; }
warn() { echo "[litebox] 警告：$*" >&2; }
die() { echo "[litebox] 错误：$*" >&2; [ -n "$TMP" ] && rm -rf "$TMP"; exit 1; }

usage() {
	cat <<EOF
用法：sh install.sh [选项]
  --sub URL       机场订阅地址（Clash/mihomo 订阅或 base64 节点链接）
  --port N        面板端口（默认 9090）
  --mirror URL    GitHub 下载镜像前缀，例如 https://ghfast.top（默认先直连，失败再试内置镜像）
  --reset-config  用新版模板重新生成配置（订阅、端口、密钥保留，旧配置备份为 config.yaml.old）
  -y, --yes       所有提问都按默认回答（用检测到的订阅、停用冲突的代理插件），适合无人值守
  -h, --help      显示本帮助
EOF
}

SUB_URL=""
PANEL_PORT=""
USER_MIRROR=""
RESET_CONFIG=0
ASSUME_YES=0
while [ $# -gt 0 ]; do
	case "$1" in
		--sub|--port|--mirror)
			[ $# -ge 2 ] || die "$1 后面缺少参数"
			case "$1" in
				--sub) SUB_URL=$2 ;;
				--port) PANEL_PORT=$2 ;;
				--mirror) USER_MIRROR=${2%/} ;;
			esac
			shift 2 ;;
		--reset-config) RESET_CONFIG=1; shift ;;
		-y|--yes) ASSUME_YES=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) usage; die "未知参数：$1" ;;
	esac
done

# ---------- 环境检查 ----------

[ "$(id -u)" = 0 ] || die "请以 root 身份运行。"
[ -f /etc/openwrt_release ] && [ -f /etc/rc.common ] || die "只支持 OpenWrt 系统（包括 GL.iNet 官方固件）。"
[ -f "$SCRIPT_DIR/files/config.yaml.tpl" ] || die "找不到 $SCRIPT_DIR/files/，请把整个仓库目录上传后再运行。"

case "$(uname -m)" in
	aarch64|arm64) ARCH=arm64 ;;
	armv7*) ARCH=armv7 ;;
	x86_64) ARCH=amd64 ;;
	*) die "不支持的 CPU 架构：$(uname -m)" ;;
esac
eval "MIHOMO_SHA=\$MIHOMO_SHA_$ARCH"

. /etc/openwrt_release
MEM_MB=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 }' /proc/meminfo)
info "系统：${DISTRIB_DESCRIPTION:-OpenWrt}，架构 $(uname -m)（$ARCH），内存 ${MEM_MB}MB"
[ "$MEM_MB" -ge 200 ] || warn "内存不到 200MB，运行可能不稳定。"

overlay=/overlay
[ -d "$overlay" ] || overlay=/
free_kb=$(df -Pk "$overlay" | awk 'END { print $4 }')
[ "${free_kb:-0}" -ge "$MIN_FREE_KB" ] || die "存储空间不足：$overlay 只剩 $((${free_kb:-0} / 1024))MB，至少需要 $((MIN_FREE_KB / 1024))MB。"

if command -v curl >/dev/null 2>&1; then DL=curl
elif command -v wget >/dev/null 2>&1; then DL=wget
else die "系统没有 curl 或 wget。"
fi
command -v sha256sum >/dev/null 2>&1 || die "系统没有 sha256sum，无法校验下载文件。"

if [ ! -c /dev/net/tun ]; then
	info "缺少 TUN 设备，尝试安装 kmod-tun ..."
	{ opkg update && opkg install kmod-tun; } >/dev/null 2>&1
	[ -c /dev/net/tun ] || die "kmod-tun 安装失败。请在 GL 管理界面「系统 → 插件」里安装 kmod-tun 后重试。"
fi

# ---------- 先把要问的都问完，后面全自动 ----------

TTY=0
# 放在子 shell 里试：: 是特殊内建命令，重定向失败会让整个脚本退出
[ "$ASSUME_YES" = 0 ] && ( : < /dev/tty ) 2>/dev/null && TTY=1
ask_yes() { # 问题；默认是
	local a
	[ "$ASSUME_YES" = 1 ] && return 0
	[ "$TTY" = 1 ] || return 1
	printf '%s [Y/n] ' "$1" > /dev/tty
	read -r a < /dev/tty || a=""
	case "$a" in n|N|no|NO|否) return 1 ;; *) return 0 ;; esac
}
mask_url() { echo "$1" | sed -E 's#^(https?://[^/?]+).*#\1/…#'; }

# 已启用的其他代理插件：同时运行会抢流量和 DNS，装好后要停用（只停用，配置保留）
OTHER_SVCS="openclash nikki mihomo passwall passwall2 shadowsocksr ssr-plus vssr bypass sing-box openbox homeproxy"
OTHERS=""
for svc in $OTHER_SVCS; do
	[ -x "/etc/init.d/$svc" ] || continue
	if "/etc/init.d/$svc" running >/dev/null 2>&1 || "/etc/init.d/$svc" enabled 2>/dev/null; then
		OTHERS="$OTHERS $svc"
	fi
done
OTHERS=${OTHERS# }
if [ -n "$OTHERS" ]; then
	echo
	info "检测到这些代理插件已启用：$OTHERS"
	info "它们和 LiteBox 同时运行会抢流量和 DNS。LiteBox 装好后会停用它们（只是停用，配置都保留，"
	info "想切回时执行 litebox switch-back）。下载会趁它们还在工作时先完成。"
	if ! ask_yes "[litebox] 继续吗？"; then
		[ "$TTY" = 1 ] || die "需要停用 $OTHERS 才能安装。确认的话加 --yes 重新运行。"
		die "已取消，什么都没改。"
	fi
fi

# 新装且没给 --sub 时，先看看其他插件里有没有现成的订阅
if [ -z "$SUB_URL" ] && { [ ! -f "$CONFIG" ] || [ "$RESET_CONFIG" = 1 ]; }; then
	found=$(uci -q show openclash 2>/dev/null | sed -n "s/^openclash\.[^.]*\.address='\(https\{0,1\}:\/\/.*\)'$/\1/p" | head -n 1)
	[ -n "$found" ] || found=$(uci -q show passwall 2>/dev/null | sed -n "s/^passwall\.[^.]*\.url='\(https\{0,1\}:\/\/.*\)'$/\1/p" | head -n 1)
	if [ -n "$found" ] && { [ ! -f "$CONFIG" ] || ! grep -q "LITEBOX_SUB" "$CONFIG" || grep -q "$SUB_PLACEHOLDER" "$CONFIG"; }; then
		echo
		info "检测到已有的机场订阅：$(mask_url "$found")"
		ask_yes "[litebox] 直接用这个订阅吗？" && SUB_URL=$found
	fi
	if [ -z "$SUB_URL" ] && [ ! -f "$CONFIG" ] && [ "$TTY" = 1 ]; then
		printf '[litebox] 请粘贴机场订阅地址后回车（没有可直接回车，稍后用 litebox sub 设置）：' > /dev/tty
		read -r SUB_URL < /dev/tty || SUB_URL=""
	fi
fi
echo

# 内存紧张时（比如 OpenClash 还开着）临时文件放闪存，免得 /tmp 占内存
avail_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
if [ "${avail_kb:-0}" -lt 122880 ]; then
	mkdir -p "$HOME_DIR"
	TMP=$(mktemp -d "$HOME_DIR/.tmp.XXXXXX") || die "无法创建临时目录。"
else
	TMP=$(mktemp -d /tmp/litebox.XXXXXX) || die "无法创建临时目录。"
fi
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 1' INT TERM

# ---------- 下载工具 ----------

fetch() { # URL 输出文件
	case "$DL" in
		curl) curl -fsSL --connect-timeout 10 --speed-limit 1024 --speed-time 60 -o "$2" "$1" ;;
		wget) wget -q -T 60 -O "$2" "$1" ;;
	esac
}

# 依次输出：直连地址、用户指定镜像、内置镜像
sources_of() {
	echo "$1"
	[ -n "$USER_MIRROR" ] && echo "$USER_MIRROR/$1"
	for m in $BUILTIN_MIRRORS; do echo "$m/$1"; done
}

sha_of() { sha256sum "$1" | awk '{ print $1 }'; }

# 下载并校验 SHA256；同目录下若已有同名文件（离线安装）则优先使用
fetch_verified() { # URL 输出文件 SHA256
	local name src
	name=$(basename "$1")
	if [ -f "$SCRIPT_DIR/$name" ] && [ "$(sha_of "$SCRIPT_DIR/$name")" = "$3" ]; then
		cp "$SCRIPT_DIR/$name" "$2" && return 0
	fi
	for src in $(sources_of "$1"); do
		info "  下载 $src"
		if fetch "$src" "$2" 2>/dev/null && [ "$(sha_of "$2")" = "$3" ]; then
			return 0
		fi
		rm -f "$2"
	done
	return 1
}

# 规则文件不锁版本（作者会更新），只检查不是空文件或网页错误页。
# 记住上一次成功的下载源（直连或某个镜像）下次先试；连续两个文件全部失败多半是网络不通，
# 剩下的不再逐个等超时，交给内核启动后经代理下载
RULE_SRC="" RULE_FAILS=0
fetch_rule() { # URL 输出文件
	local src
	[ "$RULE_FAILS" -ge 2 ] && return 1
	for src in ${RULE_SRC:+"$RULE_SRC$1"} $(sources_of "$1"); do
		if fetch "$src" "$2.tmp" 2>/dev/null && [ -s "$2.tmp" ] && [ "$(head -c 1 "$2.tmp")" != "<" ]; then
			mv -f "$2.tmp" "$2"
			RULE_SRC=${src%"$1"} RULE_FAILS=0
			return 0
		fi
		rm -f "$2.tmp"
	done
	RULE_FAILS=$((RULE_FAILS + 1))
	return 1
}

# ---------- mihomo 内核 ----------

info "安装 mihomo $MIHOMO_VER（$ARCH）..."
asset="mihomo-linux-$ARCH-$MIHOMO_VER.gz"
fetch_verified "https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VER/$asset" "$TMP/$asset" "$MIHOMO_SHA" \
	|| die "mihomo 下载失败或校验不通过。可以在电脑上下载 $asset 放到 $SCRIPT_DIR/ 里再运行（离线安装）。"
mkdir -p "$BIN_DIR" "$HOME_DIR/rules" "$HOME_DIR/providers"
gunzip -c "$TMP/$asset" > "$BIN_DIR/mihomo.new" || die "解压 mihomo 失败。"
chmod 755 "$BIN_DIR/mihomo.new"
"$BIN_DIR/mihomo.new" -v >/dev/null 2>&1 || { rm -f "$BIN_DIR/mihomo.new"; die "mihomo 无法在本机运行（架构不匹配？）。"; }
mv -f "$BIN_DIR/mihomo.new" "$BIN_DIR/mihomo"
rm -f "$TMP/$asset"

# ---------- zashboard 面板 ----------

info "安装 zashboard 面板 $UI_VER ..."
if ! command -v unzip >/dev/null 2>&1; then
	{ opkg update && opkg install unzip; } >/dev/null 2>&1
fi
if ! command -v unzip >/dev/null 2>&1; then
	warn "没有 unzip，跳过面板预装；内核首次启动时会自己下载面板。"
elif fetch_verified "https://github.com/Zephyruso/zashboard/releases/download/$UI_VER/$UI_ASSET" "$TMP/ui.zip" "$UI_SHA"; then
	rm -rf "$TMP/ui"
	if unzip -q -o "$TMP/ui.zip" -d "$TMP/ui" && [ -f "$TMP/ui/dist/index.html" ]; then
		rm -rf "$HOME_DIR/ui"
		mv "$TMP/ui/dist" "$HOME_DIR/ui"
	else
		warn "面板解压失败；内核首次启动时会自己下载面板。"
	fi
else
	warn "面板下载失败；内核首次启动时会自己下载面板。"
fi

# ---------- 规则文件 ----------

info "下载分流规则 ..."
skipped=""
for pair in \
	lb_direct.list=$LB_LIST/Direct.list \
	lb_ai.list=$LB_LIST/AI.list \
	lb_claude.list=$LB_LIST/Claude.list \
	lb_chatgpt.list=$LB_LIST/ChatGPT.list \
	lb_gemini.list=$LB_LIST/Gemini.list \
	lb_copilot.list=$LB_LIST/Copilot.list \
	lb_grok.list=$LB_LIST/Grok.list \
	lb_proxy.list=$LB_LIST/Proxy.list \
	cn_site.mrs=$META_GEO/geosite/cn.mrs \
	cn_ip.mrs=$META_GEO/geoip/cn.mrs
do
	file=${pair%%=*}
	url=${pair#*=}
	if [ "$RULE_FAILS" -ge 2 ]; then
		[ -f "$HOME_DIR/rules/$file" ] || skipped="$skipped $file"
		continue
	fi
	fetch_rule "$url" "$HOME_DIR/rules/$file" || warn "  $file 下载失败，内核启动后会经代理重试。"
done
[ -n "$skipped" ] && warn "  连不上规则下载地址，其余规则（$skipped ）由内核启动后经代理下载。"

# ---------- 停用其他代理插件 ----------

if [ -n "$OTHERS" ]; then
	info "停用 $OTHERS ..."
	for svc in $OTHERS; do
		"/etc/init.d/$svc" stop >/dev/null 2>&1
		"/etc/init.d/$svc" disable >/dev/null 2>&1
		grep -qx "$svc" "$HOME_DIR/others-stopped" 2>/dev/null || echo "$svc" >> "$HOME_DIR/others-stopped"
	done
	sleep 2
	# 个别插件停掉后没把 dnsmasq 改回来，DNS 还指向已经不在的端口：改回系统默认
	srv=$(uci -q get dhcp.@dnsmasq[0].server)
	case "$srv" in
		*127.0.0.1#*)
			case "$srv" in *"127.0.0.1#1053"*) ;; *)
				uci -q delete dhcp.@dnsmasq[0].server
				uci -q delete dhcp.@dnsmasq[0].noresolv
				uci commit dhcp
				/etc/init.d/dnsmasq restart >/dev/null 2>&1
				info "  已把 DNS 改回系统默认" ;;
			esac ;;
	esac
fi

# ---------- 设置与配置文件 ----------

gen_secret() {
	od -An -N12 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
}

port_busy() {
	netstat -ltn 2>/dev/null | awk '{ print $4 }' | grep -q "[:.]$1\$"
}

# 升级时沿用 litebox.conf 里的端口和密钥；命令行 --port 优先
ARG_PORT=$PANEL_PORT
PANEL_PORT="" MIXED_PORT="" SECRET="" MEM_SOFT_MB="" MEM_HARD_MB=""
[ -f "$CONF" ] && . "$CONF"
OLD_PANEL_PORT=$PANEL_PORT
PANEL_PORT=${ARG_PORT:-${OLD_PANEL_PORT:-9090}}
case "$PANEL_PORT" in ''|*[!0-9]*) die "面板端口必须是数字：$PANEL_PORT" ;; esac
MIXED_PORT=${MIXED_PORT:-7890}
SECRET=${SECRET:-$(gen_secret)}
[ -n "$SECRET" ] || SECRET=$(date +%s | sha256sum | cut -c1-24)
MEM_SOFT_MB=${MEM_SOFT_MB:-100}
MEM_HARD_MB=${MEM_HARD_MB:-180}

running=0
pidof mihomo >/dev/null 2>&1 && running=1
if [ "$running" = 0 ] || [ "$PANEL_PORT" != "$OLD_PANEL_PORT" ]; then
	port_busy "$PANEL_PORT" && die "面板端口 $PANEL_PORT 已被占用，请用 --port 换一个，例如 --port 9091"
fi

cat > "$CONF" <<EOF
PANEL_PORT=$PANEL_PORT
MIXED_PORT=$MIXED_PORT
SECRET=$SECRET
MEM_SOFT_MB=$MEM_SOFT_MB
MEM_HARD_MB=$MEM_HARD_MB
EOF

sed_escape() { printf '%s' "$1" | sed -e "s/'/''/g" -e 's/[\\|&]/\\&/g'; }

if [ -f "$CONFIG" ] && [ "$RESET_CONFIG" = 1 ]; then
	# 沿用旧配置里的订阅地址（命令行 --sub 优先）
	if [ -z "$SUB_URL" ]; then
		SUB_URL=$(sed -n "s/^    url: '\(.*\)' # LITEBOX_SUB\$/\1/p" "$CONFIG" | sed "s/''/'/g")
		[ "$SUB_URL" = "$SUB_PLACEHOLDER" ] && SUB_URL=""
	fi
	cp "$CONFIG" "$CONFIG.old"
	rm -f "$CONFIG"
	info "按新模板重新生成配置，旧配置备份为 $CONFIG.old"
fi
if [ -f "$CONFIG" ]; then
	info "保留已有配置 $CONFIG"
	sed -i "s|^external-controller: .*|external-controller: 0.0.0.0:$PANEL_PORT|" "$CONFIG"
else
	tr -d '\r' < "$SCRIPT_DIR/files/config.yaml.tpl" | sed \
		-e "s|__MIXED_PORT__|$MIXED_PORT|" \
		-e "s|__PANEL_PORT__|$PANEL_PORT|" \
		-e "s|__SECRET__|$SECRET|" \
		-e "s|__SUB_URL__|$(sed_escape "${SUB_URL:-$SUB_PLACEHOLDER}")|" \
		> "$CONFIG"
fi
if [ -n "$SUB_URL" ]; then
	sed -i "s|^\(    url: \).*# LITEBOX_SUB\$|\1'$(sed_escape "$SUB_URL")' # LITEBOX_SUB|" "$CONFIG"
	rm -f "$HOME_DIR/providers/sub.yaml"
fi

info "检查配置 ..."
"$BIN_DIR/mihomo" -t -d "$HOME_DIR" -f "$CONFIG" > "$TMP/check.log" 2>&1 \
	|| { cat "$TMP/check.log" >&2; die "配置检查未通过，见上面的输出。"; }

# ---------- 服务、命令、防火墙、看门狗 ----------

info "安装服务和 litebox 命令 ..."
tr -d '\r' < "$SCRIPT_DIR/files/litebox" > /usr/bin/litebox
tr -d '\r' < "$SCRIPT_DIR/files/litebox.init" > /etc/init.d/litebox
chmod 755 /usr/bin/litebox /etc/init.d/litebox

# 局域网流量要能转发进 tun 网卡；fw3 / fw4 都认这套 uci 配置
uci -q delete firewall.litebox_zone
uci set firewall.litebox_zone=zone
uci set firewall.litebox_zone.name=litebox
uci add_list firewall.litebox_zone.device=litebox0
uci set firewall.litebox_zone.input=ACCEPT
uci set firewall.litebox_zone.output=ACCEPT
uci set firewall.litebox_zone.forward=REJECT
uci set firewall.litebox_zone.mtu_fix=1
uci -q delete firewall.litebox_fwd
uci set firewall.litebox_fwd=forwarding
uci set firewall.litebox_fwd.src=lan
uci set firewall.litebox_fwd.dest=litebox
uci commit firewall
/etc/init.d/firewall reload >/dev/null 2>&1

touch /etc/crontabs/root
sed -i '/# litebox$/d' /etc/crontabs/root
echo '*/5 * * * * /usr/bin/litebox watchdog # litebox' >> /etc/crontabs/root
/etc/init.d/cron restart >/dev/null 2>&1

/etc/init.d/litebox enable

LAN_IP=$(uci -q get network.lan.ipaddr)
LAN_IP=${LAN_IP%%/*}
echo
if grep -q "$SUB_PLACEHOLDER" "$CONFIG"; then
	info "安装完成，但还没有设置订阅，所以暂不启动（网络不受影响）。"
	info "设置订阅后会自动启动：litebox sub '你的订阅地址'"
else
	# 首次安装时服务还没在运行，restart 里的 stop 会打印 "Command failed: Not found"，所以分开写
	/etc/init.d/litebox stop >/dev/null 2>&1
	/etc/init.d/litebox start
	ok=0
	for i in 1 2 3 4 5 6 7 8 9 10; do
		sleep 1
		[ -n "$(ubus call service list '{"name":"litebox"}' 2>/dev/null | jsonfilter -e '@.litebox.instances.*.pid' 2>/dev/null)" ] && ok=1 && break
	done
	if [ "$ok" = 0 ]; then
		warn "LiteBox 没能启动。"
		if [ -s "$HOME_DIR/others-stopped" ]; then
			/usr/bin/litebox switch-back
			die "已自动切回原来的代理插件，网络不受影响。把 litebox log 的输出发出来求助。"
		fi
		/usr/bin/litebox direct >/dev/null 2>&1
		die "已恢复直连，网络不受影响。把 litebox log 的输出发出来求助。"
	fi
	info "安装完成，已启动。"
fi
LAN_IP=${LAN_IP:-192.168.8.1}
cat <<EOF

  一键登录：http://$LAN_IP:$PANEL_PORT/ui/#/setup?hostname=$LAN_IP&port=$PANEL_PORT&secret=$SECRET
  （复制到浏览器打开即可。手动登录时：主机 $LAN_IP，端口 $PANEL_PORT，密码 $SECRET）

  常用命令：litebox status | litebox doctor | litebox mem | litebox sub <地址> | litebox panel | litebox direct
EOF
