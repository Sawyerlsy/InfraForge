#!/bin/bash
set -euo pipefail

# ==================== 全局配置 ====================
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
UNINSTALL_DATE=$(date "+%Y-%m-%d")
START_TIME=$(date "+%H:%M:%S")
START_SECONDS=$SECONDS
LOG_FILE="/var/log/docker_uninstall_$(date +%Y%m%d%H%M%S).log"

# ==================== 格式化输出函数 ====================
function stage_start() {
    echo -e "\n\033[1;34m### $1\033[0m" | tee -a "$LOG_FILE"
}

function step_info() {
    echo -e "  \033[1;36m$1\033[0m" | tee -a "$LOG_FILE"
}

function step_ok() {
    echo -e "  ✅ $1" | tee -a "$LOG_FILE"
}

function step_warn() {
    echo -e "  ⚠️  $1" | tee -a "$LOG_FILE"
}

function step_error() {
    echo -e "  ❌ $1" | tee -a "$LOG_FILE"
    exit 1
}

function step_action() {
    echo -e "  ➤ $1" | tee -a "$LOG_FILE"
}

function step_input() {
    echo -ne "  ? $1 " | tee -a "$LOG_FILE"
}

# ==================== 安全卸载函数 ====================
check_root() {
    [[ $(id -u) -eq 0 ]] || step_error "必须使用 root 权限执行本脚本"
    step_ok "执行权限: root 用户"
}

confirm_uninstall() {
    step_info "当前系统状态:"
    if command -v docker &>/dev/null; then
        local installed_ver=$(docker --version | awk '{print $3}')
        step_ok "检测到已安装 Docker | 版本: $installed_ver"
    else
        step_ok "未检测到 Docker 安装"
    fi

    step_warn "重要安全提示:"
    step_warn "1. 卸载前请确保已备份重要容器和数据"
    step_warn "2. 强制删除可能导致系统网络服务中断"
    step_warn "3. 卸载完成后需要重启系统释放内核资源"

    step_input "确定要卸载 Docker 及其所有组件吗？(y/n) "
    read -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        step_ok "卸载已取消"
        exit 0
    fi
    step_ok "用户选择: 继续卸载 (y)"
}

safe_remove_containers() {
    step_input "是否删除所有 Docker 容器？(y/n) "
    read -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        step_action "安全停止容器..."
        if docker ps -a -q | grep -q .; then
            docker stop $(docker ps -a -q) 2>/dev/null || true
            step_ok "容器已停止"

            step_action "删除容器..."
            docker rm -f $(docker ps -a -q) 2>/dev/null || true
            step_ok "容器已删除"
        else
            step_ok "没有运行的容器"
        fi
    else
        step_ok "跳过容器删除"
    fi
}

safe_remove_images() {
    step_input "是否删除所有 Docker 镜像？(y/n) "
    read -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        step_action "删除镜像..."
        if docker images -q | grep -q .; then
            docker rmi -f $(docker images -q) 2>/dev/null || true
            step_ok "镜像已删除"
        else
            step_ok "没有镜像存在"
        fi
    else
        step_ok "跳过镜像删除"
    fi
}

safe_remove_volumes() {
    step_input "是否删除所有 Docker 卷？(y/n) "
    read -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        step_action "删除卷..."
        docker volume prune -f 2>/dev/null || true
        step_ok "匿名卷已删除"

        # 仅删除未使用的卷
        docker volume rm $(docker volume ls -q -f dangling=true) 2>/dev/null || true
        step_ok "未使用卷已删除"
    else
        step_ok "跳过卷删除"
    fi
}

