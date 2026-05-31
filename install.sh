#!/usr/bin/env bash
set -euo pipefail

SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/xia-66/port-block/master/port-block.sh}"

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行，例如：sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/xia-66/port-block/master/port-block.sh)\""
    exit 1
fi

tmp_script="$(mktemp)"
cleanup() {
    rm -f "$tmp_script"
}
trap cleanup EXIT

curl -fsSL "$SCRIPT_URL" -o "$tmp_script"
chmod +x "$tmp_script"
bash "$tmp_script" "${1:-menu}"
