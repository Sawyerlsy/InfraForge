#!/usr/bin/env bash
# ============================================================================
# 通用健康检测脚本 for Keepalived
# 功能：检测 TCP 端口、HTTP/URL、进程或自定义命令的健康状态
# 日志：默认写入 /etc/keepalived/healthy_check.log，可自定义
# 用法：./health_check.sh -t tcp -p 80 -h 127.0.0.1
#       ./health_check.sh -t http -u http://localhost/health -c 200 -v
#       ./health_check.sh -t http -u http://localhost/health -c 200
#       ./health_check.sh -t process -P nginx
#       ./health_check.sh -t command -C "pgrep -x nginx"
# 返回：0 = 健康，非0 = 不健康（触发 Keepalived 权重调整或切换）
# 版本：1.1
# ============================================================================

set -euo pipefail

# 默认参数
TYPE=""                     # 检测类型：tcp, http, https, process, command
HOST="127.0.0.1"            # TCP/HTTP 目标主机
PORT=""                     # TCP 端口
URL=""                      # HTTP/HTTPS 完整 URL
EXPECTED_CODE="2xx"         # HTTP 期望的状态码范围（如 200, 2xx, 3xx）
PROCESS_NAME=""             # 进程名（pgrep 精确匹配）
COMMAND=""                  # 自定义检测命令
TIMEOUT=3                   # 超时秒数
VERBOSE=false               # 是否输出详细日志到终端
LOG_FILE="/etc/keepalived/healthy_check.log"  # 默认日志文件

# 显示帮助信息
show_help() {
    cat << EOF
Usage: $0 -t TYPE [options]

必需参数:
  -t TYPE       检测类型: tcp, http, https, process, command

TCP 类型选项:
  -h HOST       目标主机 (默认: 127.0.0.1)
  -p PORT       目标端口 (必需)

HTTP/HTTPS 类型选项:
  -u URL        完整 URL，如 http://127.0.0.1:80/health (必需)
  -c CODE       期望的 HTTP 状态码或范围，如 200, 2xx (默认: 2xx)

进程检测选项:
  -P NAME       进程名 (pgrep -x 精确匹配)

命令检测选项:
  -C "CMD"      自定义检测命令，退出码 0 表示健康

通用选项:
  -T SECONDS    超时时间，单位秒 (默认: 3)
  -l FILE       日志文件路径 (默认: /etc/keepalived/healthy_check.log)
  -v            详细模式，同时将日志输出到终端 (stderr)
  -h            显示此帮助信息

示例:
  $0 -t tcp -p 80
  $0 -t http -u http://localhost:8080/health -c 200
  $0 -t https -u https://127.0.0.1/status -c 2xx
  $0 -t process -P nginx
  $0 -t command -C "systemctl is-active nginx"
  $0 -t tcp -p 3306 -l /var/log/keepalived/mysql_check.log -v
EOF
    exit 0
}

# 初始化日志文件（确保目录存在且文件可写）
init_log() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            echo "ERROR: Cannot create log directory $log_dir" >&2
            exit 1
        }
    fi
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: Cannot write to log file $LOG_FILE" >&2
        exit 1
    }
}

# 日志输出：写入文件，若 VERBOSE=true 则同时输出到 stderr
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local msg="[$timestamp] $*"
    echo "$msg" >> "$LOG_FILE"
    if [[ "$VERBOSE" == true ]]; then
        echo "$msg" >&2
    fi
}

# 解析命令行参数
while getopts "t:h:p:u:c:P:C:T:l:vh" opt; do
    case $opt in
        t) TYPE="$OPTARG" ;;
        h) HOST="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        u) URL="$OPTARG" ;;
        c) EXPECTED_CODE="$OPTARG" ;;
        P) PROCESS_NAME="$OPTARG" ;;
        C) COMMAND="$OPTARG" ;;
        T) TIMEOUT="$OPTARG" ;;
        l) LOG_FILE="$OPTARG" ;;
        v) VERBOSE=true ;;
        *) show_help ;;
    esac
done

