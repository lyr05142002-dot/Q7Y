#!/bin/sh
# 检查 README 里写的 get.sh 校验值和仓库里的 get.sh 一致（改了 get.sh 忘了改 README，用户照着校验就会失败）。
# GitHub Actions 里和 shellcheck 一起跑；本机也可以手动运行：sh scripts/check-docs.sh

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
want=$(sha256sum "$ROOT/get.sh" | awk '{ print $1 }')
found=$(grep -o '[0-9a-f]\{64\}  get\.sh' "$ROOT/README.md" | awk '{ print $1 }' | sort -u)
[ -n "$found" ] || { echo "README.md 里没有找到 get.sh 的校验命令" >&2; exit 1; }
for h in $found; do
	if [ "$h" != "$want" ]; then
		echo "README.md 里 get.sh 的校验值 $h 和实际的 $want 不一致，请更新 README" >&2
		exit 1
	fi
done
echo "README 里的 get.sh 校验值正确：$want"
