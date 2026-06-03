# Rootless Podman 启动与复盘说明

## 1. 推荐启动方式

当前推荐方案是 rootless Podman + 用户态端口转发：

```text
宿主机 127.0.0.1:10080
-> 容器 0.0.0.0:10080
-> proxy-forward.js
-> 容器 127.0.0.1:23321
-> Tuxler SOCKS 代理
```

不要再把宿主机端口直接映射到容器 `23321`，因为 Tuxler 实际只监听容器内部的 `127.0.0.1:23321`。

查看运行日志

podman logs -f tuxler-container-au

### AU

```bash
podman pod create \
  --name tuxler-pod-au \
  --network slirp4netns:allow_host_loopback=true \
  --publish 0.0.0.0:10080:10080/tcp

podman run -d \
  --pod tuxler-pod-au \
  --name tuxler-container-au \
  -e TUXLER_COUNTRY=AU \
  -e PROXY_URL=http://10.0.2.2:7880 \
  -e TUXLER_ENABLE_IPTABLES=0 \
  -e TUXLER_FORWARD_LISTEN_PORT=10080 \
  --memory=1g \
  --memory-swap=1g \
  --pids-limit=256 \
  --shm-size=512m \
  docker-tuxlervpn-server \
  node client.js

curl --proxy socks4://127.0.0.1:10080 http://lumtest.com/myip.json
```

### TR

```bash
podman pod create \
  --name tuxler-pod-tr \
  --network slirp4netns:allow_host_loopback=true \
  --publish 127.0.0.1:10081:10080/tcp

podman run -d \
  --pod tuxler-pod-tr \
  --name tuxler-container-tr \
  -e TUXLER_COUNTRY=TR \
  -e PROXY_URL=http://10.0.2.2:7880 \
  -e TUXLER_ENABLE_IPTABLES=0 \
  -e TUXLER_FORWARD_LISTEN_PORT=10080 \
  --memory=1g \
  --memory-swap=1g \
  --pids-limit=256 \
  --shm-size=512m \
  docker-tuxlervpn-server \
  node client.js

curl --proxy socks4://127.0.0.1:10081 http://lumtest.com/myip.json
```

## 2. 不要再使用旧命令

不要再使用下面这些旧参数：

```bash
--publish 127.0.0.1:10080:23321/tcp
--cap-add=NET_ADMIN
--sysctl net.ipv4.conf.all.route_localnet=1
```

原因：

- rootless Podman 发布端口时，访问的是容器网卡侧端口，不是容器内部 loopback。
- Tuxler 代理实际监听在容器内 `127.0.0.1:23321`。
- 旧方案依赖容器内 iptables DNAT，把容器网卡流量转到 loopback。
- rootless 容器通常不能修改 `nat` 表，所以旧方案会出现宿主机 `10080` 连接重置。

当前方案使用 `proxy-forward.js` 绕开 iptables，不需要 `NET_ADMIN`，也不需要 `route_localnet`。

## 3. 内存限制说明

`--shm-size=512m` 只是 `/dev/shm` 的上限，不是启动时预分配 512MB。

真正限制容器内存和进程数的是：

```bash
--memory=1g
--memory-swap=1g
--pids-limit=256
```

含义：

- `--memory=1g`：限制容器主要进程最多使用约 1GB 内存。
- `--memory-swap=1g`：把内存 + swap 总量也限制在约 1GB，避免容器把宿主机 swap 打爆。
- `--pids-limit=256`：限制容器内最多创建 256 个进程/线程。
- `--shm-size=512m`：限制共享内存大小，避免 Xvfb/Wine 异常占用过大 shm。

注意：

- 这能限制容器内主要进程，但 rootless Podman 的少量辅助进程（如 `conmon`、`slirp4netns`）运行在宿主机用户态，仍会有少量额外开销。
- 如果你的系统不支持 cgroup v2 或 rootless memory limit，Podman 可能无法真正应用 `--memory`。启动后必须检查。

检查资源限制是否生效：

```bash
podman inspect tuxler-container-au | grep -Ei 'memory|pids'
podman stats tuxler-container-au
```

如果宿主机内存很小，可以先把上限改得更保守：

```bash
--memory=768m
--memory-swap=768m
--shm-size=256m
```

如果容器频繁 OOM，再逐步调高。

## 4. 如何阻断“本公网 IP 被当出口”

Tuxler 免费住宅模式的风险是：你的客户端可能会主动连 Tuxler 网络，并把你的公网 IP 加入社区池，让其他用户的流量从你的 IP 出去。

这通常不是“外界直接打开一个公网端口连进你的机器”，而更像是：

```text
容器内 Tuxler
-> 主动外联 Tuxler/中转服务器
-> 建立出站隧道
-> 其他用户流量经调度后从你的公网 IP 出口访问目标网站
```

如果你不能接受这一点，最可靠的做法是：

```text
不要运行 Tuxler 免费住宅模式。
```

如果只是想强制防止它使用你的公网 IP 出口，可以用防火墙阻断容器/Podman 用户的外联。但这样 Tuxler 很可能无法正常工作，因为它需要外联维持服务。

更安全的防火墙思路：

1. 创建专用 Linux 用户运行 Podman，例如 `tuxler-runner`。
2. 只对这个用户做出站限制，不要影响你的主用户和 SSH。
3. 默认阻断该用户的外联。
4. 如果你有可信的上游代理/VPN，只允许它访问上游代理端口。

示例（需要按你的系统防火墙方案调整，执行前必须确认不会影响 SSH）：

```bash
sudo useradd -m tuxler-runner

# 仅示例：先允许该用户访问本机代理，再拒绝其它外联。
# 如果你的代理不是 127.0.0.1:7880，请改成真实地址。
sudo iptables -I OUTPUT 1 -m owner --uid-owner tuxler-runner -p tcp -d 127.0.0.1 --dport 7880 -j ACCEPT
sudo iptables -I OUTPUT 2 -m owner --uid-owner tuxler-runner -j REJECT
```

然后用该用户运行 Podman：

```bash
sudo -iu tuxler-runner
podman ps
```

重要限制：

- 如果完全阻断外联，Tuxler 基本不能工作。
- 如果只允许访问上游代理，但 Tuxler/Wine 不走这个代理，它也会失败。
- 当前 `TUXLER_ENABLE_IPTABLES=0` 是为了避免 rootless 改 iptables；这也意味着不能靠容器内透明代理强制所有流量走 `PROXY_URL`。
- 如果你想既使用 Tuxler、又绝不让你的公网 IP 作为出口，现实可控方案通常是购买 premium、换商业住宅代理，或在不重要的隔离网络/一次性机器上运行。

检查监听和外联：

```bash
ss -lntup
ss -ntup | grep -Ei 'wine|ExtensionHelper|tuxler|podman|slirp|transocks|node'
podman exec tuxler-container-au ss -lntup
podman exec tuxler-container-au ss -ntup
podman stats tuxler-container-au
```

## 5. 清理与故障恢复

停止并删除 AU：

```bash
podman rm -f tuxler-container-au
podman pod rm -f tuxler-pod-au
```

停止并删除 TR：

```bash
podman rm -f tuxler-container-tr
podman pod rm -f tuxler-pod-tr
```

这些命令是正确的，但它们只删除 Podman 对象。如果容器已经导致宿主机 OOM、SSH 被杀或系统陷入 swap 抖动，删除容器不一定能让服务器立刻恢复，可能需要从云控制台/VNC/IPMI/物理控制台重启。

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