function safe_clean_network() {
    step_action "安全清理网络命名空间..."
    local netns_dir="/var/run/docker/netns"
    local default_netns="$netns_dir/default"

    if [ -d "$netns_dir" ]; then
        # 处理默认网络命名空间占用问题
        if [ -f "$default_netns" ]; then
            step_action "处理默认网络命名空间..."

            # 1. 安全重启NetworkManager释放资源
            if systemctl is-active NetworkManager &>/dev/null; then
                if ! systemctl restart NetworkManager; then
                    step_warn "NetworkManager重启失败，但继续尝试清理"
                fi
                sleep 2
            fi

            # 2. 查找并终止占用进程
            local busy_pids=$(lsof -t "$default_netns" 2>/dev/null || true)
            if [[ -n "$busy_pids" ]]; then
                step_warn "检测到占用进程: PID $busy_pids"
                kill -9 $busy_pids 2>/dev/null || true
                step_ok "已终止占用进程"
                sleep 1
            fi

            # 3. 尝试卸载挂载点
            if mountpoint -q "$default_netns" 2>/dev/null; then
                if umount "$default_netns" 2>/dev/null; then
                    step_ok "已卸载挂载点"
                else
                    step_warn "卸载失败（重启系统后将自动释放）"
                fi
            fi

            # 4. 尝试删除文件（忽略失败）
            if rm -f "$default_netns" 2>/dev/null; then
                step_ok "已删除默认网络命名空间"
            else
                step_warn "删除失败: Device or resource busy"
                step_warn "此错误不影响主流程，重启系统后将自动释放"
            fi
        fi

        # 5. 清理父目录（强制继续）
        rm -rf "$netns_dir" 2>/dev/null || true
        step_ok "网络命名空间目录已清理"
    else
        step_ok "未找到网络命名空间目录"
    fi
}

stop_services() {
    step_action "停止 Docker 服务..."
    declare -a docker_services=("docker" "docker.socket" "containerd")

    for service in "${docker_services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            step_ok "已停止并禁用: $service"
        fi
    done
}

remove_packages() {
    step_action "卸载 Docker 软件包..."
    if command -v yum &>/dev/null; then
        # 扩展卸载包列表
        yum remove -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin \
            docker \
            docker-client \
            docker-client-latest \
            docker-common \
            docker-latest \
            docker-latest-logrotate \
            docker-logrotate \
            docker-engine 2>/dev/null || true
        step_ok "YUM包已卸载"
    elif command -v apt-get &>/dev/null; then
        # 扩展卸载包列表
        apt-get purge -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin \
            lxc-docker* \
            docker* \
            docker-engine* \
            docker.io* 2>/dev/null || true
        step_ok "APT包已卸载"
    fi
}

remove_files() {
    step_action "删除 Docker 专用目录..."
    declare -a docker_dirs=(
        "/etc/docker"
        "/var/lib/docker"
        "/var/lib/containerd"
        "/var/run/docker"
        "/var/run/containerd"
    )

    for dir in "${docker_dirs[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir" 2>/dev/null || true
            step_ok "已删除: $dir"
        fi
    done

    # 增加删除docker.sock
    if [ -S "/var/run/docker.sock" ]; then
        rm -f "/var/run/docker.sock" 2>/dev/null || true
        step_ok "已删除: /var/run/docker.sock"
    fi

    step_action "删除 Docker 可执行文件..."
    declare -a docker_binaries=(
        "/usr/bin/docker"
        "/usr/bin/dockerd"
        "/usr/bin/containerd"
        "/usr/bin/containerd-shim"
        "/usr/bin/containerd-shim-runc-v2"
        "/usr/bin/ctr"
        "/usr/bin/runc"
        "/usr/bin/docker-init"
        "/usr/bin/docker-proxy"
        "/usr/local/bin/docker-compose"
    )

    for binary in "${docker_binaries[@]}"; do
        if [ -f "$binary" ]; then
            rm -f "$binary" 2>/dev/null || true
            step_ok "已删除: $binary"
        fi
    done

    # 增加删除用户配置文件
    local user_config="$HOME/.docker"
    if [ -d "$user_config" ]; then
        rm -rf "$user_config" 2>/dev/null || true
        step_ok "已删除用户配置: $user_config"
    fi
}

