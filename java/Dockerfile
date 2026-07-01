ARG JDK_VERSION=8-jdk
FROM eclipse-temurin:${JDK_VERSION}

SHELL ["/bin/bash", "-c"]

LABEL maintainer="DevOps Team <devops@example.com>" \
      version="3.1" \
      description="Java base runtime with JMX monitoring, multi-arch, configurable JDK & JMX versions"

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG JMX_VERSION=1.6.0

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        locales \
        curl \
        ca-certificates \
        iputils-ping \
        dnsutils \
        netcat-openbsd \
        procps && \
    sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen zh_CN.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /service/{jmx_exporter,jar,logs,dumps} /tmp/dumps

RUN curl -fsSL "https://github.com/krallin/tini/releases/download/v0.19.0/tini-${TARGETARCH}" -o /usr/bin/tini && \
    chmod 755 /usr/bin/tini

RUN curl -fsSL "https://github.com/prometheus/jmx_exporter/releases/download/v${JMX_VERSION}/jmx_prometheus_javaagent-${JMX_VERSION}.jar" \
         -o /service/jmx_exporter/jmx_prometheus_javaagent.jar

COPY ./jmx-config.yml /service/jmx_exporter/config.yml
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 oom_handler.sh /service/oom_handler.sh

ENV SERVICE_NAME="" \
    SERVICE_PORT=8080 \
    JAVA_OPTS_MEM="" \
    JAVA_OPTS_JMX_EXPORTER="" \
    JVM_HEAP="" \
    JVM_EXTRA_OPTS="" \
    JMX_EXPORTER_PORT=9999 \
    DEBUG="false"

RUN chmod 775 /service/logs /service/dumps /tmp/dumps

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /bin/bash -c 'curl -sf --connect-timeout 5 --max-time 10 http://localhost:${SERVICE_PORT}/actuator/health 2>/dev/null || nc -z localhost ${SERVICE_PORT} || exit 1'

WORKDIR /service
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
