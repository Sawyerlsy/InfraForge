# 第一阶段：编译环境
FROM debian:bookworm-slim AS builder

# 时区配置
ENV TZ=Asia/Shanghai
ENV NGINX_VERSION=1.28.0
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装编译依赖
RUN apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends \
        wget unzip patch make gcc libpcre3-dev zlib1g-dev libssl-dev \
        libxml2-dev libxslt-dev libgd-dev geoip-bin libgeoip-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 下载源码并清理
RUN wget -O nginx.tar.gz --no-check-certificate https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
    && wget -O module.zip --no-check-certificate https://github.com/yaoweibin/nginx_upstream_check_module/archive/master.zip \
    && tar zxvf nginx.tar.gz \
    && unzip module.zip -d /tmp/ \
    && rm nginx.tar.gz module.zip

# 创建必要目录结构（匹配配置参数）
RUN mkdir -p /var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp} && \
    mkdir -p /usr/lib/nginx/modules

# 创建系统用户（与运行时一致）
RUN groupadd --system --gid 101 nginx \
 && useradd --system --gid nginx --no-create-home --home /nonexistent --shell /bin/false --uid 101 nginx

# 应用补丁并编译
WORKDIR /nginx-${NGINX_VERSION}
RUN patch -p1 < /tmp/nginx_upstream_check_module-master/check_1.20.1+.patch

RUN ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --add-module=/tmp/nginx_upstream_check_module-master \
        --with-cc-opt='-g -O2 -ffile-prefix-map=/home/builder/debuild/nginx-1.28.0/debian/debuild-base/nginx-1.28.0=. -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
        --with-ld-opt='-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
        && make -j$(nproc) \
        && make install \
        && chown -R nginx:nginx /var/cache/nginx \
        && rm -rf /nginx-${NGINX_VERSION} /tmp/*

# 第二阶段：最终镜像
FROM debian:bookworm-slim

# 安装最小运行时依赖
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates libpcre3 zlib1g libssl3 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 101 nginx \
 && useradd --system --gid nginx --no-create-home --home /nonexistent --shell /bin/false --uid 101 nginx \
 && mkdir -p /var/log/nginx /var/cache/nginx /docker-entrypoint.d \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

# 从编译阶段复制必要文件
COPY --from=builder --chown=nginx:nginx /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder --chown=nginx:nginx /etc/nginx /etc/nginx
COPY --from=builder --chown=nginx:nginx /usr/lib/nginx /usr/lib/nginx
COPY --from=builder --chown=nginx:nginx /var/cache/nginx /var/cache/nginx
COPY --from=builder --chown=nginx:nginx /usr/lib/nginx/modules /usr/lib/nginx/modules

# Entrypoint 配置
COPY docker-entrypoint.sh /
COPY *.sh /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.sh /docker-entrypoint.d/*.sh \
    && sed -i 's/\r$//' /docker-entrypoint.sh /docker-entrypoint.d/*.sh

# 暴露端口和启动命令
EXPOSE 80
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
