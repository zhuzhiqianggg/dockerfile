# Java Docker Base Image

Java 基础运行环境镜像，支持 **amd64** 和 **arm64** 双架构。

基于 `eclipse-temurin:8-jdk`，内置 JMX Prometheus 监控，不包含 SkyWalking。

依赖全部在线下载，git 仅管理源码，克隆后可直接构建。

## ARM (arm64) 支持

镜像原生支持 **amd64** 和 **arm64**，无需修改代码。

详见 [`MULTI_ARCH.md`](MULTI_ARCH.md) — 包含原理详解、buildx 配置、CI/CD 示例和常见问题。

| 场景 | 说明 |
|---|---|
| ARM 机器上直接构建 | `docker build -t img .` → 自动拉取 arm64 版本 `eclipse-temurin:8-jdk`，`TARGETARCH=arm64` 自动下载 tini-arm64 |
| x86 上构建 arm64 镜像 | `docker build --platform linux/arm64 -t img .` |
| 构建双架构并推送到仓库 | `docker buildx build --platform linux/amd64,linux/arm64 -t your-registry/img:tag --push .` |

## 构建

```bash
# 默认 amd64（最新 JDK 8 + JMX Exporter 1.6.0）
docker build -t java-base:latest .

# 指定 arm64
docker build --platform linux/arm64 -t java-base:latest .

# 使用 build.sh 构建并测试
./build.sh
./build.sh -t swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630
./build.sh -t myimg:latest -n myapp -p 9000
./build.sh --platform linux/arm64 -t img:arm64
./build.sh -h   # 查看帮助

# 指定 JDK 版本（锁定具体更新）
docker build --build-arg JDK_VERSION=8u492-b09-jdk -t java-base:latest .

# 指定 JMX Exporter 版本（兼容 JDK 8 即可）
docker build --build-arg JMX_VERSION=1.6.0 -t java-base:latest .

# 单次命令构建双架构并推送
docker buildx build --platform linux/amd64,linux/arm64 \
  -t your-registry/java-base:latest --push .
```

## 构建参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `JDK_VERSION` | `8-jdk` | Eclipse Temurin 基础镜像标签，设为 `8u492-b09-jdk` 可锁定具体版本 |
| `JMX_VERSION` | `1.6.0` | Prometheus JMX Exporter 版本（从 GitHub Releases 下载） |

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SERVICE_NAME` | `app` | 服务名称，对应 jar 文件名 |
| `SERVICE_PORT` | `8080` | 服务端口 |
| `JAVA_OPTS_MEM` | (空) | JVM 内存参数，如 `-Xms4G -Xmx4G`（兼容现有 K8s，优先级高于 `JVM_HEAP`） |
| `JAVA_OPTS_JMX_EXPORTER` | (空) | 完整 JMX javaagent 参数，如 `-javaagent:/path/jar=port:/path/config.yaml`（兼容现有 K8s，优先级最高） |
| `JVM_HEAP` | (自动) | 堆内存，为空则根据容器内存自动计算 |
| `JVM_EXTRA_OPTS` | (空) | 附加 JVM 参数 |
| `JMX_PORT` | (空) | JMX Prometheus 端口，设值即启用内置 agent |
| `JMX_ENABLED` | `false` | JMX 开关（当 `JMX_PORT` 和 `JAVA_OPTS_JMX_EXPORTER` 都没设置时生效） |
| `JMX_EXPORTER_PORT` | `9999` | `JMX_ENABLED=true` 时使用的端口 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `DEBUG` | `false` | 调试日志 |

## 启动

```bash
docker run -d --name myapp \
  -e SERVICE_NAME=my-service \
  -e SERVICE_PORT=8080 \
  -v /path/to/my-service.jar:/service/jar/my-service.jar \
  java-base:latest
```

## 内存说明

JVM 总内存 = 堆 + Metaspace + CodeCache + 线程栈 + 堆外 (约 20-30%)。
推荐限制容器总内存，由 JVM 自动分配：

```bash
docker run --memory=6g -e SERVICE_NAME=myapp my-image
# -> JVM 堆 ~4.2g (MaxRAMPercentage=70)
```

## K8s 部署建议

### 最小 Deployment 示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-service
  template:
    metadata:
      labels:
        app: my-service
    spec:
      containers:
      - name: my-service
        image: swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630
        ports:
        - containerPort: 80
          name: http
        - containerPort: 9999
          name: jmx
        env:
        - name: SERVICE_NAME
          value: my-service
        - name: SERVICE_PORT
          value: "80"
        - name: JAVA_OPTS_MEM
          value: "-Xms2G -Xmx2G"
        - name: JAVA_OPTS_JMX_EXPORTER
          value: "-javaagent:/service/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=9999:/service/jmx_exporter/jmx_prometheus_javaagent.yaml"
        - name: TZ
          value: Asia/Shanghai
        volumeMounts:
        - mountPath: /service/jar
          name: jar-volume
        - mountPath: /service/logs
          name: log-volume
        - mountPath: /service/dumps
          name: dump-volume
        - mountPath: /service/file
          name: file-volume
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health
            port: 80
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
      - name: file-volume
        persistentVolumeClaim:
          claimName: my-service-pvc
```

