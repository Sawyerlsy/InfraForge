#!/bin/bash
set -euo pipefail

###############################################################################
#                             配置参数
###############################################################################
readonly DEPLOY_DIR="."
readonly HARBOR_DOMAIN="core.harbor.domain:32388"
readonly DEFAULT_HARBOR_REGISTRY="${HARBOR_DOMAIN}/virtual-station-guangdong"
readonly DEBUG="true"
readonly PUSH_IMAGES="true"  # 是否推送镜像到私有仓库
readonly HARBOR_USERNAME="${HARBOR_USERNAME:-admin}"  # Harbor用户名（环境变量）
readonly HARBOR_PASSWORD="${HARBOR_PASSWORD:-HGrica1_2de10}"  # Harbor密码（环境变量）

# 服务名前缀配置（可通过环境变量覆盖）
readonly SERVICE_PREFIX="${SERVICE_PREFIX:-virtual-station-}"

# 临时文件目录（使用mktemp确保唯一性）
readonly TEMP_DIR=$(mktemp -d)
trap 'cleanup' EXIT INT TERM HUP

# Harbor登录状态缓存
HARBOR_LOGIN_CACHE_FILE="${TEMP_DIR}/harbor_login.cache"
declare -g HARBOR_LOGGED_IN=false

###############################################################################
#                             颜色和样式定义
###############################################################################
# 颜色代码
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# 样式
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

# 图标
readonly SUCCESS_ICON="✓"
readonly ERROR_ICON="✗"
readonly INFO_ICON="ℹ"
readonly WARNING_ICON="⚠"

# 分隔符
readonly SECTION_SEPARATOR="════════════════════════════════════════════════════════════════"
readonly STEP_SEPARATOR="────────────────────────────────────────────────────────────────"

###############################################################################
#                             日志函数
###############################################################################

# 输出日志部分标题
log_section() {
    echo -e "\n${BOLD}${CYAN}${SECTION_SEPARATOR}${NC}" >&2
    echo -e "${BOLD}${CYAN}$1${NC}" >&2
    echo -e "${CYAN}${SECTION_SEPARATOR}${NC}\n" >&2
}

# 输出步骤信息
log_step() {
    echo -e "${BOLD}${BLUE}${INFO_ICON} $1${NC}" >&2
}

# 输出成功信息
log_success() {
    echo -e "${GREEN}${SUCCESS_ICON} $1${NC}" >&2
}

# 输出信息
log_info() {
    echo -e "${BLUE}${INFO_ICON} $1${NC}" >&2
}

# 输出警告信息
log_warn() {
    echo -e "${YELLOW}${WARNING_ICON} $1${NC}" >&2
}

# 输出错误信息
log_error() {
    echo -e "${RED}${ERROR_ICON} $1${NC}" >&2
}

# 输出详细信息（调试用）
log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${DIM}  DEBUG: $1${NC}" >&2
    fi
}

# 输出命令执行结果
log_exec_result() {
    if [[ $? -eq 0 ]]; then
        log_success "$1"
    else
        log_error "$1"
    fi
}

###############################################################################
#                             工具函数
###############################################################################

# 清理临时文件和资源
cleanup() {
    local exit_code=$?

    log_debug "开始清理临时资源..."

    # 删除临时目录
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
        log_debug "临时目录已清理: ${TEMP_DIR}"
    fi

    # 清理Docker悬空镜像（仅在成功时执行）
    if [[ ${exit_code} -eq 0 ]] && command -v docker &>/dev/null; then
        local dangling_count
        dangling_count=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
        if [[ ${dangling_count} -gt 0 ]]; then
            log_debug "清理${dangling_count}个悬空镜像"
            docker images -f "dangling=true" -q | xargs -r docker rmi 2>/dev/null || true
        fi
    fi

    log_debug "资源清理完成"
}

