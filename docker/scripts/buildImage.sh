#!/bin/bash

PROVINCE="$1"
SERVICE_NAME="$2"

VERSION="$3"

WORKSPACE="$4"

# jar包所在目录
JAR_DIR="${WORKSPACE}/app/${SERVICE_NAME}"

# jar文件
JAR_FILE="${SERVICE_NAME}.jar"

OUT_DIRECTORY="."

# 设置Dockerfile 路径
DOCKERFILE_PATH="${WORKSPACE}/dockerfile/${SERVICE_NAME}"

IMAGE_NAME="${SERVICE_NAME}"

if [ "${VERSION}" != "" ]; then
		IMAGE_TAG="${VERSION}"
else
		IMAGE_TAG="latest"
fi


# 镜像信息: /命名空间/仓库名称:镜像版本号
IMAGE_PATH="/virtual-station-rebuild-${PROVINCE}/${IMAGE_NAME}:${IMAGE_TAG}"

# 镜像仓库私服信息
HARBOR_IP="core.harbor.domain"
HARBOR_PORT=32388


# 尝试连接域名和端口
curl -IsS --connect-timeout 5 ${HARBOR_IP}:${HARBOR_PORT} >/dev/null

# 检查连接结果
if [ $? -eq 0 ]; then
  echo "1. 连接 ${HARBOR_IP}:${HARBOR_PORT} 成功！！！！"
else
  echo "1. 连接 ${HARBOR_IP}:${HARBOR_PORT} 失败,请根据docker配置Harbor仓库"
  exit 1
fi

# 开始登录harbor仓库
if docker login ${HARBOR_IP}:${HARBOR_PORT} -u admin -p Harbor@2024; then
  echo "2. harbor 登录成功"
else
  echo "2. harbor 登录失败"
  exit 1
fi

# 将对应jar包编译成docker镜像
echo "docker build -f ${DOCKERFILE_PATH} --build-arg OUT_DIRECTORY=${OUT_DIRECTORY} --build-arg JAR_FILE=${OUT_DIRECTORY}/${JAR_FILE} -t ${HARBOR_IP}:${HARBOR_PORT}${IMAGE_PATH} ${JAR_DIR}"
if docker build -f ${DOCKERFILE_PATH} --build-arg OUT_DIRECTORY=${OUT_DIRECTORY} --build-arg JAR_FILE=${OUT_DIRECTORY}/${JAR_FILE} -t ${HARBOR_IP}:${HARBOR_PORT}${IMAGE_PATH} ${JAR_DIR}; then
  echo "3. 镜像 ${SERVICE_NAME} 构建成功"
else
  echo "3. 镜像 ${SERVICE_NAME} 构建失败"
  exit 1
fi

# 推送镜像到Harbor仓库
if docker push ${HARBOR_IP}:${HARBOR_PORT}${IMAGE_PATH}; then
  echo "4. 镜像 ${SERVICE_NAME} 已推送到Harbor仓库"
  echo ">>>>> 本次操作结束(${SERVICE_NAME}) <<<<<"
  echo ""
else
  echo "4. 镜像 ${SERVICE_NAME} 推送到Harbor仓库失败"
  exit 1
fi


# 查看镜像
# docker images

# 查看容器
# docker ps

# 导出单个镜像
# docker save core.harbor.domain:32388/virtual-station-jiangxi/virtual-station-gateway:latest > virtual-station-gateway.tar

# 导入镜像
# docker load < virtual-station-gateway.tar

