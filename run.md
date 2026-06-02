# Docker & Podman 极简部署与运行指南

本项目通过极简端口映射（仅保留核心控制与出口端口）以及精细化权限配置，实现了在 Docker 或 Podman 环境下的高效运行。

---

## 端口精简说明

原版配置映射了 16 个动态端口，现已精简为最核心的两个端口：
- **`1701`**：控制通道端口（用于控制脚本切换 IP）
- **`23321`**：住宅代理出口端口（用于 Clash 或其它客户端接入代理）

> **安全提示**：使用更安全的 `--cap-add=NET_ADMIN` 替代粗放的 `--privileged` 参数，保障宿主机系统安全。

---

## 一、 Docker 极简部署运行

### 1. 构建镜像
```bash
docker build -t docker-tuxlervpn-server .
```

### 2. 声明前置代理（若宿主机网络受限）
```bash
# 声明本地代理，例如 Clash 端口 7890
export PROXY_URL=http://172.17.0.1:7890
```

### 3. 一键运行容器
```bash
docker run -d \
    --name tuxler-server \
    --cap-add=NET_ADMIN \
    --hostname="$(hostname)" \
    --shm-size="2g" \
    -p 127.0.0.1:1701:1701/tcp \
    -p 127.0.0.1:23321:23321/tcp \
    --rm \
    docker-tuxlervpn-server
```

---

## 二、 Podman 部署运行

由于 Podman 默认采用无 Root（Rootless）模式，内核限制更为严格，需要根据部署形态选择以下命令：

### 准备工作（仅限非 Root/Rootless 模式）
在 Rootless 模式下，容器内进程无法直接运行 `sysctl` 指令。
1. 请编辑当前目录下的 [startup.sh](startup.sh) 文件。
2. 将第 18 行 `sysctl -w net.ipv4.conf.eth0.route_localnet=1` 在行首添加 `#` 注释掉。

---

### 形态 A：独立容器模式（Solo Container）

#### 1. 构建镜像
```bash
podman build -t docker-tuxlervpn-server .
```

#### 2. 一键运行容器
```bash
podman run -d \
    --name tuxler-server \
    --cap-add=NET_ADMIN \
    --sysctl net.ipv4.conf.all.route_localnet=1 \
    --hostname="$(hostname)" \
    --shm-size="2g" \
    -p 127.0.0.1:1701:1701/tcp \
    -p 127.0.0.1:23321:23321/tcp \
    --rm \
    docker-tuxlervpn-server
```
*(在启动时通过 `--sysctl` 命令行参数由引擎代为配置内核参数。)*

---

### 形态 B：Pod 容器组模式（Pod Mode - 推荐）

Pod 模式将网络命名空间、端口映射与内核参数配置在 Pod 级别统一管理，更适合复杂多容器协同。

#### 1. 创建共享网络 Pod
```bash
podman pod create \
    --name tuxler-pod \
    --sysctl net.ipv4.conf.all.route_localnet=1 \
    --publish 127.0.0.1:1701:1701/tcp \
    --publish 127.0.0.1:23321:23321/tcp
```

#### 2. 启动容器并载入 Pod
```bash
podman run -d \
    --pod tuxler-pod \
    --name tuxler-container \
    -e TUXLER_COUNTRY=AU \
    --cap-add=NET_ADMIN \
    --shm-size="2g" \
    --rm \
    docker-tuxlervpn-server
```
*(注：容器加入 Pod 后会自动继承 Pod 的网络和映射，无需在 run 命令中重复配置端口与 sysctl。)*

---

## 三、 住宅代理可用性测试

容器成功运行并拨号后，您可以通过以下命令验证是否拿到了家庭住宅 IP：

```bash
curl --proxy socks4://127.0.0.1:23321 http://lumtest.com/myip.json
```
如果返回的数据中包含澳大利亚或您在 `client.js` 中指定的国家 IP 信息，即说明部署成功。

---

## 四、 启动多个国家住宅代理（多实例运行）

如果需要**同时（并行）**获取多个不同国家的住宅代理（如澳大利亚 `AU` 和土耳其 `TR`），可以通过创建**多个独立的 Pod**，并分别指定其环境变量与映射到不同的宿主机端口来实现。

以下是同时启动澳洲和土耳其节点的示例命令：

### 1. 启动澳大利亚 (AU) 实例

- **创建澳大利亚专属 Pod**（映射控制端口 `17001`，代理出口 `10080`）：
  ```bash
  podman pod create \
      --name tuxler-pod-au \
      --sysctl net.ipv4.conf.all.route_localnet=1 \
      --publish 127.0.0.1:17001:1701/tcp \
      --publish 127.0.0.1:10080:23321/tcp
  ```

- **启动澳洲容器并绑定至该 Pod**（指定 `TUXLER_COUNTRY=AU`）：
  ```bash
  podman run -d \
      --pod tuxler-pod-au \
      --name tuxler-container-au \
      -e TUXLER_COUNTRY=AU \
      --cap-add=NET_ADMIN \
      --shm-size="2g" \
      --rm \
      docker-tuxlervpn-server
  ```

---

### 2. 启动土耳其 (TR) 实例

- **创建土耳其专属 Pod**（映射控制端口 `17002`，代理出口 `10081`）：
  ```bash
  podman pod create \
      --name tuxler-pod-tr \
      --sysctl net.ipv4.conf.all.route_localnet=1 \
      --publish 127.0.0.1:17002:1701/tcp \
      --publish 127.0.0.1:10081:23321/tcp
  ```

- **启动土耳其容器并绑定至该 Pod**（指定 `TUXLER_COUNTRY=TR`）：
  ```bash
  podman run -d \
      --pod tuxler-pod-tr \
      --name tuxler-container-tr \
      -e TUXLER_COUNTRY=TR \
      --cap-add=NET_ADMIN \
      --shm-size="2g" \
      --rm \
      docker-tuxlervpn-server
  ```

---

### 3. 多出口连接测试与使用

启动成功后，您的宿主机上将并行存在两个高质量住宅代理入口，您可以根据需求使用：

- **测试/使用澳大利亚住宅代理**（端口 `10080`）：
  ```bash
  curl --proxy socks4://127.0.0.1:10080 http://lumtest.com/myip.json
  ```

- **测试/使用土耳其住宅代理**（端口 `10081`）：
  ```bash
  curl --proxy socks4://127.0.0.1:10081 http://lumtest.com/myip.json
  ```
