#!/bin/sh
# 检查网页部分：概览页和 LuCI 页面的 JavaScript 能解析，LuCI 菜单、权限文件是合法 JSON。
# GitHub Actions 里和 shellcheck 一起跑；本机有 node 和 python3 也可以手动运行：sh scripts/check-web.sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 概览页的脚本写在 <script> 和 </script> 两行之间
sed -n '/^<script>$/,/^<\/script>$/p' "$ROOT/files/panel.html" | sed '1d;$d' > "$TMP/panel.js"
[ -s "$TMP/panel.js" ] || { echo "files/panel.html 里没找到脚本" >&2; exit 1; }
node --check "$TMP/panel.js"
node --check "$ROOT/files/luci-litebox.js"
for f in luci-litebox-menu.json luci-litebox-acl.json; do
	python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$ROOT/files/$f"
done
echo "网页检查通过"
