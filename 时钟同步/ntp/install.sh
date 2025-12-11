#!/bin/bash
set -euo pipefail
trap 'cleanup' EXIT

# ===== 全局配置 =====
NTP_CONF="/etc/ntp.conf"
LOG_DIR="/var/log/ntp"
UNPACK_DIR="./ntp-unpacked"
RPM_DIR="./rpms"
SERVERS=()

# ===== 日志与错误处理 =====
log() {
    echo -e "[$(date '+%F %T')] $1"
}

error_exit() {
    log "❌ 错误: $1" >&2
    [[ -f "$LOG_DIR/ntpd.log" ]] && tail -20 "$LOG_DIR/ntpd.log" | log "查看日志"
    exit "${2:-1}"
}

cleanup() {
    [[ -f "${NTP_CONF}.tmp" ]] && rm -f "${NTP_CONF}.tmp"
}

# ===== 环境检查 =====
check_environment() {
    [[ $EUID -ne 0 ]] && error_exit "必须使用root运行"
    grep -qE "CentOS|Red Hat" /etc/os-release || error_exit "仅支持CentOS/RHEL系统" 2
    log "✅ 环境检查通过: $(grep -oP '(?<=PRETTY_NAME=").*(?=")' /etc/os-release)"
}

# ===== 解压安装包 =====
extract_package() {
    log "步骤1/6: 解压安装包..."
    [[ ! -f "ntp-pack.zip" ]] && error_exit "ntp-pack.zip 文件不存在" 3
    [[ -d "$UNPACK_DIR" ]] && { rm -rf "$UNPACK_DIR"; log "清理旧解压目录"; }

    unzip -qo ntp-pack.zip -d "$UNPACK_DIR" || error_exit "解压失败，检查压缩包完整性" 4

    mkdir -p "$RPM_DIR"
    find "$UNPACK_DIR" -name "*.rpm" -exec mv {} "$RPM_DIR" \;
    log "✅ RPM文件已移动到 $RPM_DIR"
}

# ===== RPM安装 =====
install_rpms() {
    log "步骤2/6: 安装RPM包..."
    local packages=("autogen-libopts-*.rpm" "ntp-*.rpm")

    for pkg in "${packages[@]}"; do
        local rpm_file=$(find "$RPM_DIR" -name "$pkg" | head -n1)
        [[ -z "$rpm_file" ]] && error_exit "未找到RPM文件: $pkg" 5

        local pkg_name=$(rpm -qp --queryformat '%{NAME}' "$rpm_file" 2>/dev/null)
        if rpm -q "$pkg_name" &>/dev/null; then
            log "ℹ️ 已安装: $pkg_name (跳过)"
            continue
        fi

        rpm -Uvh --force --nodeps "$rpm_file" >/dev/null 2>&1 || error_exit "安装失败: $rpm_file" 6
    done
    log "✅ 所有RPM包安装成功"
}

