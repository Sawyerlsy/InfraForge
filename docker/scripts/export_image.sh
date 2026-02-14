#!/bin/bash
set -euo pipefail

# 默认配置
DEFAULT_PROJECT="virtual-station-rebuild-hebei"
DEFAULT_VERSION="1301.2508.2"
DEFAULT_REGISTRY="core.harbor.domain:32388"
DEFAULT_SERVICES=("gateway" "param" "charge" "list" "trade" "psam" "upload" "log")

show_help() {
    cat << EOF
容器镜像导出工具
用法: $0 [选项]
示例:
  $0 -p virtual-station-rebuild-hebei -v 1301.2508.2
  $0 -p virtual-station-rebuild -v 1301.2508.2 -s "gateway,param"

选项:
  -p  项目/地域名称 (默认: $DEFAULT_PROJECT)
  -v  镜像版本标签 (默认: $DEFAULT_VERSION)
  -r  镜像仓库地址 (默认: $DEFAULT_REGISTRY)
  -s  要导出的服务列表，逗号分隔 (默认: 全部服务)
  -h  显示此帮助信息

默认导出目录: 版本号目录 (如: $DEFAULT_VERSION/)
EOF
}

# 解析命令行参数
PROJECT=""
VERSION=""
REGISTRY=""
USER_SERVICES=""

while getopts "p:v:r:s:h" opt; do
    case $opt in
        p) PROJECT="$OPTARG";;
        v) VERSION="$OPTARG";;
        r) REGISTRY="$OPTARG";;
        s) USER_SERVICES="$OPTARG";;
        h) show_help; exit 0;;
        ?) show_help; exit 1;;
    esac
done

# 应用默认值
PROJECT="${PROJECT:-$DEFAULT_PROJECT}"
VERSION="${VERSION:-$DEFAULT_VERSION}"
REGISTRY="${REGISTRY:-$DEFAULT_REGISTRY}"

# 处理服务列表
if [ -n "$USER_SERVICES" ]; then
    IFS=',' read -ra SERVICES <<< "$USER_SERVICES"
else
    SERVICES=("${DEFAULT_SERVICES[@]}")
fi

OUTPUT_DIR="$VERSION"

echo "=========================================="
echo "开始导出镜像"
echo "项目名称:    $PROJECT"
echo "镜像版本:    $VERSION"
echo "仓库地址:    $REGISTRY"
echo "输出目录:    $OUTPUT_DIR"
echo "导出服务:    ${SERVICES[*]}"
echo "=========================================="

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR" || exit

# 导出镜像
FAILURES=0
for SERVICE in "${SERVICES[@]}"; do
    IMAGE_NAME="$REGISTRY/$PROJECT/virtual-station-$SERVICE:$VERSION"
    OUTPUT_FILE="${SERVICE}-${VERSION}.tar"

    echo "正在导出: $SERVICE"
    echo "镜像: $IMAGE_NAME"

    if docker save "$IMAGE_NAME" > "$OUTPUT_FILE" 2>/dev/null; then
        FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
        echo "✓ 导出成功: $OUTPUT_FILE ($FILE_SIZE)"
    else
        echo "✗ 导出失败: $SERVICE"
        rm -f "$OUTPUT_FILE"
        ((FAILURES++))
    fi
    echo "------------------------------------------"
done

# 显示结果
echo "导出完成"
echo "成功: $((${#SERVICES[@]} - FAILURES)), 失败: $FAILURES, 总计: ${#SERVICES[@]}"

if [ $FAILURES -eq 0 ]; then
    echo "✓ 所有镜像已导出到: $(pwd)"
else
    echo "⚠ 部分镜像导出失败"
    exit 1
fi