# 检查命令是否存在
check_command() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        log_error "命令未找到: ${cmd}"
        return 1
    fi
    return 0
}

# 安全执行Docker命令，捕获错误
safe_docker_cmd() {
    local cmd="$1"
    local error_msg="${2:-Docker命令执行失败}"

    if ! docker ${cmd} 2>/dev/null; then
        log_error "${error_msg}: docker ${cmd}"
        return 1
    fi
    return 0
}

# 检查Harbor登录状态（带缓存）
check_harbor_login() {
    local harbor_domain="${1:-${HARBOR_DOMAIN}}"

    # 检查缓存
    if [[ -f "${HARBOR_LOGIN_CACHE_FILE}" ]]; then
        if [[ "$(cat "${HARBOR_LOGIN_CACHE_FILE}" 2>/dev/null)" == "true" ]]; then
            log_debug "使用缓存的Harbor登录状态: 已登录"
            HARBOR_LOGGED_IN=true
            return 0
        elif [[ "$(cat "${HARBOR_LOGIN_CACHE_FILE}" 2>/dev/null)" == "false" ]]; then
            log_debug "使用缓存的Harbor登录状态: 未登录"
            HARBOR_LOGGED_IN=false
            return 1
        fi
    fi

    log_debug "检查Harbor登录状态: ${harbor_domain}"

    # 方法1: 检查docker配置文件中是否有对应域名的认证信息
    if [[ -f ~/.docker/config.json ]]; then
        if grep -q "\"${harbor_domain}\"" ~/.docker/config.json; then
            log_debug "在docker配置中找到Harbor认证信息"
            echo "true" > "${HARBOR_LOGIN_CACHE_FILE}"
            HARBOR_LOGGED_IN=true
            return 0
        fi
    fi

    # 方法2: 尝试获取镜像列表（不显示输出）
    if timeout 5s docker pull "${harbor_domain}/test:latest" 2>&1 | grep -q "manifest unknown"; then
        log_debug "可以访问Harbor但镜像不存在（正常情况）"
        echo "true" > "${HARBOR_LOGIN_CACHE_FILE}"
        HARBOR_LOGGED_IN=true
        return 0
    fi

    # 方法3: 检查认证错误
    if timeout 5s docker pull "${harbor_domain}/test:latest" 2>&1 | grep -q "unauthorized\|denied"; then
        log_debug "未认证或认证失败"
        echo "false" > "${HARBOR_LOGIN_CACHE_FILE}"
        HARBOR_LOGGED_IN=false
        return 1
    fi

    # 默认认为未登录
    log_debug "无法确定Harbor登录状态"
    echo "false" > "${HARBOR_LOGIN_CACHE_FILE}"
    HARBOR_LOGGED_IN=false
    return 1
}

# 登录到Harbor仓库
login_to_harbor() {
    local harbor_domain="${1:-${HARBOR_DOMAIN}}"

    log_debug "登录到Harbor仓库: ${harbor_domain}"

    # 检查是否已登录
    if check_harbor_login "${harbor_domain}"; then
        log_success "已登录到Harbor"
        return 0
    fi

    # 尝试从环境变量获取凭证
    if [[ -z "${HARBOR_USERNAME}" ]] || [[ -z "${HARBOR_PASSWORD}" ]]; then
        log_warn "未设置Harbor认证环境变量"
        log_info "请设置以下环境变量："
        log_info "  export HARBOR_USERNAME=\"your-username\""
        log_info "  export HARBOR_PASSWORD=\"your-password\""
        return 1
    fi

    # 尝试登录
    log_debug "使用环境变量凭证登录..."
    if echo "${HARBOR_PASSWORD}" | docker login "${harbor_domain}" \
        --username "${HARBOR_USERNAME}" \
        --password-stdin 2>/dev/null; then
        log_success "登录成功"
        # 更新缓存
        echo "true" > "${HARBOR_LOGIN_CACHE_FILE}"
        HARBOR_LOGGED_IN=true
        return 0
    else
        log_error "登录失败"
        # 更新缓存
        echo "false" > "${HARBOR_LOGIN_CACHE_FILE}"
        HARBOR_LOGGED_IN=false
        return 1
    fi
}

