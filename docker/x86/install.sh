#!/bin/bash
set -euo pipefail

# ==================== 全局配置 ====================
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
DOCKER_TGZ=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'docker-*.tgz' -print -quit)
declare -a REQUIRED_FILES=("docker.service" "docker-compose")
INSTALL_DATE=$(date "+%Y-%m-%d")
START_TIME=$(date "+%H:%M:%S")
START_SECONDS=$SECONDS

# ==================== 格式化输出函数 ====================
function stage_start() {
    echo -e "\n\033[1;34m### $1\033[0m"
}

function step_info() {
    echo -e "  \033[1;36m$1\033[0m"
}

function step_ok() {
    echo -e "  ✅ $1"
}

function step_warn() {
    echo -e "  ⚠️  $1"
}

function step_error() {
    echo -e "  ❌ $1"
    exit 1
}

function step_action() {
    echo -e "  ➤ $1"
}

function step_input() {
    echo -ne "  ? $1 "
}

# ==================== 安装函数 ====================
check_docker_installed() {
    if command -v docker &>/dev/null; then
        local installed_ver=$(docker --version | awk '{print $3}')
        step_warn "检测到已安装 Docker | 版本: $installed_ver"
        step_input "是否继续安装？(y/n) "
        read -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            step_ok "安装已取消"
            exit 0
        fi
        step_ok "用户选择: 继续安装 (y)"
    else
        step_ok "未检测到 Docker 安装"
    fi
}

validate_package() {
    [[ -f "$DOCKER_TGZ" ]] || step_error "错误：未找到 docker 安装包"

    DOCKER_VER=$(basename "$DOCKER_TGZ" | grep -oP 'docker-\K[0-9.]+(?=\.tgz)')
    step_ok "找到安装包: docker-$DOCKER_VER.tgz"

    for file in "${REQUIRED_FILES[@]}"; do
        [[ -f "$SCRIPT_DIR/$file" ]] || step_error "缺失必要文件: $file"
    done
    step_ok "必要文件检查通过 [${REQUIRED_FILES[*]}]"

    # 确保docker-compose有执行权限
    if [[ ! -x "$SCRIPT_DIR/docker-compose" ]]; then
        chmod +x "$SCRIPT_DIR/docker-compose"
        step_ok "添加执行权限: docker-compose"
    fi
}

permanently_disable_selinux() {
    step_action "永久禁用 SELinux..."
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    setenforce 0
    step_ok "SELinux 已永久禁用 (当前为临时禁用,重启后永久禁用生效)"
}

disable_firewall_permanently() {
    step_action "永久禁用防火墙..."
    systemctl stop firewalld
    systemctl disable firewalld
    step_ok "防火墙已永久禁用"
}

check_selinux() {
    step_info "1. SELinux 状态检查"
    if [ -f /etc/selinux/config ]; then
        local current_state=$(getenforce 2>/dev/null || echo "Disabled")
        local config_state=$(grep -E '^SELINUX=' /etc/selinux/config | cut -d'=' -f2)

        step_ok "当前状态: $current_state"
        step_ok "配置状态: $config_state"

        if [[ "$current_state" != "Disabled" ]]; then
            step_warn "SELinux 处于启用状态，可能影响 Docker 正常运行"
            step_input "是否永久禁用 SELinux？(y/n) "
            read -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                permanently_disable_selinux
            fi
        fi
    else
        step_ok "未找到 SELinux 配置文件"
    fi
}

check_firewall() {
    step_info "2. 防火墙状态检查"
    local firewalld_status="已关闭"
    local iptables_status="已停止"

    # 检查firewalld
    if systemctl is-active firewalld &>/dev/null; then
        firewalld_status="运行中"
        step_action "检测到 firewalld 正在运行"
        step_input "是否永久禁用防火墙？(y/n) "
        read -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            disable_firewall_permanently
            firewalld_status="已关闭"
        else
            step_action "请手动开放以下 Docker 端口:"
            echo -e "    - TCP: 2375, 2376, 4243, 4244"
            echo -e "    - UDP: 4789, 7946"
        fi
    fi

    # 检查iptables
    if systemctl is-active iptables &>/dev/null; then
        iptables_status="运行中"
        step_action "检测到 iptables 正在运行"
        step_input "是否停止iptables服务？(y/n) "
        read -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            systemctl stop iptables
            systemctl disable iptables
            iptables_status="已停止"
            step_ok "iptables 已停止并禁用"
        fi
    fi

    step_ok "firewalld 状态: $firewalld_status"
    step_ok "iptables 状态: $iptables_status"
}