# ===== 配置时间源（修复重复参数）=====
configure_servers() {
    log "步骤3/6: 配置时间源..."
    timedatectl | grep -q "Time zone" || { timedatectl set-timezone Asia/Shanghai; log "ℹ️ 时区设置为Asia/Shanghai"; }

    while true; do
        read -p "> 请输入NTP服务器(空格分隔，留空使用默认池): " server_input
        if [[ -z "$server_input" ]]; then
            SERVERS=("ntp.aliyun.com" "cn.pool.ntp.org")
            log "ℹ️ 使用默认时间源: ${SERVERS[*]}"
            break
        fi

        read -ra input_servers <<< "$server_input"
        SERVERS=()
        local all_valid=1
        for srv in "${input_servers[@]}"; do
            if [[ "$srv" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$srv" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
                SERVERS+=("$srv")
            else
                log "⚠️ 无效地址: $srv (必须是IP或域名)"
                all_valid=0
            fi
        done
        [[ $all_valid -eq 1 && ${#SERVERS[@]} -ge 1 ]] && break
        [[ ${#SERVERS[@]} -lt 1 ]] && log "⚠️ 至少需要1个时间源"
    done

    # 首选服务器设置（仅添加prefer标记）
    if [[ ${#SERVERS[@]} -gt 1 ]]; then
        echo "可用服务器:"
        for i in "${!SERVERS[@]}"; do echo "  [$((i+1))] ${SERVERS[$i]}"; done

        local valid_choice=0
        while [[ $valid_choice -eq 0 ]]; do
            read -p "设置首选服务器序号(1-${#SERVERS[@]}，留空不设置): " prefer_index
            if [[ -z "$prefer_index" ]]; then
                log "ℹ️ 未设置首选服务器"
                valid_choice=1
            elif [[ "$prefer_index" =~ ^[0-9]+$ ]] && (( prefer_index >= 1 && prefer_index <= ${#SERVERS[@]} )); then
                SERVERS[$((prefer_index-1))]="${SERVERS[$((prefer_index-1))]} prefer"
                log "✅ 设置首选服务器: ${SERVERS[$((prefer_index-1))]}"
                valid_choice=1
            else
                log "⚠️ 无效输入: 请输入1-${#SERVERS[@]}之间的数字"
            fi
        done
    fi
}

# ===== 生成NTP配置（关键修复）=====
generate_ntp_conf() {
    log "步骤4/6: 生成NTP配置..."
    local timestamp=$(date +%s)
    [[ -f "$NTP_CONF" ]] && { cp -p "$NTP_CONF" "${NTP_CONF}.bak.$timestamp"; log "ℹ️ 原始配置已备份: ${NTP_CONF}.bak.$timestamp"; }

    mkdir -p "$LOG_DIR" && chown ntp:ntp "$LOG_DIR"

    # 生成配置（避免重复iburst）
    cat > "${NTP_CONF}.tmp" <<-EOF
driftfile /var/lib/ntp/drift

# ==== 安全访问限制 ====
restrict default kod nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1

# ==== 时间源配置 ====
$(for srv in "${SERVERS[@]}"; do
    if [[ $srv != *"iburst"* ]]; then
        echo "server $srv iburst"
    else
        echo "server $srv"
    fi
done)

# ==== 安全加固 ====
tinker panic 0  # 避免时间偏差过大时服务崩溃[6](@ref)
disable monitor  # 关闭监控模式防攻击[3](@ref)

# ==== 日志配置 ====
logfile $LOG_DIR/ntpd.log
logconfig =syncall +clockall

# ==== 本地时钟兜底 ====
server 127.127.1.0
fudge 127.127.1.0 stratum 10
EOF

    # 硬件时间同步
    echo "SYNC_HWCLOCK=yes" > /etc/sysconfig/ntpd

    # 日志轮转
    cat > /etc/logrotate.d/ntpd <<EOF
$LOG_DIR/ntpd.log {
    weekly
    missingok
    rotate 12
    compress
    delaycompress
    notifempty
    create 0640 ntp ntp
    postrotate
        systemctl try-reload-or-restart ntpd >/dev/null 2>&1 || true
    endscript
}
EOF

    mv "${NTP_CONF}.tmp" "$NTP_CONF"
    log "✅ 配置文件已更新"
}

# ===== 防火墙配置（持久化修复）=====
configure_firewall() {
    log "步骤5/6: 配置防火墙..."

    # firewalld处理[3](@ref)
    if systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --add-service=ntp --permanent >/dev/null
        firewall-cmd --reload >/dev/null
        log "✅ 已持久化开放firewalld (ntp服务)"
        return
    fi

    # iptables处理（增加规则保存）[3](@ref)
    if command -v iptables &>/dev/null; then
        if ! iptables -C INPUT -p udp --dport 123 -j ACCEPT &>/dev/null; then
            iptables -A INPUT -p udp --dport 123 -j ACCEPT
            # 持久化规则[3](@ref)
            if command -v iptables-save &>/dev/null; then
                mkdir -p /etc/sysconfig
                iptables-save > /etc/sysconfig/iptables
                log "✅ 已持久化开放iptables UDP 123端口"
            else
                log "⚠️ 开放iptables端口（需手动持久化）"
            fi
        fi
        return
    fi
    log "ℹ️ 未检测到活动防火墙"
}

# ===== 服务启动（状态检测修复）=====
start_service() {
    log "步骤6/6: 启动服务..."

    # 服务操作
    if systemctl is-active ntpd &>/dev/null; then
        systemctl restart ntpd && log "✅ 服务已重启"
    else
        systemctl enable --now ntpd && log "✅ 服务已启用"
    fi

    # 等待服务就绪（修复误判）[2](@ref)
    local wait_sec=15
    while ! systemctl is-active ntpd --quiet && ((wait_sec>0)); do
        sleep 1
        ((wait_sec--))
    done
    ((wait_sec<=0)) && error_exit "服务启动超时" 7

    # 首次同步检测
    verify_service
}

# ===== 健康检查（多维度验证）=====
verify_service() {
    log "健康验证..."
    local attempts=5 interval=5

    # 状态检测（使用退出码而非输出）[2](@ref)
    if ! systemctl is-active ntpd --quiet; then
        error_exit "服务未运行" 8
    fi

    # 同步状态检测
    for ((i=1; i<=attempts; i++)); do
        if ntpstat &>/dev/null; then
            offset=$(ntpstat 2>&1 | awk -F'[ ,]+' '/offset/ {print $(NF-1)}')
            [[ -n "$offset" ]] && log "✅ 同步成功! 时间偏移: ${offset}ms" || log "✅ 同步成功!"
            return 0
        fi
        sleep $interval
        log "等待同步中($i/$attempts)..."
    done

    # 层级验证
    if ntpq -pn | grep -q '^\*'; then
        log "✅ 找到有效时间源"
    else
        ntpq -pn
        error_exit "❌ 未找到有效时间源" 9
    fi
}

# ===== 结果展示 =====
show_summary() {
    local primary_ip=${SERVERS[0]%% *}  # 清理额外参数
    cat <<EOF


✅ NTP部署成功！
============================================
  配置文件  : $NTP_CONF (备份见 ${NTP_CONF}.bak.*)
  日志路径  : $LOG_DIR/ntpd.log
  时间源    : ${SERVERS[*]}

▶ 运维指南:
  强制同步  : ntpdate -u $primary_ip  # 使用纯净地址[5](@ref)
  状态检查  : ntpq -pn
  日志跟踪  : tail -f $LOG_DIR/ntpd.log

▶ 故障排查:
  1. 检查端口: netstat -unlp | grep 123
  2. 防火墙状态:
     - firewalld: firewall-cmd --list-ports
     - iptables: iptables -L -n | grep 123
  3. 详细日志: journalctl -u ntpd -f
============================================
EOF
}

# ===== 主流程 =====
main() {
    check_environment
    extract_package
    install_rpms
    configure_servers
    generate_ntp_conf
    configure_firewall
    start_service
    show_summary
}

main "$@"
