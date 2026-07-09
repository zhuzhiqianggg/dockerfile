# Dockerfile

标准化多架构 Docker 镜像构建脚本，推送至 SWR，源码托管在 GitHub。

## 镜像列表

| 镜像 | 目录 | 说明 |
|------|------|------|
| jdk | `jdk1.8/` | JDK 8 基础运行环境，内置 JMX Prometheus Exporter |
| jdk | `jdk17/` | JDK 17 基础运行环境，内置 JMX Prometheus Exporter |
| nginx | `nginx/` | Nginx 定制镜像 |
| openresty | `openresty/` | OpenResty 定制镜像 |
| tag-images | `tag-images/` | 标签镜像 |
| xxl-job-admin | `xxl-job-admin/` | XXL-JOB 管理端镜像 |

---

## Java 基础镜像

支持 **amd64** 和 **arm64** 双架构，基于 `eclipse-temurin`，内置 JMX Prometheus 监控。

### 目录结构

```
jdk1.8/               # JDK 8 版本
  Dockerfile
  entrypoint.sh        # 启动入口（内存/JMX/GC 配置）
  build.sh             # 构建 + 推送 + 测试
  jmx-config.yml       # JMX Exporter 配置
  oom_handler.sh       # OOM 自动诊断
  test-app/            # Spring Boot 测试应用

jdk17/                # JDK 17 版本（结构与 jdk1.8 一致）
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SERVICE_NAME` | `app` | 服务名称，对应 `/service/jar/{SERVICE_NAME}.jar` |
| `SERVICE_PORT` | `8080` | 服务端口 |
| `JAVA_OPTS_MEM` | (空) | JVM 内存参数，**优先级最高**，如 `-Xms4G -Xmx4G` |
| `JVM_HEAP` | (空) | 堆内存，如 `-Xms2G -Xmx2G`（优先级低于 `JAVA_OPTS_MEM`） |
| `JAVA_OPTS_JMX_EXPORTER` | (空) | 完整 JMX javaagent 参数（覆盖默认 agent） |
| `JVM_EXTRA_OPTS` | (空) | 附加 JVM 参数，追加在最后 |
| `JMX_EXPORTER_PORT` | `9999` | JMX Prometheus 端口 |
| `JMX_ENABLED` | `true` | JMX 总开关，设为 `false` 完全禁用 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `DEBUG` | `false` | 设为 `true` 打印调试日志 |

### 内存配置优先级

```
JAVA_OPTS_MEM  >  JVM_HEAP  >  默认 -Xms2G -Xmx2G
```

- **JAVA_OPTS_MEM**：完整覆盖，`JVM_EXTRA_OPTS` 不受影响
- **JVM_HEAP**：向下兼容旧配置，建议统一使用 `JAVA_OPTS_MEM`
- **默认值**：`-Xms2G -Xmx2G`（适用于 2.5G request / 3G limit 的容器）

### JVM 内置参数

entrypoint 自动添加以下参数（无需手动配置）：

```
# JVM 通用
-Djava.security.egd=file:/dev/urandom
-Duser.timezone=${TZ}
-Dfile.encoding=UTF-8
-Djava.awt.headless=true
-Djava.net.preferIPv4Stack=true

# GC（G1）
-XX:+UnlockExperimentalVMOptions
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m
-XX:G1NewSizePercent=15
-XX:G1MaxNewSizePercent=40
-XX:InitiatingHeapOccupancyPercent=45
-XX:+ParallelRefProcEnabled
-XX:+DisableExplicitGC

# 非堆
-XX:MetaspaceSize=128m
-XX:MaxMetaspaceSize=256m
-XX:ReservedCodeCacheSize=240m

# OOM 诊断
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/service/dumps
-XX:+ExitOnOutOfMemoryError
-XX:NativeMemoryTracking=summary

# GC 日志（JDK 8 用 PrintGCDetails，JDK 17 用 Xlog）
```

### K8s 部署建议

#### 推荐配置（2G 堆）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-service
  template:
    metadata:
      labels:
        app: my-service
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: my-service
        image: swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:8-jdk_JMX_SW_20260701
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 9999
          name: jmx
        env:
        - name: SERVICE_NAME
          value: "my-service"
        - name: SERVICE_PORT
          value: "8080"
        - name: TZ
          value: "Asia/Shanghai"
        # 不设 JAVA_OPTS_MEM → 使用默认 -Xms2G -Xmx2G
        # 如需覆盖:
        # - name: JAVA_OPTS_MEM
        #   value: "-Xms3G -Xmx3G"
        volumeMounts:
        - mountPath: /service/jar
          name: jar-volume
        - mountPath: /service/logs
          name: log-volume
        - mountPath: /service/dumps
          name: dump-volume
        resources:
          requests:
            memory: "2.5Gi"
            cpu: "500m"
          limits:
            memory: "3Gi"
            cpu: "2"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/bash
              - -c
              - "kill -15 1; sleep 30"
      volumes:
      - name: jar-volume
        persistentVolumeClaim:
          claimName: my-service-pvc
      - name: log-volume
        persistentVolumeClaim:
          claimName: my-service-pvc
      - name: dump-volume
        persistentVolumeClaim:
          claimName: my-service-pvc
```

#### 内存配比参考

| 期望堆 | `JAVA_OPTS_MEM` | request | limit | 总 RSS(约) |
|--------|-----------------|---------|-------|-----------|
| **2G** | 不设置(默认) | **2.5Gi** | **3Gi** | 2.5~2.8G |
| 3G | `-Xms3G -Xmx3G` | 3.5Gi | 4Gi | 3.5~3.8G |
| 4G | `-Xms4G -Xmx4G` | 4.5Gi | 6Gi | 4.8~5.5G |

> 非堆开销（Metaspace 256M + CodeCache 240M + 线程栈 + Native）约 **500-800M**，request 建议比 heap 大 0.5~1G。

#### 探针配置

```yaml
livenessProbe:
  initialDelaySeconds: 60   # 给 JVM + Spring Boot 启动时间
  periodSeconds: 30
  timeoutSeconds: 10

readinessProbe:
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
```

#### PreStop 优雅关闭

```yaml
lifecycle:
  preStop:
    exec:
      command:
      - /bin/bash
      - -c
      - "kill -15 1; sleep 30"
```

- `kill -15 1` → PID 1（Java 进程）收到 SIGTERM → Spring Boot shutdown hook
- `sleep 30` → 等待 Spring Boot 完成关闭（默认 30s 超时）
- `terminationGracePeriodSeconds: 60` → K8s 总超时（需 > preStop sleep + 关闭时间）

### 构建

```bash
# JDK 8
cd jdk1.8
./build.sh   # 默认构建 + 测试 + 推送 SWR

# 自定义 tag
./build.sh -t swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:8-jdk_JMX_20260701

# JDK 17
cd jdk17
./build.sh
```

## OOM 诊断

OOM 时自动生成以下文件（路径见 `oom_handler.sh`）：

| 产物 | 路径 | 说明 |
|------|------|------|
| 堆快照 | `/service/dumps/*.hprof` | 堆内存完整快照 |
| 线程快照 | `/service/dumps/threaddump_*.txt` | 所有线程堆栈 |
| Crash 日志 | `/service/logs/hs_err_pid*.log` | JVM 崩溃诊断 |
| OOM 日志 | `/service/logs/oom_*.log` | 系统资源记录 |
| GC 日志 | `/service/logs/gc.log` | GC 历史记录 |