###############################################################################
#                             环境检查
###############################################################################

check_prerequisites() {
    log_section ">>>>> 环境检查"

    if ! check_command "docker"; then
        log_error "请先安装Docker"
        exit 1
    fi
    log_success "Docker版本: $(docker --version | cut -d' ' -f3- | tr -d ',')"

    if ! docker info &>/dev/null; then
        log_error "Docker守护进程未运行或无权限访问"
        log_info "请确保:"
        log_info "1. Docker服务已启动 (systemctl start docker)"
        log_info "2. 当前用户在docker组中"
        exit 1
    fi
    log_success "Docker守护进程正常"

    if [[ ! -d "${DEPLOY_DIR}" ]]; then
        log_error "部署目录不存在: ${DEPLOY_DIR}"
        exit 1
    fi
    log_success "部署目录: ${DEPLOY_DIR}"

    # 初始化Harbor登录状态缓存
    > "${HARBOR_LOGIN_CACHE_FILE}"

    # 检查是否需要推送镜像
    if [[ "${PUSH_IMAGES}" == "true" ]]; then
        log_debug "检查Harbor仓库连接"
        if ! login_to_harbor; then
            log_warn "无法连接到Harbor仓库，推送功能将被禁用"
            local disable_push=""
            read -t 10 -p "是否继续导入但不推送镜像？(y/N, 10秒后默认继续): " disable_push || true
            if [[ "${disable_push}" =~ ^[Yy]$ ]]; then
                log_info "继续导入镜像但不推送"
            else
                log_error "推送镜像需要Harbor仓库访问权限"
                log_info "您可以："
                log_info "1. 设置 HARBOR_USERNAME 和 HARBOR_PASSWORD 环境变量"
                log_info "2. 手动执行: docker login ${HARBOR_DOMAIN}"
                log_info "3. 设置 PUSH_IMAGES=false 禁用推送"
                exit 1
            fi
        fi
    fi
}

###############################################################################
#                             镜像前缀选择
###############################################################################

# 提取基础服务名（移除服务前缀）
get_base_service_name() {
    local service_name="$1"
    # 如果服务名以SERVICE_PREFIX开头，则移除前缀
    if [[ "${service_name}" == "${SERVICE_PREFIX}"* ]]; then
        echo "${service_name#${SERVICE_PREFIX}}"
    else
        echo "${service_name}"
    fi
}

# 获取完整服务名（确保包含服务前缀）
get_full_service_name() {
    local service_name="$1"
    # 如果服务名不以SERVICE_PREFIX开头，则添加前缀
    if [[ ! "${service_name}" =~ ^${SERVICE_PREFIX} ]]; then
        echo "${SERVICE_PREFIX}${service_name}"
    else
        echo "${service_name}"
    fi
}

