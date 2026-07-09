#!/bin/bash
set -euo pipefail

# =============================================================================
#  Java Base Image Entrypoint
#  Usage: docker run -e SERVICE_NAME=myapp -e SERVICE_PORT=8080 \
#         -e JAVA_OPTS_MEM='-Xms4G -Xmx4G' \
#         -e JAVA_OPTS_JMX_EXPORTER='-javaagent:/service/jmx_exporter/jmx_prometheus_javaagent.jar=9999:/service/jmx_exporter/config.yml' \
#         -e JMX_PORT=9100 ...
#
#  内存说明:
#    JVM 进程总内存 = Heap + Metaspace + CodeCache + ThreadStack + DirectBuffer + Native
#    当 -Xmx2g 时, 总 RSS ≈ 2.5~2.8G 是正常范围.
#    默认 -Xms2G -Xmx2G (适用 2.5G/3G request/limit 的容器).
#    通过 JAVA_OPTS_MEM 环境变量可覆盖, 优先级最高.
# =============================================================================

log()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [entrypoint] $*" >&2; }
debug()  { [[ "${DEBUG}" != "true" ]] || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [entrypoint] DEBUG: $*" >&2; }
error()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [entrypoint] ERROR: $*" >&2; }

validate() {
    local jar="/service/jar/${SERVICE_NAME}.jar"
    [[ -f "$jar" ]] || { error "JAR not found: $jar (mount to /service/jar/${SERVICE_NAME}.jar)"; exit 1; }
    debug "Validation passed"
}

build_default_jvm_opts() {
    local jmx_enabled="${1:-true}"
    local tz="${TZ:-Asia/Shanghai}"
    local jmx_port="${JMX_EXPORTER_PORT:-9999}"
    local -a opts=(
        "-Djava.security.egd=file:/dev/urandom"
        "-Duser.timezone=${tz}"
        "-Dfile.encoding=UTF-8"
        "-Djava.awt.headless=true"
        "-Djava.net.preferIPv4Stack=true"
        "-Djava.io.tmpdir=/tmp"
        "-Dsun.net.inetaddr.ttl=60"

        "-XX:+UnlockExperimentalVMOptions"
        "-XX:+UseG1GC"
        "-XX:MaxGCPauseMillis=200"
        "-XX:G1HeapRegionSize=16m"
        "-XX:G1NewSizePercent=15"
        "-XX:G1MaxNewSizePercent=40"
        "-XX:InitiatingHeapOccupancyPercent=45"
        "-XX:+ParallelRefProcEnabled"
        "-XX:+DisableExplicitGC"

        "-XX:MetaspaceSize=128m"
        "-XX:MaxMetaspaceSize=256m"
        "-XX:ReservedCodeCacheSize=240m"

        "-XX:+UseStringDeduplication"
        "-XX:+OptimizeStringConcat"
        "-XX:+UseCompressedOops"
        "-XX:+UseCompressedClassPointers"

        "-XX:+HeapDumpOnOutOfMemoryError"
        "-XX:HeapDumpPath=/service/dumps"
        "-XX:ErrorFile=/service/logs/hs_err_pid%p.log"
        "-XX:OnOutOfMemoryError=/service/oom_handler.sh"
        "-XX:+ExitOnOutOfMemoryError"
        "-XX:NativeMemoryTracking=summary"

        "-Dspring.main.register-shutdown-hook=true"
        "-Dspring.jmx.enabled=true"
    )

    # JMX agent (默认启用，JMX_ENABLED=false 关闭，JAVA_OPTS_JMX_EXPORTER 覆盖)
    if [[ "${jmx_enabled}" != "false" ]] && [[ -z "${JAVA_OPTS_JMX_EXPORTER:-}" ]]; then
        opts+=("-javaagent:/service/jmx_exporter/jmx_prometheus_javaagent.jar=${jmx_port}:/service/jmx_exporter/config.yml")
    fi

    local ver
    ver=$(java -version 2>&1) || true
    local first_line
    first_line=$(head -1 <<< "${ver}")
    debug "Java version: ${first_line}"

    if grep -q "1\.8" <<< "${first_line}"; then
        opts+=(
            "-Xloggc:/service/logs/gc.log"
            "-XX:+PrintGCDetails"
            "-XX:+PrintGCDateStamps"
            "-XX:+PrintGCApplicationStoppedTime"
            "-XX:+UseGCLogFileRotation"
            "-XX:NumberOfGCLogFiles=5"
            "-XX:GCLogFileSize=10M"
        )
    else
        opts+=("-Xlog:gc*,gc+heap=debug:file=/service/logs/gc.log:time,uptime:filecount=5,filesize=10M")
    fi

    printf "%s\n" "${opts[@]}"
}

main() {
    SERVICE_NAME="${SERVICE_NAME:-app}"
    SERVICE_PORT="${SERVICE_PORT:-8080}"
    JAVA_OPTS_MEM="${JAVA_OPTS_MEM:-}"
    JAVA_OPTS_JMX_EXPORTER="${JAVA_OPTS_JMX_EXPORTER:-}"
    JVM_HEAP="${JVM_HEAP:-}"
    JVM_EXTRA_OPTS="${JVM_EXTRA_OPTS:-}"
    JMX_EXPORTER_PORT="${JMX_EXPORTER_PORT:-9999}"
    JMX_ENABLED="${JMX_ENABLED:-true}"
    DEBUG="${DEBUG:-false}"
    TZ="${TZ:-Asia/Shanghai}"

    log "Starting ${SERVICE_NAME} on port ${SERVICE_PORT}"
    validate
    mkdir -p /service/logs /service/dumps

    local -a cmd=("java" "-Dlabel=${SERVICE_NAME}")

    # JAVA_OPTS_MEM (兼容现有 K8s 配置，优先级最高)
    if [[ -n "${JAVA_OPTS_MEM}" ]]; then
        debug "JAVA_OPTS_MEM: ${JAVA_OPTS_MEM}"
        read -ra mem_opts <<< "${JAVA_OPTS_MEM}"
        cmd+=("${mem_opts[@]}")
    elif [[ -n "${JVM_HEAP}" ]]; then
        debug "JVM_HEAP: ${JVM_HEAP}"
        read -ra heap <<< "${JVM_HEAP}"
        cmd+=("${heap[@]}")
    else
        debug "Using default -Xms2G -Xmx2G"
        cmd+=("-Xms2G" "-Xmx2G")
    fi

    local jmx_enabled
    jmx_enabled=$(echo "${JMX_ENABLED}" | tr '[:upper:]' '[:lower:]')

    # JAVA_OPTS_JMX_EXPORTER — 覆盖默认 JMX agent (仅在 JMX 启用时生效)
    if [[ "${jmx_enabled}" != "false" ]] && [[ -n "${JAVA_OPTS_JMX_EXPORTER}" ]]; then
        debug "JAVA_OPTS_JMX_EXPORTER: ${JAVA_OPTS_JMX_EXPORTER}"
        read -ra jmx_opts <<< "${JAVA_OPTS_JMX_EXPORTER}"
        cmd+=("${jmx_opts[@]}")
    fi

    while IFS= read -r opt; do
        [[ -n "$opt" ]] && cmd+=("$opt")
    done < <(build_default_jvm_opts "${jmx_enabled}")

    if [[ -n "${JVM_EXTRA_OPTS}" ]]; then
        debug "JVM_EXTRA_OPTS: ${JVM_EXTRA_OPTS}"
        read -ra extra <<< "${JVM_EXTRA_OPTS}"
        cmd+=("${extra[@]}")
    fi

    cmd+=("-jar" "/service/jar/${SERVICE_NAME}.jar" "--server.port=${SERVICE_PORT}")

    debug "Final command: ${cmd[*]}"
    exec "${cmd[@]}"
}

main "$@"