### 关键字段说明

#### PreStop hook（优雅关闭）

```yaml
lifecycle:
  preStop:
    exec:
      command:
      - /bin/bash
      - -c
      - "kill -15 1; sleep 30"
```

- `kill -15 1` → 向 PID 1（Java 进程）发 SIGTERM，触发 Spring Boot 的 `shutdown hook`
- `sleep 30` → 给 JVM 预留时间完成关闭（Spring Boot 默认 `spring.lifecycle.timeout-per-shutdown-phase=30s`）
- K8s 默认给 Pod 的优雅关闭时间是 30s（`terminationGracePeriodSeconds`），如果应用关闭慢需加大

**工作原理**：entrypoint 用 `exec java ...` 启动，Java 进程成为 PID 1。tini 负责将 SIGTERM 转发给 Java。Spring Boot 收到 SIGTERM 后执行：
1. 停止接收新请求
2. 处理正在处理的请求（最多等 30s）
3. 关闭数据源、线程池等资源
4. 退出

#### 资源限制（memory 与 JVM 堆的关系）

```yaml
resources:
  limits:
    memory: "4Gi"       # 容器总内存上限
```

镜像内置：
```
-XX:MaxRAMPercentage=70.0   # 堆最大 = 4Gi × 70% ≈ 2.8Gi
-XX:InitialRAMPercentage=70.0  # 启动时直接分配
```

如果手动指定 `JAVA_OPTS_MEM` 或 `JVM_HEAP`，`MaxRAMPercentage` 不再生效：

| `resources.limits.memory` | `JAVA_OPTS_MEM` | 实际堆 | 总 RSS (约) |
|---|---|---|---|
| 4Gi | 不设置 | 2.8Gi (70%) | 4Gi |
| 4Gi | `-Xms2G -Xmx2G` | 2Gi | 2.8~3.2Gi |
| 6Gi | 不设置 | 4.2Gi (70%) | 6Gi |

**推荐**：不设 `JAVA_OPTS_MEM` 或 `JVM_HEAP`，让 JVM 根据 `resources.limits.memory` 自动计算堆大小，保留 30% 给非堆开销。

#### 探针配置

```yaml
livenessProbe:           # 容器是否存活（挂掉就重启）
  httpGet:
    path: /actuator/health
    port: 80
  initialDelaySeconds: 60   # 给 JVM 启动时间（AlwaysPreTouch + Spring Boot）
  periodSeconds: 30
  timeoutSeconds: 10

readinessProbe:          # 容器是否就绪（就绪才接收流量）
  httpGet:
    path: /actuator/health
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
```

- `readinessProbe.initialDelaySeconds` 应小于 `livenessProbe.initialDelaySeconds`
- 如果应用不是 Spring Boot（没有 `/actuator/health`），改用 `tcpSocket` 探针检查端口

#### Pod 优雅关闭超时

```yaml
spec:
  terminationGracePeriodSeconds: 60
```

确保 > `preStop sleep` + Spring Boot 关闭超时（默认 30s）。建议设为 60s。

### 环境变量优先级（从高到低）

| 用途 | 第1优先 | 第2优先 | 内置默认 |
|---|---|---|---|
| 堆内存 | `JAVA_OPTS_MEM` | `JVM_HEAP` | `MaxRAMPercentage=70` |
| JMX agent | `JAVA_OPTS_JMX_EXPORTER` | `JMX_PORT` | `JMX_ENABLED=true` |
| JVM 附加参数 | `JVM_EXTRA_OPTS` | — | 无 |

## OOM 诊断

当 JVM 发生 `OutOfMemoryError` 时自动执行：

| 产物 | 路径 | 说明 |
|------|------|------|
| 堆快照 (hprof) | `/service/dumps/*.hprof` | 堆内存完整快照，用于分析对象引用 |
| 线程快照 (thread dump) | `/service/dumps/threaddump_*.txt` | 所有线程堆栈，用于定位死锁/阻塞 |
| Crash 日志 | `/service/logs/hs_err_pid*.log` | JVM 崩溃时的诊断信息 |
| OOM 日志 | `/service/logs/oom_*.log` | 系统资源使用记录（由 oom_handler.sh 生成） |
| GC 日志 | `/service/logs/gc.log` | GC 历史记录，用于调优 |

> **清理策略**：保留最近 5 个 hprof 和 5 个 thread dump 文件，超出自动删除。

## 快速测试

依赖：Docker，无需安装 Java/Maven。

```bash
# 一键构建 + 测试 (build.sh)
chmod +x build.sh
./build.sh                              # 默认构建 java-base:latest 并测试
./build.sh -t my-registry/java-base:v1  # 指定镜像名称
./build.sh -n myapp -p 9000             # 指定应用名和端口
./build.sh -h                           # 查看全部选项

# 或使用 docker compose
docker compose run --rm build-test-app
docker compose up -d test-app
curl http://localhost:8080/api/info

# 清理
docker compose down
docker volume rm java_maven-repo
```

`test-app/` 是一个最小 Spring Boot 2.7 (JDK 8 兼容) 项目，包含 `/api/info` 和 `/actuator/health` 端点，用于验证镜像的构建和运行。详见 [`test-app/`](test-app/)。
