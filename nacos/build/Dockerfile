FROM alpine:latest
LABEL maintainer="Sawyerlsy <sawyerlsy@126.com>"

# install jdk
RUN apk add --no-cache openjdk8-jre-base curl iputils ncurses vim libcurl bash

# set environment
ENV MODE="cluster" \
    PREFER_HOST_MODE="ip"\
    BASE_DIR="/home/nacos" \
    CLASSPATH=".:/home/nacos/conf:$CLASSPATH" \
    CLUSTER_CONF="/home/nacos/conf/cluster.conf" \
    FUNCTION_MODE="all" \
    JAVA_HOME="/usr/lib/jvm/java-1.8-openjdk" \
    NACOS_USER="nacos" \
    JAVA="/usr/lib/jvm/java-1.8-openjdk/bin/java" \
    JVM_XMS="1g" \
    JVM_XMX="1g" \
    JVM_XMN="512m" \
    JVM_MS="128m" \
    JVM_MMS="320m" \
    NACOS_DEBUG="n" \
    TOMCAT_ACCESSLOG_ENABLED="false" \
    TIME_ZONE="Asia/Shanghai"

ARG NACOS_VERSION=v2.2.3-local
ARG HOT_FIX_FLAG=""

WORKDIR $BASE_DIR

# run all operation
RUN set -x \
    && curl -SL --retry 3 --retry-delay 10 https://github.com/Sawyerlsy/nacos/releases/download/${NACOS_VERSION}${HOT_FIX_FLAG}/nacos-server-${NACOS_VERSION}.tar.gz -o /home/nacos-server.tar.gz \
    && tar -xzvf /home/nacos-server.tar.gz -C /home \
    && rm -rf /home/nacos-server.tar.gz /home/nacos/bin/* /home/nacos/conf/*.properties /home/nacos/conf/*.example /home/nacos/conf/nacos-mysql.sql \
    && ln -snf /usr/share/zoneinfo/$TIME_ZONE /etc/localtime && echo $TIME_ZONE > /etc/timezone

ADD bin/docker-startup.sh bin/docker-startup.sh
ADD conf/application.properties conf/application.properties

# 设置启动日志目录
RUN mkdir -p logs \
	&& touch logs/start.out \
	&& ln -sf /dev/stdout logs/start.out \
	&& ln -sf /dev/stderr logs/start.out \
    && sed -i 's/\r$//' bin/docker-startup.sh \
    && chmod +x bin/docker-startup.sh

EXPOSE 8848
ENTRYPOINT ["sh","bin/docker-startup.sh"]
