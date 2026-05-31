#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="port-block.sh"
SCRIPT_URL="${SCRIPT_URL:-}"
GITHUB_REPO="${GITHUB_REPO:-xia-66/port-block}"
GITHUB_BRANCH="${GITHUB_BRANCH:-master}"
TMPDIR_PATH=""

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行，例如：sudo bash install.sh"
        exit 1
    fi
}

download_script() {
    local target="$1"

    if [ -n "$SCRIPT_URL" ]; then
        curl -fsSL "$SCRIPT_URL" -o "$target"
        return
    fi

    curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${SCRIPT_NAME}" -o "$target"
}

cleanup() {
    if [ -n "$TMPDIR_PATH" ] && [ -d "$TMPDIR_PATH" ]; then
        rm -rf "$TMPDIR_PATH"
    fi
}

main() {
    need_root

    TMPDIR_PATH="$(mktemp -d)"
    trap cleanup EXIT

    local script_path="${TMPDIR_PATH}/${SCRIPT_NAME}"
    download_script "$script_path"
    chmod +x "$script_path"

    if [ -r /dev/tty ]; then
        bash "$script_path" "${1:-menu}" </dev/tty
    else
        bash "$script_path" "${1:-menu}"
    fi
}

main "$@"
