#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PORT="55555"
DEFAULT_COUNTRY="cn"
DEFAULT_PROTO="both"

PORT="${PORT:-$DEFAULT_PORT}"
COUNTRY="${COUNTRY:-$DEFAULT_COUNTRY}"
PROTO="${PROTO:-$DEFAULT_PROTO}"

RULE_DIR="/etc/nftables.d"
RULE_TMPDIR=""

CN4_URL_BASE="https://www.ipdeny.com/ipblocks/data/countries"
CN6_URL_BASE="https://www.ipdeny.com/ipv6/ipaddresses/blocks"

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行，例如：sudo bash $0"
        exit 1
    fi
}

normalize_config() {
    COUNTRY="$(printf '%s' "$COUNTRY" | tr '[:upper:]' '[:lower:]')"
    PROTO="$(printf '%s' "$PROTO" | tr '[:upper:]' '[:lower:]')"

    if ! printf '%s' "$COUNTRY" | grep -Eq '^[a-z]{2}$'; then
        echo "国家/地区代码错误：$COUNTRY。请输入两位代码，例如 cn、us、jp。"
        exit 1
    fi

    if ! printf '%s' "$PORT" | grep -Eq '^[0-9]+$' || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "端口错误：$PORT。端口范围必须是 1-65535。"
        exit 1
    fi

    case "$PROTO" in
        tcp|udp|both) ;;
        *)
            echo "协议错误：$PROTO。只能是 tcp、udp 或 both。"
            exit 1
            ;;
    esac
}

rule_file() {
    echo "${RULE_DIR}/block-${COUNTRY}-${PORT}.nft"
}

update_script() {
    echo "/usr/local/sbin/update-block-${COUNTRY}-${PORT}.sh"
}

service_file() {
    echo "/etc/systemd/system/update-block-${COUNTRY}-${PORT}.service"
}

timer_file() {
    echo "/etc/systemd/system/update-block-${COUNTRY}-${PORT}.timer"
}

table_name() {
    echo "block_${COUNTRY}_${PORT}"
}

install_packages() {
    if ! command -v apt >/dev/null 2>&1; then
        echo "当前脚本只自动适配 Debian/Ubuntu 的 apt。请先安装 nftables、curl、ca-certificates 后重试。"
        exit 1
    fi

    apt update
    apt install -y nftables curl ca-certificates
    systemctl enable --now nftables
}

ensure_nftables_include() {
    mkdir -p "$RULE_DIR"

    if [ ! -f /etc/nftables.conf ]; then
        cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

include "/etc/nftables.d/*.nft"
EOF
        chmod 755 /etc/nftables.conf
        return
    fi

    if ! grep -Fq 'include "/etc/nftables.d/*.nft"' /etc/nftables.conf; then
        echo 'include "/etc/nftables.d/*.nft"' >> /etc/nftables.conf
    fi
}

write_rule_file() {
    local tmp_rule="$1"

    cat > "$tmp_rule" <<EOF
table inet $(table_name) {
    set cn4 {
        type ipv4_addr
        flags interval
        auto-merge
        elements = {
EOF

    awk 'NF {print "            " $0 ","}' "$2" >> "$tmp_rule"

    cat >> "$tmp_rule" <<EOF
        }
    }

    set cn6 {
        type ipv6_addr
        flags interval
        auto-merge
        elements = {
EOF

    if [ -s "$3" ]; then
        awk 'NF {print "            " $0 ","}' "$3" >> "$tmp_rule"
    fi

    cat >> "$tmp_rule" <<EOF
        }
    }

    chain input {
        type filter hook input priority -10; policy accept;

EOF

    case "$PROTO" in
        tcp)
            cat >> "$tmp_rule" <<EOF
        ip saddr @cn4 tcp dport ${PORT} drop
        ip6 saddr @cn6 tcp dport ${PORT} drop
EOF
            ;;
        udp)
            cat >> "$tmp_rule" <<EOF
        ip saddr @cn4 udp dport ${PORT} drop
        ip6 saddr @cn6 udp dport ${PORT} drop
EOF
            ;;
        both)
            cat >> "$tmp_rule" <<EOF
        ip saddr @cn4 tcp dport ${PORT} drop
        ip saddr @cn4 udp dport ${PORT} drop
        ip6 saddr @cn6 tcp dport ${PORT} drop
        ip6 saddr @cn6 udp dport ${PORT} drop
EOF
            ;;
    esac

    cat >> "$tmp_rule" <<EOF

    }
}
EOF
}

