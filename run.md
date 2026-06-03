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

### 2. 一键运行容器并配置前置代理

如果您的宿主机网络受限（例如国内环境），可以直接在 `docker run` 命令中通过 `-e PROXY_URL` 参数将流量指向您的本地代理工具（例如 Clash 运行在宿主机的局域网 IP `172.17.0.1` 上的 `7890` 端口）：

```bash
docker run -d \
    --name tuxler-server \
    -e PROXY_URL=http://172.17.0.1:7890 \
    --cap-add=NET_ADMIN \
    --hostname="$(hostname)" \
    --shm-size="2g" \
    -p 127.0.0.1:1701:1701/tcp \
    -p 127.0.0.1:23321:23321/tcp \
    --rm \
    docker-tuxlervpn-server \
    node client.js
```

---

## 二、 Podman 部署运行

由于 Podman 默认采用无 Root（Rootless）模式，内核限制更为严格，需要根据部署形态选择以下命令：

### 准备工作（仅限非 Root/Rootless 模式）
1. **网络穿透配置**：在 Rootless 模式下，Podman 默认采用 `slirp4netns` 虚拟网络，它默认阻断容器向宿主机 `127.0.0.1` 环路的网络请求。为了让容器能够顺利连接物理机上的 Clash / 代理服务（如端口 `7890`），我们必须：
   - 在创建 Pod 或容器时，额外追加 **`--network slirp4netns:allow_host_loopback=true`** 参数解锁环路限制。
   - 在容器内部声明 `PROXY_URL` 时，将代理地址指向 **`http://10.0.2.2:7890`**（`10.0.2.2` 是 `slirp4netns` 路由回宿主机 loopback 的专用网关 IP）：
     ```bash
     export PROXY_URL=http://10.0.2.2:7890
     ```
2. **内核修改避空**：编辑当前目录下的 [startup.sh](startup.sh) 文件，将第 18 行 `sysctl -w net.ipv4.conf.eth0.route_localnet=1` 注释掉（行首加 `#`），防止因权限不足导致容器构建启动失败。

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
    -e PROXY_URL=http://10.0.2.2:7890 \
    --cap-add=NET_ADMIN \
    --sysctl net.ipv4.conf.all.route_localnet=1 \
    --hostname="$(hostname)" \
    --shm-size="2g" \
    -p 127.0.0.1:1701:1701/tcp \
    -p 127.0.0.1:23321:23321/tcp \
    --rm \
    docker-tuxlervpn-server \
    node client.js
```
*(在启动时通过 `--sysctl` 命令行参数由引擎代为配置内核参数。)*

---

### 形态 B：Pod 容器组模式（Pod Mode - 推荐）

Pod 模式将网络命名空间、端口映射与内核参数配置在 Pod 级别统一管理，更适合复杂多容器协同。

#### 1. 创建共享网络 Pod
```bash
podman pod create \
    --name tuxler-pod \
    --network slirp4netns:allow_host_loopback=true \
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
    -e PROXY_URL=http://10.0.2.2:7890 \
    --cap-add=NET_ADMIN \
    --shm-size="2g" \
    --rm \
    docker-tuxlervpn-server \
    node client.js
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

- **创建澳大利亚专属 Pod**（映射代理出口 `10080`）：
  ```bash
  podman pod create \
      --name tuxler-pod-au \
      --network slirp4netns:allow_host_loopback=true \
      --publish 127.0.0.1:10080:10080/tcp
  ```

- **启动澳洲容器并绑定至该 Pod**（指定 `TUXLER_COUNTRY=AU`）：
  ```bash
  podman run -d \
      --pod tuxler-pod-au \
      --name tuxler-container-au \
      -e TUXLER_COUNTRY=AU \
      -e PROXY_URL=http://10.0.2.2:7890 \
      -e TUXLER_ENABLE_IPTABLES=0 \
      -e TUXLER_FORWARD_LISTEN_PORT=10080 \
      --memory=1g \
      --memory-swap=1g \
      --pids-limit=256 \
      --shm-size=512m \
      --rm \
      docker-tuxlervpn-server \
      node client.js
  ```

