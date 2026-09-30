#!/bin/sh
# LiteBox 一键安装：下载最新 Release 的脚本包，校验后运行 install.sh（参数原样传给 install.sh）
#
#   curl -fsSL https://raw.githubusercontent.com/lyr05142002-dot/Q7Y/main/get.sh | sh -s -- --sub '订阅地址'
#
# 路由器访问 GitHub 不畅时，经镜像获取本脚本，并让后续下载也走镜像：
#   curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/lyr05142002-dot/Q7Y/main/get.sh | sh -s -- --mirror https://ghfast.top --sub '订阅地址'

set -u

REPO=lyr05142002-dot/Q7Y
ASSET=litebox.tar.gz
BUILTIN_MIRRORS="https://ghfast.top https://gh-proxy.com"

info() { echo "[litebox] $*"; }
die() { echo "[litebox] 错误：$*" >&2; exit 1; }

USER_MIRROR=""
prev=""
for a in "$@"; do
	[ "$prev" = "--mirror" ] && USER_MIRROR=${a%/}
	prev=$a
done

[ "$(id -u)" = 0 ] || die "请以 root 身份运行。"
command -v sha256sum >/dev/null 2>&1 || die "系统没有 sha256sum。"
command -v tar >/dev/null 2>&1 || die "系统没有 tar。"

if command -v curl >/dev/null 2>&1; then
	fetch() { curl -fsSL --connect-timeout 10 --max-time 120 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
	fetch() { wget -q -T 60 -O "$2" "$1"; }
else
	die "系统没有 curl 或 wget。"
fi

TMP=$(mktemp -d /tmp/litebox-get.XXXXXX) || die "无法创建临时目录。"
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 1' INT TERM

url="https://github.com/$REPO/releases/latest/download/$ASSET"
sources() {
	echo "$url"
	[ -n "$USER_MIRROR" ] && echo "$USER_MIRROR/$url"
	for m in $BUILTIN_MIRRORS; do echo "$m/$url"; done
}

# 校验值优先直接从 GitHub 取：这样镜像站就没法同时替换安装包和校验值
want=""
if fetch "$url.sha256" "$TMP/sha" 2>/dev/null; then
	want=$(awk 'NR == 1 { print $1 }' "$TMP/sha")
fi

ok=0
for src in $(sources); do
	info "下载 $src"
	fetch "$src" "$TMP/$ASSET" 2>/dev/null || continue
	if [ -z "$want" ]; then
		fetch "$src.sha256" "$TMP/sha" 2>/dev/null || continue
		want=$(awk 'NR == 1 { print $1 }' "$TMP/sha")
	fi
	if [ "$(sha256sum "$TMP/$ASSET" | awk '{ print $1 }')" = "$want" ]; then
		ok=1
		break
	fi
	info "  校验不通过，换下一个地址"
done
[ "$ok" = 1 ] || die "安装包下载失败或校验不通过。可以改用 Release 页面的离线包手动安装。"

tar -xzf "$TMP/$ASSET" -C "$TMP" || die "解压失败。"
[ -f "$TMP/litebox/install.sh" ] || die "安装包内容不完整。"
sh "$TMP/litebox/install.sh" "$@"