generate_rules() {
    normalize_config

    RULE_TMPDIR="$(mktemp -d)"
    trap cleanup_rule_tmpdir EXIT

    local cn4="${RULE_TMPDIR}/ipv4.zone"
    local cn6="${RULE_TMPDIR}/ipv6.zone"
    local tmp_rule="${RULE_TMPDIR}/block.nft"

    echo "正在下载 IPv4 ${COUNTRY} IP 段..."
    curl -fsSL "${CN4_URL_BASE}/${COUNTRY}.zone" -o "$cn4"

    echo "正在下载 IPv6 ${COUNTRY} IP 段..."
    curl -fsSL "${CN6_URL_BASE}/${COUNTRY}.zone" -o "$cn6" || true

    write_rule_file "$tmp_rule" "$cn4" "$cn6"

    mkdir -p "$RULE_DIR"
    cp "$tmp_rule" "$(rule_file)"

    echo "正在检查 nftables 语法..."
    nft -c -f /etc/nftables.conf

    echo "正在加载 nftables 规则..."
    nft -f /etc/nftables.conf

    cleanup_rule_tmpdir
    trap - EXIT

    echo "规则已更新：$(rule_file)"
}

cleanup_rule_tmpdir() {
    if [ -n "$RULE_TMPDIR" ] && [ -d "$RULE_TMPDIR" ]; then
        rm -rf "$RULE_TMPDIR"
    fi
    RULE_TMPDIR=""
}

install_update_script() {
    normalize_config

    local target
    target="$(update_script)"

    cat > "$target" <<EOF
#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT}"
COUNTRY="${COUNTRY}"
PROTO="${PROTO}"
RULE_DIR="${RULE_DIR}"
CN4_URL_BASE="${CN4_URL_BASE}"
CN6_URL_BASE="${CN6_URL_BASE}"

rule_file() {
    echo "\${RULE_DIR}/block-\${COUNTRY}-\${PORT}.nft"
}

table_name() {
    echo "block_\${COUNTRY}_\${PORT}"
}

write_rule_file() {
    local tmp_rule="\$1"

    cat > "\$tmp_rule" <<EOR
table inet \$(table_name) {
    set cn4 {
        type ipv4_addr
        flags interval
        auto-merge
        elements = {
EOR

    awk 'NF {print "            " \$0 ","}' "\$2" >> "\$tmp_rule"

    cat >> "\$tmp_rule" <<EOR
        }
    }

    set cn6 {
        type ipv6_addr
        flags interval
        auto-merge
        elements = {
EOR

    if [ -s "\$3" ]; then
        awk 'NF {print "            " \$0 ","}' "\$3" >> "\$tmp_rule"
    fi

    cat >> "\$tmp_rule" <<EOR
        }
    }

    chain input {
        type filter hook input priority -10; policy accept;

EOR

    case "\$PROTO" in
        tcp)
            cat >> "\$tmp_rule" <<EOR
        ip saddr @cn4 tcp dport \${PORT} drop
        ip6 saddr @cn6 tcp dport \${PORT} drop
EOR
            ;;
        udp)
            cat >> "\$tmp_rule" <<EOR
        ip saddr @cn4 udp dport \${PORT} drop
        ip6 saddr @cn6 udp dport \${PORT} drop
EOR
            ;;
        both)
            cat >> "\$tmp_rule" <<EOR
        ip saddr @cn4 tcp dport \${PORT} drop
        ip saddr @cn4 udp dport \${PORT} drop
        ip6 saddr @cn6 tcp dport \${PORT} drop
        ip6 saddr @cn6 udp dport \${PORT} drop
EOR
            ;;
    esac

    cat >> "\$tmp_rule" <<EOR

    }
}
EOR
}

tmpdir="\$(mktemp -d)"
trap 'rm -rf "\$tmpdir"' EXIT

cn4="\${tmpdir}/ipv4.zone"
cn6="\${tmpdir}/ipv6.zone"
tmp_rule="\${tmpdir}/block.nft"

curl -fsSL "\${CN4_URL_BASE}/\${COUNTRY}.zone" -o "\$cn4"
curl -fsSL "\${CN6_URL_BASE}/\${COUNTRY}.zone" -o "\$cn6" || true

write_rule_file "\$tmp_rule" "\$cn4" "\$cn6"

mkdir -p "\$RULE_DIR"
cp "\$tmp_rule" "\$(rule_file)"

nft -c -f /etc/nftables.conf
nft -f /etc/nftables.conf

echo "已更新 IP 屏蔽规则：\$(rule_file)"
EOF

    chmod +x "$target"
}

install_systemd_timer() {
    normalize_config

    cat > "$(service_file)" <<EOF
[Unit]
Description=Update nftables ${COUNTRY} IP block rules for port ${PORT}

[Service]
Type=oneshot
ExecStart=$(update_script)
EOF

    cat > "$(timer_file)" <<EOF
[Unit]
Description=Weekly auto update nftables ${COUNTRY} IP block rules for port ${PORT}

[Timer]
OnBootSec=5min
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now "update-block-${COUNTRY}-${PORT}.timer"
}