---

### 2. 启动土耳其 (TR) 实例

- **创建土耳其专属 Pod**（映射代理出口 `10081`）：
  ```bash
  podman pod create \
      --name tuxler-pod-tr \
      --network slirp4netns:allow_host_loopback=true \
      --publish 127.0.0.1:10081:10080/tcp
  ```

- **启动土耳其容器并绑定至该 Pod**（指定 `TUXLER_COUNTRY=TR`）：
  ```bash
  podman run -d \
      --pod tuxler-pod-tr \
      --name tuxler-container-tr \
      -e TUXLER_COUNTRY=TR \
      -e PROXY_URL=http://10.0.2.2:7890 \
      -e TUXLER_ENABLE_IPTABLES=0 \
      -e TUXLER_FORWARD_LISTEN_PORT=10080 \
      --memory=1g \
      --memory-swap=1g \
      --pids-limit=256 \
      --shm-size=512m \
      --rm \
      docker-tuxlervpn-server \
      node client.js
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

---

## 五、资源限制与故障复盘

### 1. 不要再使用旧的 rootless 映射方式

旧命令里这种映射不适合当前 rootless 方案：

```bash
--publish 127.0.0.1:10080:23321/tcp
--cap-add=NET_ADMIN
--sysctl net.ipv4.conf.all.route_localnet=1
```

原因是 Tuxler 代理实际监听在容器内部的 `127.0.0.1:23321`。Podman publish 进入的是容器网卡侧端口，不能直接访问容器 loopback。旧方案依赖 startup.sh 里的 iptables DNAT 转发，但 rootless Podman 通常没有权限修改容器内 `nat` 表。

当前推荐链路是：

```text
宿主机 127.0.0.1:10080
-> 容器 0.0.0.0:10080
-> proxy-forward.js
-> 容器 127.0.0.1:23321
-> Tuxler SOCKS 代理
```

### 2. 内存与进程数护栏

`--shm-size=512m` 只是 `/dev/shm` 的上限，不是启动时预分配的内存。真正用于保护宿主机的是：

```bash
--memory=1g
--memory-swap=1g
--pids-limit=256
```

不要在没有 `--memory` 和 `--pids-limit` 的情况下并行启动多个国家实例。Wine、Xvfb、Tuxler helper、Node、transocks 都会占用资源；如果异常增长，没有上限时可能把宿主机拖入 OOM 或 swap 抖动。

运行后观察资源：

```bash
podman stats tuxler-container-au
```

### 3. 清理命令的边界

以下命令可以停止并删除 Podman 对象：

```bash
podman rm -f tuxler-container-au
podman pod rm -f tuxler-pod-au
```

但如果宿主机已经 OOM、SSH 被杀、系统正在大量 swap，删除容器不一定能让服务器立刻恢复可连接。此时需要通过云厂商控制台、VNC、IPMI 或物理控制台进入机器，必要时先重启。

恢复后检查：

```bash
free -h
podman ps -a
podman pod ps
ps aux --sort=-rss | head -30
ps aux | grep -Ei 'wine|wineserver|Xvfb|ExtensionHelper|podman|conmon|slirp4netns|transocks|node'
dmesg -T | grep -Ei 'oom|out of memory|killed process'
journalctl -k -b -1 | grep -Ei 'oom|out of memory|killed process'
```

如确认有残留进程，再谨慎清理：

```bash
pkill -f 'ExtensionHelper|wineserver|Xvfb|transocks|proxy-forward|client.js'
pkill -f 'conmon|slirp4netns'
```

### 4. 安全边界

当前方案应保持 rootless Podman，不使用 `--privileged`，不使用 `--cap-add=NET_ADMIN`，并只把代理端口绑定到宿主机 `127.0.0.1`。仓库包含 `setup.tar` 内的 Windows exe 和 `transocks` 二进制，无法仅凭源码审查证明绝对安全；本机 Microsoft Defender 扫描当前仓库未发现威胁，但这不等于绝对安全保证。