install_docker_core() {
    step_info "1. 解压安装包"
    if [[ -d "$SCRIPT_DIR/docker" ]]; then
        rm -rf "$SCRIPT_DIR/docker"
        step_ok "删除旧解压目录"
    fi

    tar -xvf "$DOCKER_TGZ" -C "$SCRIPT_DIR" >/dev/null
    local file_count=$(ls "$SCRIPT_DIR/docker" | wc -l)
    step_ok "安装包解压完成 | 组件文件数量: $file_count"

    step_info "2. 文件部署"
    # 复制新文件
    cp -f "$SCRIPT_DIR"/docker/* /usr/bin
    step_ok "二进制文件: 复制到 /usr/bin"

    # 安装docker-compose
    cp -f "$SCRIPT_DIR/docker-compose" /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    step_ok "Docker Compose: 安装到 /usr/local/bin"

    # 配置systemd服务
    cp -f "$SCRIPT_DIR/docker.service" /etc/systemd/system/
    chmod 644 /etc/systemd/system/docker.service
    step_ok "系统服务: docker.service 配置完成"
}

start_docker_service() {
    step_info "3. 服务管理"
    systemctl daemon-reload
    step_ok "服务重载: systemctl daemon-reload"

    systemctl start docker
    systemctl enable docker >/dev/null 2>&1

    # 检查服务状态
    local status=$(systemctl is-active docker)
    if [[ "$status" == "active" ]]; then
        step_ok "服务状态: 运行中 ($status)"
    else
        step_error "服务启动失败! 状态: $status"
    fi

    step_ok "开机自启: 已启用"
}

verify_components() {
    step_info "1. 组件版本验证"
    local docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "未知")
    local compose_ver=$(docker-compose version --short 2>/dev/null || echo "未知")
    local containerd_ver=$(containerd --version | awk '{print $3}' 2>/dev/null || echo "未知")
    local all_success=true

    echo -e "  | 组件          | 版本        | 状态       |"
    echo -e "  |---------------|-------------|------------|"

    # Docker Engine
    if [[ "$docker_ver" != "未知" ]]; then
        printf "  | Docker Engine | %-11s | ✅ 正常    |\n" "$docker_ver"
    else
        printf "  | Docker Engine | %-11s | ❌ 异常    |\n" "$docker_ver"
        all_success=false
    fi

    # Containerd
    if [[ "$containerd_ver" != "未知" ]]; then
        printf "  | Containerd    | %-11s | ✅ 正常    |\n" "$containerd_ver"
    else
        printf "  | Containerd    | %-11s | ❌ 异常    |\n" "$containerd_ver"
        all_success=false
    fi

    # Docker Compose
    if [[ "$compose_ver" != "未知" ]]; then
        printf "  | Docker Compose| %-11s | ✅ 正常    |\n" "$compose_ver"
    else
        printf "  | Docker Compose| %-11s | ❌ 异常    |\n" "$compose_ver"
        all_success=false
    fi

    if ! $all_success; then
        step_error "关键组件验证失败，请检查日志"
    fi
}

# ==================== 主执行流程 ====================
main() {
    # 标题与时间
    echo -e "\n\033[1;35m===== Docker 离线安装程序 =====\033[0m"
    echo -e "\033[1;33m📅 $INSTALL_DATE | ⏱ 开始时间: $START_TIME\033[0m"

    # 阶段一：系统环境检测
    stage_start "阶段一：系统环境检测"
    [[ $(id -u) -eq 0 ]] || step_error "必须使用 root 权限执行本脚本"
    step_ok "执行权限: root 用户"
    check_docker_installed
    validate_package

    # 阶段二：安全配置
    stage_start "阶段二：安全配置"
    check_selinux
    check_firewall

    # 阶段三：核心组件安装
    stage_start "阶段三：核心组件安装"
    install_docker_core
    start_docker_service

    # 阶段四：组件安装验证
    stage_start "阶段四：组件安装验证"
    verify_components

    # 阶段五：使用配置
    stage_start "阶段五：使用配置"
    step_info "1. 用户权限管理"
    step_action "添加用户到 docker 组:"
    echo -e "    sudo usermod -aG docker <用户名>"
    step_ok "生效方式: 注销后重新登录"

    step_info "2. 镜像加速配置"
    step_action "推荐镜像源:"
    echo -e "    - https://docker.1panel.top"
    echo -e "    - https://hub-mirror.c.163.com"
    echo -e "    - https://mirror.baidubce.com"
    step_action "配置方法:"
    echo -e "    1. sudo nano /etc/docker/daemon.json"
    echo -e "    2. 添加内容:"
    echo -e "        {"
    echo -e "          \"registry-mirrors\": ["
    echo -e "            \"https://docker.1panel.top\""
    echo -e "          ]"
    echo -e "        }"
    echo -e "    3. sudo systemctl restart docker"

    step_info "3. 安全加固建议"
    step_action "运行安全扫描:"
    echo -e "    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock docker/docker-bench-security"
    step_action "禁用容器 root 权限:"
    echo -e "    在 Dockerfile 中添加: USER <非root用户>"

    # 完成报告
    local duration=$((SECONDS - START_SECONDS))
    local end_time=$(date "+%H:%M:%S")
    echo -e "\n\033[1;35m===== 安装完成 =====\033[0m"
    step_ok "开始时间: $START_TIME"
    step_ok "结束时间: $end_time"
    step_ok "总耗时: ${duration}秒"
    step_ok "服务状态: $(systemctl is-active docker)"

    echo -e "\n💡 验证命令:"
    echo -e "  docker version    | 查看 Docker 版本"
    echo -e "  docker ps         | 检查容器状态"
    echo -e "  docker info       | 查看系统信息"
    echo -e "  docker stats      | 查看容器资源使用"

    echo -e "\n✔ 安装成功! 建议重新启动系统以确保所有配置生效。"
}

# 执行主函数
main