install_all() {
    need_root
    normalize_config
    install_packages
    ensure_nftables_include
    install_update_script
    generate_rules
    install_systemd_timer

    echo
    echo "安装完成。"
    echo "国家/地区：${COUNTRY}"
    echo "端口：${PORT}"
    echo "协议：${PROTO}"
    echo "规则文件：$(rule_file)"
    echo "更新脚本：$(update_script)"
    echo "IP 库自动更新：已启用，每周一次"
    echo
    echo "查看规则：nft list table inet $(table_name)"
    echo "查看定时器：systemctl status update-block-${COUNTRY}-${PORT}.timer"
}

uninstall_all() {
    need_root
    normalize_config

    systemctl disable --now "update-block-${COUNTRY}-${PORT}.timer" 2>/dev/null || true
    rm -f "$(timer_file)" "$(service_file)"
    systemctl daemon-reload

    rm -f "$(update_script)" "$(rule_file)"

    if nft list table inet "$(table_name)" >/dev/null 2>&1; then
        nft delete table inet "$(table_name)" || true
    fi

    nft -f /etc/nftables.conf || true

    echo "已卸载 ${COUNTRY} IP 屏蔽规则：端口 ${PORT}，协议 ${PROTO}。"
}

show_status() {
    need_root
    normalize_config

    echo "国家/地区：${COUNTRY}"
    echo "端口：${PORT}"
    echo "协议：${PROTO}"
    echo "规则文件：$(rule_file)"
    echo

    if [ -f "$(rule_file)" ]; then
        echo "规则文件存在。"
    else
        echo "规则文件不存在。"
    fi

    echo

    if nft list table inet "$(table_name)" >/dev/null 2>&1; then
        echo "nftables 表存在：$(table_name)"
        nft list table inet "$(table_name)"
    else
        echo "nftables 表不存在：$(table_name)"
    fi

    echo
    systemctl status "update-block-${COUNTRY}-${PORT}.timer" --no-pager || true
}

ask_value() {
    local prompt="$1"
    local default_value="$2"
    local value

    read -r -p "${prompt} [${default_value}]: " value
    echo "${value:-$default_value}"
}

ask_proto() {
    local value

    echo "请选择协议：" >&2
    echo "  1) tcp + udp" >&2
    echo "  2) tcp" >&2
    echo "  3) udp" >&2
    read -r -p "输入序号 [1]: " value >&2

    case "${value:-1}" in
        1) echo "both" ;;
        2) echo "tcp" ;;
        3) echo "udp" ;;
        *)
            echo "选择无效。" >&2
            return 1
            ;;
    esac
}

interactive_install() {
    PORT="$(ask_value "请输入要屏蔽的本机端口" "$PORT")"
    COUNTRY="$(ask_value "请输入国家/地区代码" "$COUNTRY")"
    PROTO="$(ask_proto)"
    install_all
}

change_port() {
    need_root

    local old_port new_port old_country old_proto
    old_port="$(ask_value "请输入当前已安装端口" "$PORT")"
    new_port="$(ask_value "请输入新端口" "$old_port")"
    old_country="$(ask_value "请输入国家/地区代码" "$COUNTRY")"
    old_proto="$(ask_proto)"

    PORT="$old_port"
    COUNTRY="$old_country"
    PROTO="$old_proto"
    uninstall_all

    PORT="$new_port"
    COUNTRY="$old_country"
    PROTO="$old_proto"
    install_all
}

interactive_uninstall() {
    PORT="$(ask_value "请输入要卸载的端口" "$PORT")"
    COUNTRY="$(ask_value "请输入国家/地区代码" "$COUNTRY")"
    PROTO="$(ask_proto)"
    uninstall_all
}

show_menu() {
    while true; do
        echo
        echo "nftables IP 屏蔽管理"
        echo "  1) 安装/重新安装（启用 IP 库自动更新）"
        echo "  2) 修改端口"
        echo "  3) 卸载"
        echo "  0) 退出"
        read -r -p "请选择操作 [1]: " choice

        case "${choice:-1}" in
            1) interactive_install ;;
            2) change_port ;;
            3) interactive_uninstall ;;
            0) exit 0 ;;
            *) echo "选择无效，请重新输入。" ;;
        esac
    done
}

usage() {
    cat <<EOF
用法：
  sudo bash $0 menu          打开交互菜单
  sudo bash $0 install       按当前环境变量安装
  sudo bash $0 change-port   交互式修改端口
  sudo bash $0 uninstall     按当前环境变量卸载

可选环境变量：
  PORT=55555
  COUNTRY=cn
  PROTO=both|tcp|udp

示例：
  sudo bash $0 menu
  sudo PORT=55555 PROTO=tcp bash $0 install
  sudo PORT=55555 bash $0 uninstall
EOF
}

case "${1:-menu}" in
    menu) show_menu ;;
    install) install_all ;;
    change-port|port) change_port ;;
    uninstall|remove) uninstall_all ;;
    update)
        need_root
        normalize_config
        ensure_nftables_include
        generate_rules
        ;;
    status) show_status ;;
    help|-h|--help) usage ;;
    *)
        usage
        exit 1
        ;;
esac
