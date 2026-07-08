#!/bin/bash

# OOM 处理脚本
# 当 JVM 发生 OutOfMemoryError 时会调用此脚本

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="/service/logs/oom_${TIMESTAMP}.log"
PID=$$

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OOM_HANDLER] $*" | tee -a "${LOG_FILE}"
}

log "=== OOM Handler Started ==="
log "PID: ${PID}"
log "Service: ${SERVICE_NAME:-unknown}"
log "Timestamp: ${TIMESTAMP}"

# 收集系统信息
log "=== System Information ==="
log "Memory usage:"
free -h | tee -a "${LOG_FILE}"

log "Disk usage:"
df -h | tee -a "${LOG_FILE}"

log "Process information:"
ps aux --sort=-%mem | head -20 | tee -a "${LOG_FILE}"

# 如果存在 Java 进程，收集更多信息
JAVA_PIDS=$(pgrep -f "java.*${SERVICE_NAME}")
if [[ -n "${JAVA_PIDS}" ]]; then
    log "=== Java Process Information ==="
    for java_pid in ${JAVA_PIDS}; do
        log "Java PID: ${java_pid}"
        
        # JVM 内存信息
        if command -v jstat >/dev/null 2>&1; then
            log "Heap memory stats:"
            jstat -gc "${java_pid}" | tee -a "${LOG_FILE}" || true
        fi
        
        # 线程信息
        if command -v jstack >/dev/null 2>&1; then
            log "Thread dump saved to: /service/dumps/threaddump_${java_pid}_${TIMESTAMP}.txt"
            jstack "${java_pid}" > "/service/dumps/threaddump_${java_pid}_${TIMESTAMP}.txt" 2>/dev/null || true
        fi
        
        # Native memory tracking
        if command -v jcmd >/dev/null 2>&1; then
            log "Native memory tracking:"
            jcmd "${java_pid}" VM.native_memory summary 2>/dev/null | tee -a "${LOG_FILE}" || true
        fi
    done
fi

# 记录容器/系统限制信息
log "=== Container/System Limits ==="
if [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
    log "Container memory limit: $(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 'unknown')"
fi

if [[ -f /sys/fs/cgroup/memory/memory.usage_in_bytes ]]; then
    log "Container memory usage: $(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo 'unknown')"
fi

# 清理旧的转储文件（保留最新的5个）
log "=== Cleanup Old Dumps ==="
find /service/dumps -name "*.hprof" -type f -printf '%T@ %p\n' | sort -n | head -n -5 | cut -d' ' -f2- | xargs -r rm -f
find /service/dumps -name "threaddump_*.txt" -type f -printf '%T@ %p\n' | sort -n | head -n -5 | cut -d' ' -f2- | xargs -r rm -f

# 发送告警（如果配置了告警端点）
if [[ -n "${ALERT_WEBHOOK_URL:-}" ]]; then
    log "Sending alert notification..."
    curl -X POST "${ALERT_WEBHOOK_URL}" \
         -H "Content-Type: application/json" \
         -d "{
             \"service\": \"${SERVICE_NAME:-unknown}\",
             \"event\": \"OutOfMemoryError\",
             \"timestamp\": \"$(date -Iseconds)\",
             \"hostname\": \"$(hostname)\",
             \"logFile\": \"${LOG_FILE}\"
         }" \
         --max-time 10 \
         --retry 2 2>/dev/null || log "Failed to send alert notification"
fi

log "=== OOM Handler Completed ==="
log "Log saved to: ${LOG_FILE}"

# 可选：发送信号给父进程进行优雅关闭
# kill -TERM $PPID 2>/dev/null || true

exit 0

