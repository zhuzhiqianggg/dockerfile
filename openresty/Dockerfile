# =============================================================================
# OpenResty 多阶段构建 (多架构支持)
# 版本: v3.0
# =============================================================================

# ---- 构建阶段 ----
FROM alpine:3.21 AS builder

ENV OPENRESTY_VERSION=1.31.1.1 \
    PCRE_VERSION=8.45 \
    OPENSSL_VERSION=3.4.6 \
    LUA_VERSION=5.1.5 \
    LUAROCKS_VERSION=3.13.0 \
    MAKEFLAGS="-j$(nproc)"

WORKDIR /tmp

RUN apk update && \
    apk add --no-cache --virtual .build-deps \
        build-base \
        cmake \
        make \
        gcc \
        g++ \
        libc-dev \
        linux-headers \
        curl-dev \
        gd-dev \
        geoip-dev \
        libxslt-dev \
        pcre-dev \
        zlib-dev \
        readline-dev \
        ncurses-dev \
        perl-dev \
        wget \
        curl \
        tar \
        gzip \
        && \
    rm -rf /var/cache/apk/*

# ---- Lua ----
RUN wget -q https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz && \
    tar zxf lua-${LUA_VERSION}.tar.gz && \
    cd lua-${LUA_VERSION} && \
    make linux \
        MYCFLAGS="-DLUA_USE_LINUX -DLUA_COMPAT_ALL -fPIC" \
        MYLIBS="-Wl,-E -ldl -lreadline -lncurses" \
        INSTALL_TOP=/data/lua && \
    make install INSTALL_TOP=/data/lua

# ---- LuaRocks ----
RUN wget -q https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz && \
    tar zxf luarocks-${LUAROCKS_VERSION}.tar.gz && \
    cd luarocks-${LUAROCKS_VERSION} && \
    ./configure \
        --prefix=/data/luarocks \
        --with-lua=/data/lua \
        --with-lua-include=/data/lua/include \
        --with-lua-lib=/data/lua/lib && \
    make build && \
    make install

# ---- Lua 模块 ----
ENV PATH="/data/luarocks/bin:$PATH"
RUN luarocks install --tree=/data/lua/modules lua-cjson && \
    luarocks install --tree=/data/lua/modules lua-resty-http && \
    luarocks install --tree=/data/lua/modules lua-resty-redis && \
    luarocks install --tree=/data/lua/modules lua-resty-mysql

# ---- OpenResty + 依赖 ----
RUN wget -q https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz && \
    wget -q https://sourceforge.net/projects/pcre/files/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.gz/download -O pcre-${PCRE_VERSION}.tar.gz && \
    wget -q https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz && \
    git clone --depth=1 --recursive https://github.com/google/ngx_brotli.git /tmp/ngx_brotli

RUN tar zxf openresty-${OPENRESTY_VERSION}.tar.gz && \
    tar zxf pcre-${PCRE_VERSION}.tar.gz && \
    tar zxf openssl-${OPENSSL_VERSION}.tar.gz

RUN cd openresty-${OPENRESTY_VERSION} && \
    ./configure \
        --prefix=/data/openresty \
        --sbin-path=/data/openresty/nginx/sbin/nginx \
        --modules-path=/data/openresty/nginx/modules \
        --conf-path=/data/openresty/nginx/conf/nginx.conf \
        --error-log-path=/data/openresty/nginx/logs/error.log \
        --http-log-path=/data/openresty/nginx/logs/access.log \
        --pid-path=/data/openresty/nginx/logs/nginx.pid \
        --lock-path=/data/openresty/nginx/logs/nginx.lock \
        --http-client-body-temp-path=/data/openresty/nginx/temp/client_body_temp \
        --http-proxy-temp-path=/data/openresty/nginx/temp/proxy_temp \
        --http-fastcgi-temp-path=/data/openresty/nginx/temp/fastcgi_temp \
        --http-uwsgi-temp-path=/data/openresty/nginx/temp/uwsgi_temp \
        --http-scgi-temp-path=/data/openresty/nginx/temp/scgi_temp \
        --with-pcre=/tmp/pcre-${PCRE_VERSION} \
        --with-pcre-jit \
        --with-openssl=/tmp/openssl-${OPENSSL_VERSION} \
        --with-luajit \
        --with-file-aio \
        --with-threads \
        --with-http_v2_module \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_addition_module \
        --with-http_sub_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_auth_request_module \
        --with-http_random_index_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_stub_status_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --add-module=/tmp/ngx_brotli && \
    make -j$(nproc) && \
    make install && \
    strip /data/openresty/nginx/sbin/nginx

# ---- 运行阶段 ----
FROM alpine:3.21

LABEL maintainer="DevOps Team <devops@example.com>" \
      version="3.0" \
      description="OpenResty ${OPENRESTY_VERSION} with Lua ecosystem (multi-arch)"

ENV PATH="/data/openresty/nginx/sbin:/data/openresty/bin:/data/lua/bin:/data/luarocks/bin:$PATH" \
    OPENRESTY_HOME=/data/openresty \
    LUA_PATH="/data/lua/modules/share/lua/5.1/?.lua;/data/lua/modules/share/lua/5.1/?/init.lua;;" \
    LUA_CPATH="/data/lua/modules/lib/lua/5.1/?.so;;" \
    TZ=Asia/Shanghai

RUN apk add --no-cache \
        ca-certificates \
        pcre \
        openssl \
        zlib \
        curl \
        libstdc++ \
        libgcc \
        tzdata \
        bash \
        procps && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    rm -rf /var/cache/apk/* /tmp/*

COPY --from=builder /data/openresty /data/openresty
COPY --from=builder /data/lua /data/lua
COPY --from=builder /data/luarocks /data/luarocks

RUN addgroup -g 101 -S nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx && \
    mkdir -p /data/openresty/nginx/conf/conf.d && \
    chown -R nginx:nginx /data/openresty/nginx && \
    ln -sf /data/openresty/nginx/sbin/nginx /usr/local/bin/openresty

COPY nginx.conf /data/openresty/nginx/conf/nginx.conf

WORKDIR /data/openresty/nginx

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/healthcheck || exit 1

STOPSIGNAL SIGQUIT

CMD ["openresty", "-g", "daemon off;", "-p", "/data/openresty/nginx/"]