protect_system() {
    step_action "保护系统组件..."
    # 跳过docker用户组删除（可能被系统共用）
    step_ok "已跳过docker用户组删除（防止影响系统用户）"

    # 跳过非Docker卷删除
    step_ok "已跳过非Docker卷检测"

    # 增加系统服务清理
    step_action "清理系统服务配置..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed 2>/dev/null || true
    step_ok "系统服务配置已清理"
}

clean_system() {
    step_action "清理系统缓存..."
    if command -v yum &>/dev/null; then
        yum clean all 2>/dev/null || true
        step_ok "YUM缓存已清理"
    elif command -v apt-get &>/dev/null; then
        apt-get autoremove -y 2>/dev/null || true
        apt-get clean 2>/dev/null || true
        step_ok "APT缓存已清理"
    fi
}

verify_uninstall() {
    # 刷新Shell缓存避免误报
    hash -r 2>/dev/null || true

    step_info "验证卸载结果:"
    # 验证可执行文件（检查实际文件而非命令缓存）
    local docker_found=0
    for path in /usr/bin/docker /usr/local/bin/docker /bin/docker; do
        if [ -f "$path" ]; then
            step_warn "发现残留文件: $path"
            docker_found=1
        fi
    done

    if [ $docker_found -eq 0 ]; then
        step_ok "无残留Docker可执行文件"
    fi

    # 验证目录
    declare -a check_dirs=("/etc/docker" "/var/lib/docker" "/var/run/docker")
    local dirs_found=0
    for dir in "${check_dirs[@]}"; do
        if [ -d "$dir" ]; then
            step_warn "发现残留目录: $dir"
            dirs_found=1
        fi
    done

    if [ $dirs_found -eq 0 ]; then
        step_ok "无残留Docker目录"
    fi

    # 验证服务
    if systemctl list-unit-files | grep -q docker; then
        step_warn "发现残留Docker服务"
    else
        step_ok "无残留Docker服务"
    fi

    if [ $docker_found -eq 0 ] && [ $dirs_found -eq 0 ]; then
        step_ok "所有Docker组件已安全移除"
    else
        step_warn "发现部分残留组件，重启系统后将自动释放"
    fi
}

# ==================== 主执行流程 ====================
main() {
    echo -e "\n\033[1;35m===== Docker安全卸载程序 =====\033[0m" | tee "$LOG_FILE"
    echo -e "\033[1;33m📅 $UNINSTALL_DATE | ⏱ 开始时间: $START_TIME\033[0m" | tee -a "$LOG_FILE"
    echo -e "\033[1;33m📝 日志文件: $LOG_FILE\033[0m" | tee -a "$LOG_FILE"
    echo -e "\033[1;33m💻 操作系统: $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')\033[0m" | tee -a "$LOG_FILE"

    stage_start "阶段一：权限与确认"
    check_root
    confirm_uninstall

    stage_start "阶段二：资源清理"
    safe_remove_containers
    safe_remove_images
    safe_remove_volumes

    stage_start "阶段三：服务处理"
    safe_clean_network
    stop_services

    stage_start "阶段四：组件卸载"
    remove_packages
    remove_files

    stage_start "阶段五：系统保护"
    protect_system
    clean_system

    stage_start "阶段六：结果验证"
    verify_uninstall

    local duration=$((SECONDS - START_SECONDS))
    local end_time=$(date "+%H:%M:%S")
    echo -e "\n\033[1;35m===== 卸载完成 =====\033[0m" | tee -a "$LOG_FILE"
    step_ok "开始时间: $START_TIME" | tee -a "$LOG_FILE"
    step_ok "结束时间: $end_time" | tee -a "$LOG_FILE"
    step_ok "总耗时: ${duration}秒" | tee -a "$LOG_FILE"

    # 增加重要提示
    echo -e "\n\033[1;31m💡 重要提示: 必须重启系统以释放所有内核资源！\033[0m" | tee -a "$LOG_FILE"
    echo -e "\033[1;33m   执行命令: sudo reboot\033[0m" | tee -a "$LOG_FILE"
    echo -e "\033[1;33m   日志文件已保存至: $LOG_FILE\033[0m" | tee -a "$LOG_FILE"
}

# 执行主函数
main