# 智能选择仓库前缀
select_registry_prefix() {
    local service_name="$1"
    local target_prefix=""

    log_debug "为服务 ${service_name} 选择仓库前缀"

    # 提取基础服务名
    local base_service_name
    base_service_name=$(get_base_service_name "${service_name}")

    # 方案1：查找相同服务的镜像（精确匹配）
    local same_service_prefix
    same_service_prefix=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | \
        grep "${HARBOR_DOMAIN}/" | \
        grep -E "/${SERVICE_PREFIX}${base_service_name}:" | \
        head -1 | \
        cut -d'/' -f1-2)

    if [[ -n "${same_service_prefix}" ]]; then
        target_prefix="${same_service_prefix}"
        log_debug "使用 ${SERVICE_PREFIX}${base_service_name} 匹配镜像前缀（精确匹配）: ${target_prefix}"
        echo "${target_prefix}"
        return 0
    fi

    # 方案2：查找相同服务的镜像（宽松匹配，允许其他前缀）
    same_service_prefix=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | \
        grep "${HARBOR_DOMAIN}/" | \
        grep -E "/.*${base_service_name}:" | \
        head -1 | \
        cut -d'/' -f1-2)

    if [[ -n "${same_service_prefix}" ]]; then
        target_prefix="${same_service_prefix}"
        log_debug "使用 ${base_service_name} 匹配镜像前缀（宽松匹配）: ${target_prefix}"
        echo "${target_prefix}"
        return 0
    fi

    # 查找任何包含服务前缀的镜像的前缀
    local any_prefixed_image
    any_prefixed_image=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | \
        grep "${HARBOR_DOMAIN}/" | \
        grep "${SERVICE_PREFIX}" | \
        head -1 | \
        cut -d'/' -f1-2)

    if [[ -n "${any_prefixed_image}" ]]; then
        target_prefix="${any_prefixed_image}"
        log_debug "使用服务前缀 ${SERVICE_PREFIX} 匹配镜像前缀: ${target_prefix}"
        echo "${target_prefix}"
        return 0
    fi

    # 使用环境变量（如果设置）
    if [[ -n "${TARGET_PREFIX:-}" ]]; then
        target_prefix="${HARBOR_DOMAIN}/${TARGET_PREFIX}"
        log_debug "使用环境变量前缀: ${target_prefix}"
        echo "${target_prefix}"
        return 0
    fi

    # 使用默认前缀
    log_debug "使用默认前缀: ${DEFAULT_HARBOR_REGISTRY}"
    echo "${DEFAULT_HARBOR_REGISTRY}"
}

###############################################################################
#                             镜像处理
###############################################################################

# 解析tar/tar.gz文件名，提取服务名和版本（同时支持 .tar 和 .tar.gz）
parse_tar_filename() {
    local tar_file="$1"
    local filename
    filename=$(basename "${tar_file}")

    # 假设格式: <service>-<version>.tar
    # 或: <prefix>-<service>-<version>.tar
    # 或: <prefix>-<service>-<version>.tar.gz

    # 先去掉 .tar.gz，再去掉 .tar
    filename="${filename%.tar.gz}"
    filename="${filename%.tar}"

    local service_name
    local version
    # 提取版本（最后一个 - 后面的部分）
    version="${filename##*-}"
    # 提取服务名（去掉版本部分）
    service_name="${filename%-${version}}"

    echo "${service_name}|${version}"
}

# 推送镜像到Harbor仓库（使用缓存的登录状态）
push_image_to_harbor() {
    local image_tag="$1"
    local retry_count=0
    local max_retries=2

    if [[ "${PUSH_IMAGES}" != "true" ]]; then
        log_debug "推送功能已禁用，跳过推送: ${image_tag}"
        return 0
    fi

    # 检查登录状态（使用缓存）
    if [[ "${HARBOR_LOGGED_IN}" != "true" ]]; then
        log_warn "未登录到Harbor，跳过推送: ${image_tag}"
        return 1
    fi

    log_step "开始推送镜像"

    # 尝试推送，允许重试
    while [[ ${retry_count} -lt ${max_retries} ]]; do
        log_debug "推送尝试 $((retry_count + 1))/${max_retries}"

        if docker push --quiet "${image_tag}" >/dev/null 2>"${TEMP_DIR}/push_error.log"; then
            log_success "推送成功: ${image_tag}"
            return 0
        fi

        ((retry_count++))

        # 如果是权限问题，尝试重新登录
        if grep -q "unauthorized\|denied" "${TEMP_DIR}/push_error.log"; then
            log_warn "认证失败，尝试重新登录..."
            if ! login_to_harbor; then
                log_error "重新登录失败，放弃推送"
                return 1
            fi
        elif [[ ${retry_count} -lt ${max_retries} ]]; then
            log_warn "推送失败，等待3秒后重试..."
            sleep 3
        fi
    done

    # 所有重试都失败
    log_error "推送失败: ${image_tag}"
    cat "${TEMP_DIR}/push_error.log" >&2
    return 1
}