# 验证必需参数
if [[ -z "$TYPE" ]]; then
    echo "ERROR: 缺少检测类型 (-t)" >&2
    show_help
fi

# 初始化日志系统
init_log

# 根据类型执行检测
case "$TYPE" in
    tcp)
        if [[ -z "$PORT" ]]; then
            log "ERROR: TCP 检测需要指定端口 (-p)"
            exit 1
        fi
        log "检测 TCP: $HOST:$PORT (超时 ${TIMEOUT}s)"
        # 使用 bash 内置 /dev/tcp 进行连接测试
        if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/$HOST/$PORT" 2>/dev/null; then
            log "TCP 检测成功: $HOST:$PORT 可连接"
            exit 0
        else
            log "TCP 检测失败: $HOST:$PORT 不可连接"
            exit 1
        fi
        ;;

    http|https)
        if [[ -z "$URL" ]]; then
            log "ERROR: HTTP/HTTPS 检测需要指定 URL (-u)"
            exit 1
        fi
        # 自动补全 https 前缀（如果类型是 https 且 URL 未包含协议）
        if [[ "$TYPE" == "https" && ! "$URL" =~ ^https?:// ]]; then
            URL="https://$URL"
        elif [[ "$TYPE" == "http" && ! "$URL" =~ ^https?:// ]]; then
            URL="http://$URL"
        fi
        log "检测 HTTP: $URL (期望状态码: $EXPECTED_CODE, 超时 ${TIMEOUT}s)"

        # 优先使用 curl，其次使用 wget
        if command -v curl &>/dev/null; then
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$URL" 2>/dev/null || echo "000")
        elif command -v wget &>/dev/null; then
            HTTP_CODE=$(wget --spider --timeout="$TIMEOUT" --tries=1 -S "$URL" 2>&1 | grep -i "HTTP/" | tail -1 | awk '{print $2}' || echo "000")
        else
            log "ERROR: 既未找到 curl 也未找到 wget，无法进行 HTTP 检测"
            exit 1
        fi

        # 判断状态码是否匹配期望范围
        match=false
        if [[ "$EXPECTED_CODE" == "2xx" ]]; then
            [[ "$HTTP_CODE" =~ ^2[0-9]{2}$ ]] && match=true
        elif [[ "$EXPECTED_CODE" == "3xx" ]]; then
            [[ "$HTTP_CODE" =~ ^3[0-9]{2}$ ]] && match=true
        elif [[ "$EXPECTED_CODE" == "2xx3xx" ]]; then
            [[ "$HTTP_CODE" =~ ^(2|3)[0-9]{2}$ ]] && match=true
        else
            [[ "$HTTP_CODE" == "$EXPECTED_CODE" ]] && match=true
        fi

        if $match; then
            log "HTTP 检测成功: $URL 返回 $HTTP_CODE"
            exit 0
        else
            log "HTTP 检测失败: $URL 返回 $HTTP_CODE (期望 $EXPECTED_CODE)"
            exit 1
        fi
        ;;

    process)
        if [[ -z "$PROCESS_NAME" ]]; then
            log "ERROR: 进程检测需要指定进程名 (-P)"
            exit 1
        fi
        log "检测进程: $PROCESS_NAME"
        if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
            log "进程检测成功: $PROCESS_NAME 正在运行"
            exit 0
        else
            log "进程检测失败: 未找到进程 $PROCESS_NAME"
            exit 1
        fi
        ;;

    command)
        if [[ -z "$COMMAND" ]]; then
            log "ERROR: 命令检测需要指定命令 (-C)"
            exit 1
        fi
        log "检测自定义命令: $COMMAND"
        # 使用 timeout 防止命令卡死
        if timeout "$TIMEOUT" sh -c "$COMMAND" >/dev/null 2>&1; then
            log "命令检测成功: $COMMAND 返回 0"
            exit 0
        else
            log "命令检测失败: $COMMAND 返回非零或超时"
            exit 1
        fi
        ;;

    *)
        log "ERROR: 不支持的检测类型: $TYPE"
        show_help
        ;;
esac
