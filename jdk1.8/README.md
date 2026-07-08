# Java Docker Base Image

Java 基础运行环境镜像，支持 **amd64** 和 **arm64** 双架构。

基于 `eclipse-temurin:8-jdk`，内置 JMX Prometheus 监控。

## ARM (arm64) 支持

镜像原生支持 **amd64** 和 **arm64**，无需修改代码。

| 场景 | 说明 |
|------|------|
| ARM 机器上直接构建 | `docker build -t img .` → 自动拉取 arm64 版本 |
| x86 上构建 arm64 镜像 | `docker build --platform linux/arm64 -t img .` |
| 构建双架构并推送 | `docker buildx build --platform linux/amd64,linux/arm64 -t reg/img:tag --push .` |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SERVICE_NAME` | `app` | 服务名称，对应 jar 文件名 |
| `SERVICE_PORT` | `8080` | 服务端口 |
| `JAVA_OPTS_MEM` | (空) | JVM 内存参数，**优先级最高**，如 `-Xms4G -Xmx4G` |
| `JVM_HEAP` | (空) | 堆内存（优先级低于 `JAVA_OPTS_MEM`） |
| `JAVA_OPTS_JMX_EXPORTER` | (空) | 完整 JMX javaagent 参数（覆盖默认） |
| `JVM_EXTRA_OPTS` | (空) | 附加 JVM 参数 |
| `JMX_EXPORTER_PORT` | `9999` | JMX Prometheus 端口 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `DEBUG` | `false` | 调试日志 |

### 内存优先级

```
JAVA_OPTS_MEM  >  JVM_HEAP  >  默认 -Xms2G -Xmx2G
```

默认 `-Xms2G -Xmx2G`，适用于 2.5G request / 3G limit 的容器。

## K8s 部署

### 完整示例

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
        # 默认 -Xms2G -Xmx2G，不设 JAVA_OPTS_MEM 即可
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

### 内存配比

| 期望堆 | `JAVA_OPTS_MEM` | request | limit |
|--------|-----------------|---------|-------|
| 2G | 不设置(默认) | 2.5Gi | 3Gi |
| 3G | `-Xms3G -Xmx3G` | 3.5Gi | 4Gi |
| 4G | `-Xms4G -Xmx4G` | 4.5Gi | 6Gi |

## 构建

```bash
./build.sh
./build.sh -t swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:8-jdk_JMX_20260701
./build.sh -t myimg:latest -n myapp -p 9000
./build.sh --platform linux/arm64 -t img:arm64
```

## OOM 诊断

| 产物 | 路径 | 说明 |
|------|------|------|
| 堆快照 | `/service/dumps/*.hprof` | 堆内存完整快照 |
| 线程快照 | `/service/dumps/threaddump_*.txt` | 所有线程堆栈 |
| Crash 日志 | `/service/logs/hs_err_pid*.log` | JVM 崩溃诊断 |
| OOM 日志 | `/service/logs/oom_*.log` | 资源使用记录 |
| GC 日志 | `/service/logs/gc.log` | GC 历史 |
