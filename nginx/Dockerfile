# =============================================================================
# Nginx 多架构编译镜像 (多阶段构建)
# 版本: 2.0 - 支持 linux/amd64, linux/arm64
# =============================================================================

FROM ubuntu:24.04 AS builder

ARG NGINX_VERSION=1.30.3
ARG DEBIAN_FRONTEND=noninteractive

ENV NGINX_ROOT=/data/nginx

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        build-essential \
        libpcre3-dev \
        zlib1g-dev \
        libssl-dev \
        wget \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN wget -q https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar zxf nginx-${NGINX_VERSION}.tar.gz && \
    cd nginx-${NGINX_VERSION} && \
    ./configure \
        --prefix=${NGINX_ROOT} \
        --sbin-path=${NGINX_ROOT}/sbin/nginx \
        --modules-path=${NGINX_ROOT}/modules \
        --conf-path=${NGINX_ROOT}/conf/nginx.conf \
        --error-log-path=${NGINX_ROOT}/logs/error.log \
        --http-log-path=${NGINX_ROOT}/logs/access.log \
        --pid-path=${NGINX_ROOT}/run/nginx.pid \
        --lock-path=${NGINX_ROOT}/run/nginx.lock \
        --http-client-body-temp-path=${NGINX_ROOT}/temp/client_body \
        --http-proxy-temp-path=${NGINX_ROOT}/temp/proxy \
        --http-fastcgi-temp-path=${NGINX_ROOT}/temp/fastcgi \
        --http-uwsgi-temp-path=${NGINX_ROOT}/temp/uwsgi \
        --http-scgi-temp-path=${NGINX_ROOT}/temp/scgi \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-http_sub_module \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_gunzip_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-pcre-jit \
        --with-threads \
        --with-file-aio && \
    make -j$(nproc) && \
    make install && \
    strip ${NGINX_ROOT}/sbin/nginx && \
    rm -rf /tmp/*

FROM ubuntu:24.04

ARG NGINX_VERSION=1.30.3
ARG DEBIAN_FRONTEND=noninteractive

LABEL maintainer="DevOps Team <devops@example.com>" \
      version="2.0" \
      description="Nginx ${NGINX_VERSION} multi-arch image"

ENV NGINX_ROOT=/data/nginx \
    TZ=Asia/Shanghai

COPY --from=builder ${NGINX_ROOT} ${NGINX_ROOT}

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libpcre3 \
        zlib1g \
        libssl3 \
        tzdata \
        curl && \
    ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY nginx.conf ${NGINX_ROOT}/conf/nginx.conf

RUN mkdir -p ${NGINX_ROOT}/temp ${NGINX_ROOT}/logs ${NGINX_ROOT}/run ${NGINX_ROOT}/html && \
    useradd -r -s /sbin/nologin nginx && \
    chown -R nginx:nginx ${NGINX_ROOT}

ENV PATH=${NGINX_ROOT}/sbin:$PATH

HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -4 -f http://localhost/healthcheck || exit 1

EXPOSE 80 443

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
