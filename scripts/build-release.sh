#!/bin/sh
# 打包 Release 文件到 dist/（由 .github/workflows/release.yml 调用，也可以在电脑上手动运行）
#
#   sh scripts/build-release.sh
#
# 内核和面板的版本、SHA256 直接取自 install.sh，保证离线包里的文件和安装时校验的一致。

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

pinned() { sed -n "s/^$1=//p" install.sh | head -n 1; }
MIHOMO_VER=$(pinned MIHOMO_VER)
MIHOMO_SHA=$(pinned MIHOMO_SHA_arm64)
UI_VER=$(pinned UI_VER)
UI_ASSET=$(pinned UI_ASSET)
UI_SHA=$(pinned UI_SHA)
[ -n "$MIHOMO_VER" ] && [ -n "$MIHOMO_SHA" ] && [ -n "$UI_VER" ] && [ -n "$UI_ASSET" ] && [ -n "$UI_SHA" ] \
	|| { echo "无法从 install.sh 读取锁定的版本" >&2; exit 1; }

DIST=$ROOT/dist
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rm -rf "$DIST"
mkdir -p "$DIST"

fetch_verified() { # URL 输出文件 SHA256
	curl -fsSL --retry 3 -o "$2" "$1"
	echo "$3  $2" | sha256sum -c - >/dev/null || { echo "校验不通过：$1" >&2; exit 1; }
}

# 只含脚本的包：litebox.tar.gz（get.sh 用）和 litebox.zip
mkdir -p "$WORK/scripts/litebox/files"
cp install.sh README.md "$WORK/scripts/litebox/"
cp files/* "$WORK/scripts/litebox/files/"
chmod 755 "$WORK/scripts/litebox/install.sh" "$WORK/scripts/litebox/files/litebox" "$WORK/scripts/litebox/files/litebox.init" "$WORK/scripts/litebox/files/litebox-firewall.sh"
(cd "$WORK/scripts" && tar --owner=0 --group=0 -czf "$DIST/litebox.tar.gz" litebox && zip -qr "$DIST/litebox.zip" litebox)

# 离线包：脚本 + arm64 内核 + 面板 + 许可证
cp -r "$WORK/scripts" "$WORK/offline"
fetch_verified "https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VER/mihomo-linux-arm64-$MIHOMO_VER.gz" \
	"$WORK/offline/litebox/mihomo-linux-arm64-$MIHOMO_VER.gz" "$MIHOMO_SHA"
fetch_verified "https://github.com/Zephyruso/zashboard/releases/download/$UI_VER/$UI_ASSET" \
	"$WORK/offline/litebox/$UI_ASSET" "$UI_SHA"
cp -r licenses "$WORK/offline/litebox/licenses"
(cd "$WORK/offline" && zip -qr "$DIST/litebox-arm64-offline.zip" litebox)

# GPL-3.0 要求随二进制提供对应源码
curl -fsSL --retry 3 -o "$DIST/mihomo-$MIHOMO_VER-source.tar.gz" \
	"https://github.com/MetaCubeX/mihomo/archive/refs/tags/$MIHOMO_VER.tar.gz"

cd "$DIST"
for f in *; do
	sha256sum "$f" > "$f.sha256"
done
ls -l