# 导入单个镜像tar/tar.gz文件
import_single_image() {
    local tar_file="$1"
    local service_name="$2"
    local version="$3"

    log_step "处理: ${BOLD}$(basename "${tar_file}")${NC}"
    log_debug "原始服务名: ${service_name}, 版本: ${version}"

    # 记录开始时间
    local start_time
    start_time=$(date +%s)

    # 步骤1: 标准化服务名（确保包含服务前缀）
    local full_service_name
    full_service_name=$(get_full_service_name "${service_name}")
    log_debug "标准化服务名: ${full_service_name}"

    # 步骤2: 选择仓库前缀
    local harbor_registry
    harbor_registry=$(select_registry_prefix "${full_service_name}")

    if [[ ! "${harbor_registry}" =~ ^${HARBOR_DOMAIN}/ ]]; then
        log_warn "仓库前缀格式无效，使用默认值"
        harbor_registry="${DEFAULT_HARBOR_REGISTRY}"
    fi

    # 构建新标签
    local new_image_tag="${harbor_registry}/${full_service_name}:${version}"

    # 步骤3: 导入镜像（docker load 原生支持 .tar 和 .tar.gz）
    local load_output="${TEMP_DIR}/load_output_${full_service_name}.txt"
    local load_status="success"

    if ! docker load -i "${tar_file}" > "${load_output}" 2>&1; then
        log_error "镜像导入失败: ${tar_file}"
        cat "${load_output}" >&2
        load_status="failed"

        # 记录处理结果
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "${full_service_name}|${version}|${harbor_registry}|${new_image_tag}|failed|skipped|${duration}" >> "${TEMP_DIR}/processed_images.txt"
        return 1
    fi

    # 提取导入的镜像ID
    local image_id
    if grep -q "Loaded image ID:" "${load_output}"; then
        image_id=$(grep "Loaded image ID:" "${load_output}" | awk '{print $4}')
    elif grep -q "Loaded image:" "${load_output}"; then
        local image_ref
        image_ref=$(grep "Loaded image:" "${load_output}" | awk '{print $3}')
        image_id=$(docker inspect --format='{{.Id}}' "${image_ref}" 2>/dev/null || echo "")
    fi

    if [[ -z "${image_id}" ]]; then
        log_error "镜像导入成功,但是无法获取导入的镜像ID"
        load_status="failed"
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "${full_service_name}|${version}|${harbor_registry}|${new_image_tag}|failed|skipped|${duration}" >> "${TEMP_DIR}/processed_images.txt"
        return 1
    fi

    log_debug "镜像导入成功: ${image_id}"

    # 保存镜像ID用于后续处理
    echo "${image_id}" >> "${TEMP_DIR}/imported_images.txt"

    # 步骤4: 标记镜像
    if ! docker tag "${image_id}" "${new_image_tag}"; then
        log_error "添加新标签失败: ${new_image_tag}"
        load_status="failed"
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "${full_service_name}|${version}|${harbor_registry}|${new_image_tag}|failed|skipped|${duration}" >> "${TEMP_DIR}/processed_images.txt"
        return 1
    fi

    log_debug "添加新标签: ${new_image_tag}"

    # 步骤5: 清理原始标签（保留新标签）
    local original_tags_file="${TEMP_DIR}/original_tags_${full_service_name}.txt"
    docker inspect --format='{{range .RepoTags}}{{.}}{{"\n"}}{{end}}' "${image_id}" 2>/dev/null | \
        grep -v '^$' > "${original_tags_file}" || true

    local removed_count=0
    if [[ -s "${original_tags_file}" ]]; then
        while read -r original_tag; do
            # 跳过空行和新标签
            [[ -z "${original_tag}" ]] && continue
            [[ "${original_tag}" == "${new_image_tag}" ]] && continue

            # 提取基础服务名用于匹配
            local base_service_name
            base_service_name=$(get_base_service_name "${full_service_name}")

            # 删除属于当前服务的标签（使用基础服务名匹配）
            if [[ "${original_tag}" =~ /.*${base_service_name}: ]]; then
                # 静默执行，不输出 "Untagged: ..." 信息
                if docker rmi "${original_tag}" >/dev/null 2>&1; then
                    ((removed_count++))
                    log_debug "移除旧标签: ${original_tag}"
                fi
            fi
        done < "${original_tags_file}"
    fi
    log_debug "移除旧标签数量: ${removed_count}个"

    # 步骤6: 推送镜像（如果启用）
    local push_status="skipped"
    if [[ "${PUSH_IMAGES}" == "true" ]]; then
        # 使用全局缓存的登录状态，不再重复检查
        if [[ "${HARBOR_LOGGED_IN}" == "true" ]]; then
            if push_image_to_harbor "${new_image_tag}"; then
                push_status="success"
            else
                push_status="failed"
            fi
        else
            push_status="unauthorized"
            log_warn "未登录到Harbor，跳过推送"
        fi
    else
        push_status="disabled"
    fi

    # 记录处理结果
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 记录格式: 服务名|版本|仓库|完整标签|导入状态|推送状态|耗时(秒)
    echo "${full_service_name}|${version}|${harbor_registry}|${new_image_tag}|${load_status}|${push_status}|${duration}" >> "${TEMP_DIR}/processed_images.txt"

    # 显示推送状态
    case "${push_status}" in
        "success")
            log_success "推送成功"
            ;;
        "failed")
            log_error "镜像推送失败,请重新检查"
            ;;
        "disabled")
            log_info "推送已禁用"
            ;;
        "unauthorized")
            log_warn "未授权，跳过推送"
            ;;
        "skipped")
            log_info "跳过推送"
            ;;
    esac

    return 0
}

