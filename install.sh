#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="port-block.sh"
SCRIPT_URL="${SCRIPT_URL:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

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

    if [ -n "$GITHUB_REPO" ]; then
        curl -fsSL "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${SCRIPT_NAME}" -o "$target"
        return
    fi

    if [ -f "./${SCRIPT_NAME}" ]; then
        cp "./${SCRIPT_NAME}" "$target"
        return
    fi

    echo "未找到 ${SCRIPT_NAME}。"
    echo "从 GitHub 一键安装时请设置 GITHUB_REPO 或 SCRIPT_URL，例如："
    echo "  curl -fsSL https://raw.githubusercontent.com/xia-66/port-block/main/install.sh | sudo GITHUB_REPO=xia-66/port-block bash"
    exit 1
}

main() {
    need_root

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    local script_path="${tmpdir}/${SCRIPT_NAME}"
    download_script "$script_path"
    chmod +x "$script_path"

    bash "$script_path" "${1:-menu}"
}

main "$@"
