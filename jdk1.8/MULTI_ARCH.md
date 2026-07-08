# Multi-Arch Docker 镜像构建指南

## 目录

1. [为什么 x86 机器能构建 ARM 镜像](#1-为什么-x86-机器能构建-arm-镜像)
2. [多架构镜像在仓库中的存储原理](#2-多架构镜像在仓库中的存储原理)
3. [Docker 如何自动选择架构](#3-docker-如何自动选择架构)
4. [环境准备](#4-环境准备)
5. [构建多架构镜像](#5-构建多架构镜像)
6. [验证与测试](#6-验证与测试)
7. [构建脚本与 CI/CD](#7-构建脚本与-cicd)
8. [常见问题](#8-常见问题)

---

## 1. 为什么 x86 机器能构建 ARM 镜像

传统观念认为 "ARM 镜像必须到 ARM 机器上编译"，但 Docker 提供了 **QEMU 用户态模拟** 技术，可以在 x86 上运行 ARM 二进制文件。

### 原理

```
┌──────────────────────────────────────────────┐
│               x86 宿主机                       │
│  ┌──────────────────────────────────────────┐ │
│  │  Docker BuildKit (buildx)                │ │
│  │  ┌─────────────┐  ┌─────────────┐        │ │
│  │  │ amd64 构建   │  │ arm64 构建   │        │ │
│  │  │ 原生执行     │  │ QEMU 模拟    │        │ │
│  │  └─────────────┘  └─────────────┘        │ │
│  └──────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────┐ │
│  │  binfmt_misc + QEMU (注册 ARM 解释器)     │ │
│  │  当内核看到 ARM ELF → 自动调用 qemu-aarch64 │ │
│  └──────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

- **binfmt_misc**：Linux 内核机制，根据 ELF 文件头识别架构，自动调用对应的解释器
- **QEMU user mode**：将 ARM 系统调用翻译为 x86 系统调用，不需要完整的虚拟机
- **Docker 集成**：`tonistiigi/binfmt` 镜像一键注册所有架构的 QEMU 解释器

### 限制

| 场景 | 说明 |
|------|------|
| **纯脚本/解释型语言** (Python, Shell, Java) | 完全没问题，因为最终运行的是 JVM 字节码，Dockerfile 中的 RUN 指令很少 |
| **编译型语言** (C, Go, Rust) | 需注意交叉编译工具链，或依赖 QEMU 模拟（速度慢 5-10 倍） |
| **底层系统调用** | QEMU 覆盖了大部分 Linux 系统调用，极少数不常用的可能缺失 |

> **Java 镜像特别适合跨架构构建**：因为绝大部分 `RUN` 指令是 `apt-get`、`curl` 下载、`mkdir` 等轻量操作，不存在编译瓶颈。Dockerfile 中的工具（curl、apt）在 QEMU 下运行良好。

---

## 2. 多架构镜像在仓库中的存储原理

### 传统单架构镜像

```
Docker Hub / SWR / 其他仓库

  my-image:latest  ──→  manifest.json
                            ├── config.json (镜像元数据)
                            └── layer_sha256:abc...  (文件系统层)
                            └── layer_sha256:def...
```

### 多架构镜像 (Manifest List / OCI Index)

```
Docker Hub / SWR / 其他仓库

  my-image:latest  ──→ manifest list (OCI Index)
                            │
                            ├── 指向 amd64 的 manifest
                            │     ├── config.json
                            │     ├── layer (amd64 专用)
                            │     └── layer ...
                            │
                            └── 指向 arm64 的 manifest
                                  ├── config.json
                                  ├── layer (arm64 专用)
                                  └── layer ...

  实际存储了 2 组独立的镜像层，共用相同的层（如果内容一致则共享 sha256）
```

### manifest list 示例

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.list.v2+json",
  "manifests": [
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 3247,
      "digest": "sha256:1f4da9b8b6970cc65cfcf660011b95ba32b88b933d220ee35e429ab5be774133",
      "platform": {
        "architecture": "amd64",
        "os": "linux"
      }
    },
    {
      "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
      "size": 3247,
      "digest": "sha256:3bddd2f8ad18f8217155e42a4756c00cb088b75df98a3689bdee66f8eca7c22d",
      "platform": {
        "architecture": "arm64",
        "os": "linux",
        "variant": "v8"
      }
    }
  ]
}
```

### 仓库兼容性

| 仓库 | 支持 manifest list | 说明 |
|------|-------------------|------|
| Docker Hub | ✅ | 完整支持 |
| GitHub Container Registry (ghcr.io) | ✅ | 完整支持 |
| 阿里云 ACR | ✅ | 完整支持 |
| **华为云 SWR** | ✅ | 支持，但需 `--provenance=false --sbom=false` |
| 腾讯云 TCR | ✅ | 支持 |
| AWS ECR | ✅ | 支持 |
| Harbor (自建) | ⚠️ | v2.8+ 完整支持 |

> **华为云 SWR 特别说明**：SWR 目前不支持 OCI 镜像规范中的 attestation 格式。
> 构建时需添加 `--provenance=false --sbom=false` 禁用构建证明和 SBOM，
> 否则 push 会报错 "Invalid image, fail to parse manifest.json"。

---

## 3. Docker 如何自动选择架构

当 pull 或 run 一个多架构镜像时：

```
docker pull my-image:latest

  1. Docker 客户端请求 manifest list
  2. Docker 检测宿主机 CPU 架构 (uname -m)
  3. 在 manifest list 中查找匹配的架构
  4. 只下载匹配架构的镜像层

  x86 机器  → 自动选 amd64
  ARM 机器  → 自动选 arm64 (或 arm/v7)
  Apple Silicon (M1/M2/M3) → 自动选 arm64
```

```bash
# 查看当前机器架构
uname -m
# x86_64  → amd64
# aarch64 → arm64

# 查看 manifest list 内容
docker manifest inspect my-image:latest

# 强制拉取特定架构
docker pull --platform linux/arm64 my-image:latest
docker pull --platform linux/amd64 my-image:latest

# 在运行容器时也可指定架构
docker run --platform linux/arm64 --rm my-image uname -m
```

### K8s 中的行为

- kubelet 根据 `kubernetes.io/arch` 节点标签自动选择
- 如果节点是 arm64，调度器优先匹配 arm64 的镜像 manifest
- 不需要手动指定架构

---

## 4. 环境准备

### 4.1 安装 buildx

Docker 19.03+ 自带 buildx，但需启用：

```bash
# 检查是否可用
docker buildx version

# 如果没有，手动安装插件
# https://github.com/docker/buildx/releases
```

### 4.2 启用多架构支持（QEMU）

```bash
# 一键注册所有架构的 QEMU 解释器
docker run --privileged --rm tonistiigi/binfmt --install all

# 验证已注册的架构
ls -la /proc/sys/fs/binfmt_misc/
cat /proc/sys/fs/binfmt_misc/qemu-aarch64

# 或使用 buildx 内置命令
docker buildx inspect --bootstrap
```

### 4.3 创建并使用多架构 builder

```bash
# 查看已有的 builder
docker buildx ls

# 创建支持多架构的 builder（使用 docker-container 驱动）
docker buildx create --name multiarch --driver docker-container --use

# 初始化
docker buildx inspect --bootstrap

# 验证
docker buildx ls
# 输出应显示 multiarch builder 支持 linux/amd64, linux/arm64 等
```

> **为什么需要 docker-container 驱动？**
> - 默认的 `docker` 驱动只能构建当前宿主机架构的镜像
> - `docker-container` 驱动在容器中运行 BuildKit，支持跨平台构建和导出 manifest list
> - 该驱动才能使用 `--push` 推送 manifest list 到仓库

### 4.4 登录镜像仓库

```bash
# Docker Hub
docker login

# 华为云 SWR
docker login swr.cn-east-3.myhuaweicloud.com

# 阿里云 ACR
docker login registry.cn-hangzhou.aliyuncs.com
```

---

## 5. 构建多架构镜像

### 5.1 前提条件

在 Dockerfile 中，如果要构建多架构镜像，需要注意：

1. **使用 `ARG TARGETARCH`**（buildx 自动注入）
2. **下载二进制依赖时根据架构选择不同 URL**
3. **避免使用架构特定的基础镜像标签**（用 `8-jdk` 而不是具体 sha256）

示例（本项目的 Dockerfile）：

```dockerfile
ARG JDK_VERSION=8-jdk
FROM eclipse-temurin:${JDK_VERSION}

ARG TARGETARCH  # buildx 自动注入

# 根据架构下载不同版本的 tini
RUN curl -fsSL \
  "https://github.com/krallin/tini/releases/download/v0.19.0/tini-${TARGETARCH}" \
  -o /usr/bin/tini && \
  chmod 755 /usr/bin/tini

# 纯 Java jar 不依赖架构，无需区分
RUN curl -fsSL "https://github.com/prometheus/jmx_exporter/releases/download/v1.6.0/jmx_prometheus_javaagent-1.6.0.jar" \
  -o /service/jmx_exporter/jmx_prometheus_javaagent.jar
```

### 5.2 单条命令构建并推送

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630 \
  --provenance=false --sbom=false \
  --push .
```

说明：
| 参数 | 作用 |
|------|------|
| `--platform linux/amd64,linux/arm64` | 指定要构建的架构列表 |
| `-t <tag>` | 镜像标签，所有架构共享同一个 tag |
| `--provenance=false --sbom=false` | **华为云 SWR 必须加**，禁用 attestation 清单 |
| `--push` | 构建完成后直接推送到仓库 |
| `.` | Dockerfile 所在目录 |

### 5.3 构建到本地

如果你需要在本地加载（例如测试），需分两次构建再创建 manifest：

```bash
# 分别构建各架构并加载到本地
docker buildx build --platform linux/amd64 -t img:amd64 --load .
docker buildx build --platform linux/arm64 -t img:arm64 --load .

# 创建 manifest list
docker manifest create img:latest \
  img:amd64 \
  img:arm64

# 推送到仓库
docker manifest push img:latest
```

> **注意**：`--load` 和 `--platform` 同时使用时有数量限制。
> docker-container driver 一次 `--load` 只能加载一个平台的镜像。
> 多平台同时 `--push` 没问题，但无法同时 `--load`。

### 5.4 Docker Compose 配合 buildx

如果 docker-compose.yml 中使用了构建，可以这样指定：

```bash
DOCKER_BUILDKIT=1 docker compose build
```

docker-compose.yml 中也可以指定 platforms：

```yaml
services:
  myapp:
    build:
      context: .
      dockerfile: Dockerfile
    image: myapp:latest
    ports:
      - "8080:8080"
```

---

## 6. 验证与测试

### 6.1 查看 manifest list

```bash
docker manifest inspect \
  swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630
```

### 6.2 在不同架构的机器上运行

```bash
# x86 机器上测试（自动拉取 amd64）
docker run --rm \
  swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630 \
  java -version

# ARM 机器上测试（自动拉取 arm64）
docker run --rm \
  swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630 \
  java -version

# 在 x86 上强制测试 arm64（需要 QEMU）
docker run --platform linux/arm64 --rm \
  swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630 \
  java -version
```

### 6.3 验证架构正确性

```bash
# 进入容器查看 CPU 架构
docker run --rm --entrypoint /bin/bash \
  swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630 \
  -c 'uname -m'

# 确认 Java 是 64 位
docker run --rm --entrypoint /bin/bash \
  swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630 \
  -c 'java -version 2>&1'
```

---

## 7. 构建脚本与 CI/CD

### 7.1 使用 build.sh

本项目提供了 `build.sh` 脚本，支持 `--platform` 参数：

```bash
# 默认只构建当前架构
./build.sh

# 构建多架构并推送
./build.sh -t swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:1.8_JMX_SW_20260630 \
  --platform linux/amd64,linux/arm64
```

### 7.2 GitHub Actions 示例

```yaml
name: Build multi-arch image

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to SWR
        uses: docker/login-action@v3
        with:
          registry: swr.cn-east-3.myhuaweicloud.com
          username: ${{ secrets.SWR_USERNAME }}
          password: ${{ secrets.SWR_PASSWORD }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:latest
          provenance: false
          sbom: false
```

### 7.3 GitLab CI 示例

```yaml
stages:
  - build

build-multiarch:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  before_script:
    - docker run --privileged --rm tonistiigi/binfmt --install all
    - docker buildx create --name multiarch --driver docker-container --use
    - docker buildx inspect --bootstrap
    - docker login $CI_REGISTRY -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD
  script:
    - docker buildx build
        --platform linux/amd64,linux/arm64
        -t $CI_REGISTRY_IMAGE:latest
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
        --provenance=false --sbom=false
        --push .
```

---

## 8. 常见问题

### 8.1 "Invalid image, fail to parse manifest.json"

**原因**：华为云 SWR 不支持 OCI attestation 清单（provenance/sbom）。

**解决**：构建时添加 `--provenance=false --sbom=false`。

```bash
docker buildx build \
  --provenance=false --sbom=false \
  --platform linux/amd64,linux/arm64 \
  -t swr.cn-east-3.myhuaweicloud.com/beosin-develop/jdk:tag \
  --push .
```

### 8.2 push 时报 "unauthorized: authentication required"

**原因**：未登录或 token 过期。

**解决**：
```bash
# 重新登录
docker login swr.cn-east-3.myhuaweicloud.com
# 检查 ~/.docker/config.json 是否有效
cat ~/.docker/config.json | grep swr
```

### 8.3 构建过程中 QEMU 模拟的 arm64 很慢

**原因**：QEMU 用户态模拟比原生执行慢 5-10 倍。

**解决**：
- Java 镜像中的 `RUN` 指令很少（apt-get, curl, mkdir），慢的不明显
- 对于需要大量计算的 Dockerfile，考虑在 ARM 原生机器上构建
- 或使用交叉编译（仅适用于 Go/Rust 等语言）

### 8.4 "exec format error" 或 "not found"

**原因**：下载的二进制文件架构与构建架构不匹配。

**解决**：检查 Dockerfile 中是否正确使用了 `ARG TARGETARCH`。

```bash
# 错误：固定下载 amd64 版本
RUN curl -fsSL "https://example.com/tool-linux-amd64" -o /usr/bin/tool

# 正确：根据构建架构选择
ARG TARGETARCH
RUN curl -fsSL "https://example.com/tool-linux-${TARGETARCH}" -o /usr/bin/tool
```

### 8.5 构建完成但本地 `docker images` 看不到

**原因**：使用 `docker-container` driver + `--platform` 多架构构建时，默认不保存到本地镜像缓存。

**解决**：
- 只构建单一架构到本地：`docker buildx build --platform linux/amd64 --load .`
- 从仓库拉取：`docker pull <registry>/<image>:<tag>`
- 或直接通过 `--push` 推送到仓库后拉取

### 8.6 Docker Desktop (Mac/Windows) 需要特别配置吗？

不需要。Docker Desktop for Mac（包括 Apple Silicon）和 Docker Desktop for Windows 自带 QEMU 和 binfmt_misc 支持，开箱即用。

---

## 参考

- [Build multi-architecture images | Docker Docs](https://docs.docker.com/build/building/multi-platform/)
- [QEMU User Mode Emulation](https://www.qemu.org/docs/master/user/main.html)
- [binfmt_misc - Linux kernel documentation](https://www.kernel.org/doc/html/latest/admin-guide/binfmt-misc.html)
- [Huawei SWR Documentation](https://support.huaweicloud.com/swr/)