###############################################################################
#                             批量处理
###############################################################################

# 批量处理tar/tar.gz文件
batch_process_tar_files() {
    local success_count=0
    local fail_count=0

    # 查找 .tar 和 .tar.gz 文件
    local -a tar_files
    mapfile -t tar_files < <(find "${DEPLOY_DIR}" -maxdepth 1 \( -name "*.tar" -o -name "*.tar.gz" \) -type f | sort)

    if [[ ${#tar_files[@]} -eq 0 ]]; then
        log_error "在 ${DEPLOY_DIR} 中未找到 .tar 或 .tar.gz 文件"
        return 1
    fi

    log_section ">>>>> 发现 ${#tar_files[@]} 个镜像文件"

    # 显示文件列表
    local idx=1
    for tar_file in "${tar_files[@]}"; do
        local file_size
        file_size=$(du -h "${tar_file}" | cut -f1)
        log_info "$(printf "%02d" ${idx}). $(basename "${tar_file}") (${file_size})"
        ((idx++))
    done

    echo ""

    log_step "开始处理..."

    # 清空处理记录文件
    > "${TEMP_DIR}/imported_images.txt"
    > "${TEMP_DIR}/processed_images.txt"

    # 处理每个tar文件
    for tar_file in "${tar_files[@]}"; do
        echo ""
        echo -e "${DIM}${STEP_SEPARATOR}${NC}"

        # 解析文件名
        local file_info
        file_info=$(parse_tar_filename "${tar_file}")
        local service_name="${file_info%%|*}"
        local version="${file_info##*|}"

        if import_single_image "${tar_file}" "${service_name}" "${version}"; then
            ((success_count++))
        else
            ((fail_count++))
            log_error "处理失败: $(basename "${tar_file}")"
        fi
    done

    # 输出统计信息
    echo ""
    echo -e "${STEP_SEPARATOR}"

    if [[ ${fail_count} -eq 0 ]]; then
        #  所有镜像都处理成功,此时不打印信息,后续结果摘要会显示
        return 0
    else
        log_warn "批量处理完成: ${success_count}个成功, ${fail_count}个失败"
        return 1
    fi
}

###############################################################################
#                             结果展示
###############################################################################

# 显示处理结果
show_processing_results() {
    local summary_file="${TEMP_DIR}/processed_images.txt"

    # 临时禁用 set -e，避免命令失败导致脚本退出
    set +e

    if [[ ! -f "${summary_file}" ]] || [[ ! -s "${summary_file}" ]]; then
        log_warn "没有处理结果可显示"
        set -e  # 恢复 set -e
        return 0
    fi

    log_section "处理结果摘要"

    # 统计信息
    local total_count
    total_count=$(wc -l < "${summary_file}" 2>/dev/null || echo "0")

    # 统计状态
    local import_success_count=0
    local import_failed_count=0
    local push_success_count=0
    local push_failed_count=0
    local push_disabled_count=0
    local push_skipped_count=0
    local total_duration=0

    # 安全地读取文件
    while IFS='|' read -r service version registry full_tag import_status push_status duration 2>/dev/null; do
        # 跳过空行或格式不正确的行
        [[ -z "${service}" ]] && continue

        case "${import_status}" in
            "success") ((import_success_count++)) ;;
            "failed") ((import_failed_count++)) ;;
        esac

        case "${push_status}" in
            "success") ((push_success_count++)) ;;
            "failed") ((push_failed_count++)) ;;
            "disabled") ((push_disabled_count++)) ;;
            "skipped"|"unauthorized") ((push_skipped_count++)) ;;
        esac

        # 累加耗时
        total_duration=$((total_duration + duration))
    done < "${summary_file}"

    # 计算平均耗时
    local avg_duration=0
    if [[ ${total_count} -gt 0 ]]; then
        avg_duration=$((total_duration / total_count))
    fi

    # 显示表格
    echo -e "${BOLD}服务名称          版本            仓库                            导入状态    推送状态    耗时${NC}"
    echo -e "${DIM}────────────────── ─────────────── ──────────────────────────────── ────────── ────────── ─────${NC}"

    # 安全地排序和显示
    local sorted_content=""
    if command -v sort &>/dev/null; then
        sorted_content=$(sort "${summary_file}" 2>/dev/null || cat "${summary_file}")
    else
        sorted_content=$(cat "${summary_file}")
    fi

    while IFS='|' read -r service version registry full_tag import_status push_status duration; do
        # 跳过空行
        [[ -z "${service}" ]] && continue

        # 提取服务短名称（移除服务前缀）
        local short_service="${service#${SERVICE_PREFIX}}"

        # 提取仓库名称（HARBOR_DOMAIN后的部分）
        local repo_name="${registry#${HARBOR_DOMAIN}/}"

        # 格式化导入状态
        local import_status_formatted
        case "${import_status}" in
            "success")
                import_status_formatted="${GREEN}✓ 成功${NC}"
                ;;
            "failed")
                import_status_formatted="${RED}✗ 失败${NC}"
                ;;
            *)
                import_status_formatted="${DIM}? 未知${NC}"
                ;;
        esac

        # 格式化推送状态
        local push_status_formatted
        case "${push_status}" in
            "success")
                push_status_formatted="${GREEN}✓ 成功${NC}"
                ;;
            "failed")
                push_status_formatted="${RED}✗ 失败${NC}"
                ;;
            "disabled")
                push_status_formatted="${DIM}─ 禁用${NC}"
                ;;
            "skipped")
                push_status_formatted="${YELLOW}⚠ 跳过${NC}"
                ;;
            "unauthorized")
                push_status_formatted="${YELLOW}⚠ 未授权${NC}"
                ;;
            *)
                push_status_formatted="${DIM}? 未知${NC}"
                ;;
        esac

        # 格式化耗时
        local duration_formatted
        if [[ ${duration} -lt 10 ]]; then
            duration_formatted="${GREEN}${duration}s${NC}"
        elif [[ ${duration} -lt 30 ]]; then
            duration_formatted="${YELLOW}${duration}s${NC}"
        else
            duration_formatted="${RED}${duration}s${NC}"
        fi

        # 修改为使用%b格式，它会解释反斜杠转义序列
        printf "%-18s %-15s " "${short_service}" "${version}"
        printf "%-32s " "${repo_name}"
        printf "%-10b " "${import_status_formatted}"
        printf "%-10b " "${push_status_formatted}"
        printf "%b\n" "${duration_formatted}"
    done <<< "${sorted_content}"

    # 显示统计信息
    echo ""
    echo -e "${DIM}──────────────────────────────────────────────────────────────────────────────────────────${NC}"

    # 导入统计
    if [[ ${import_success_count} -eq ${total_count} ]]; then
        log_success "所有镜像导入成功 (${import_success_count}/${total_count})"
    elif [[ ${import_failed_count} -gt 0 ]]; then
        log_error "导入统计: 成功 ${import_success_count}, 失败 ${import_failed_count}"
    else
        log_info "导入统计: 成功 ${import_success_count}, 失败 ${import_failed_count}"
    fi

    # 推送统计
    if [[ "${PUSH_IMAGES}" == "true" ]]; then
        if [[ ${push_success_count} -eq ${total_count} ]]; then
            log_success "所有镜像推送成功 (${push_success_count}/${total_count})"
        elif [[ ${push_failed_count} -gt 0 ]]; then
            log_error "推送统计: 成功 ${push_success_count}, 失败 ${push_failed_count}, 跳过 ${push_skipped_count}"
        else
            log_info "推送统计: 成功 ${push_success_count}, 失败 ${push_failed_count}, 跳过 ${push_skipped_count}"
        fi
    else
        log_info "镜像推送已禁用"
    fi

    # 耗时统计
    log_info "总耗时: ${total_duration}秒, 平均: ${avg_duration}秒/个"

    # 恢复 set -e
    set -e
}

###############################################################################
#                             主函数
###############################################################################

main() {
    # 显示启动信息
    log_section ">>>>> Docker镜像导入工具（支持 .tar / .tar.gz）"
    log_info "工作目录: $(pwd)"
    log_info "Harbor域名: ${HARBOR_DOMAIN}"
    log_info "服务前缀: ${SERVICE_PREFIX}"
    log_info "推送镜像: ${PUSH_IMAGES}"
    log_debug "临时目录: ${TEMP_DIR}"

    # 环境检查
    check_prerequisites

    # 批量处理tar/tar.gz文件
    if ! batch_process_tar_files; then
        log_error "部分镜像导入失败，请检查错误信息"
        # 继续显示已成功导入的镜像
    fi

    # 显示结果
    show_processing_results

    # 清理建议
    if [[ "${PUSH_IMAGES}" == "true" ]] && [[ -f "${TEMP_DIR}/processed_images.txt" ]]; then
        local local_images_count
        local_images_count=$(docker images | grep -c "${HARBOR_DOMAIN}" || true)
        if [[ ${local_images_count} -gt 0 ]]; then
            echo ""
            log_info "本地仍保留 ${local_images_count} 个Harbor镜像"
            log_info "如需清理本地镜像，可执行: docker images | grep '${HARBOR_DOMAIN}' | awk '{print \$1\":\"\$2}' | xargs docker rmi"
        fi
    fi

    log_success "脚本执行完成"
}

###############################################################################
#                             脚本入口
###############################################################################
# 执行主函数
main "$@"
