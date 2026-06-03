# Research Thinking Timeline

## N001 - 仓库用途与当前可用性初判

- branch_id: B001
- parent_node_ids:
- relation_type: next
- 当时问题: 当前仓库到底是做什么的，按现有文件看能不能正常跑起来。
- 触发原因（为什么想到这个）: 用户直接询问“当前代码库是用来干啥的？功能正常吗？”，需要先从仓库文件和本地环境确认事实，而不是凭文件名猜。
- 当时假设: 这个仓库可能是把 Tuxler VPN/代理能力封装成 Docker 或 Podman 服务，对外暴露本地代理端口。
- 采取动作（做了什么实验/改了什么）: 查看 README、run.md、Dockerfile、docker-compose.yml、startup.sh、run.sh、kill.sh、client.js 和 setup.tar 内容；运行 node 语法检查、bash 语法检查、本地 Docker/Podman 可用性检查，并确认 transocks 是 Linux ELF 二进制。
- 观察结果（事实）: setup.tar 内包含 ExtensionHelperApp 相关 Windows 可执行文件；Dockerfile 安装 Wine、Xvfb、iptables、npm ws，并复制 transocks 和 client.js；startup.sh 配置 transocks、iptables 和 Wine 程序；client.js 通过 WebSocket 向本地 Tuxler app 发送 SET_PROXY 和 changeIPCountryCityNew；本地没有 Docker CLI，client.js 语法通过但宿主机缺少 ws 依赖；docker-compose.yml 没有传入 command 或 PROXY_URL。
- 当时结论（解释）: 仓库目标是容器化运行 Tuxler Windows 辅助程序，并导出住宅代理端口；代码静态上基本能解释通，但当前环境无法端到端验证，且 compose/run 脚本存在明显开箱运行风险。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 如果要确认功能正常，需要在有 Docker 或 Podman 的环境里构建并启动，并检查代理端口是否真的返回目标国家住宅 IP。
- 下一步计划: 先向用户说明用途、已验证范围和发现的运行风险；如用户要继续修复，再最小范围调整 compose/run/kill 脚本和启动参数。

## N002 - Podman Pod 启动命令可行性判断

- branch_id: B001
- parent_node_ids: N001
- relation_type: next
- 当时问题: 用户给出的两条 Podman 命令能不能把澳洲 Tuxler 住宅代理实例正常启动起来。
- 触发原因（为什么想到这个）: 用户把实际准备执行的 pod create 和 podman run 命令贴出来，需要从 startup.sh、client.js 和 run.md 对照判断，而不是只停留在“仓库可能有风险”的粗略结论。
- 当时假设: 如果镜像已经成功构建，宿主机的前置 HTTP 代理端口真实可达，并且 Podman 支持当前 rootless 网络和 sysctl 参数，这两条命令应该能走到服务启动阶段。
- 采取动作（做了什么实验/改了什么）: 对照 startup.sh 的 entrypoint 参数执行逻辑、iptables 端口转发、Wine 程序启动和 client.js 的 WebSocket 端口扫描逻辑，检查用户命令与 run.md 里的 Pod 模式示例是否一致。
- 观察结果（事实）: Dockerfile 的 ENTRYPOINT 会接收 `node client.js` 作为参数并在 startup.sh 末尾执行；Pod 的端口映射把宿主机 10080 转到容器 23321，把 17001 转到 1701；client.js 默认会连接 1701 并按 TUXLER_COUNTRY=AU 请求澳洲住宅 IP；用户命令里的 PROXY_URL 是 `http://10.0.2.2:7880`，而文档示例使用的是 7890。
- 当时结论（解释）: 这两条命令的结构基本正确，但能否正常出代理取决于宿主机 10.0.2.2:7880 是否真有可用 HTTP 代理、镜像是否已构建、Podman 是否允许 NET_ADMIN/iptables/sysctl，以及 Tuxler helper 是否能成功登录并提供 23321 代理口。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要用户在有 Podman 的机器上实际运行后，用 podman logs 和 curl --proxy socks4://127.0.0.1:10080 做出口验证。
- 下一步计划: 先给用户明确判断和执行前检查项；如果启动失败，再按日志定位是前置代理、Podman 权限、Tuxler helper 还是 client.js 控制链路的问题。

## N003 - 实际启动日志的部分成功与转发失败判断

- branch_id: B001
- parent_node_ids: N002
- relation_type: next
- 当时问题: 用户贴出的启动日志到底表示成功了，还是只是进程跑起来但代理不可用。
- 触发原因（为什么想到这个）: 日志同时出现了 `iptables Permission denied` 和后续 `CONNECTED`、`ACCOUNT_INFO`，需要区分 Tuxler helper 连上和宿主机代理出口可用这两件事。
- 当时假设: 如果 `CONNECTED` 是 Tuxler app 的状态消息，则控制链路已经打通；但如果 iptables NAT 规则全部失败，容器对外暴露的代理端口和透明转发链路可能仍然不可用。
- 采取动作（做了什么实验/改了什么）: 阅读用户贴出的完整日志，按启动顺序对照 startup.sh 的 transocks、iptables、Wine helper 和 client.js WebSocket 控制步骤。
- 观察结果（事实）: transocks 有启动日志；iptables 多次报 `can't initialize iptables table nat: Permission denied`；Wine 有图形驱动相关警告；client.js 一度连上 `ws://127.0.0.1:1701/tuxler` 并发送 `SET_PROXY` 和 `changeIPCountryCityNew`；后续收到 `CONNECTED`、`ACCOUNT_INFO`、`LIMITS_INFO`。
- 当时结论（解释）: 这不是干净的成功启动，而是 Tuxler helper 和 Node 控制链路已经部分成功，但 Podman 容器里的 NAT/iptables 转发层失败；最终是否能作为宿主机 `127.0.0.1:10080` 代理使用，必须再用 curl 代理测试确认。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要确认 `curl --proxy socks4://127.0.0.1:10080 http://lumtest.com/myip.json` 是否能返回澳洲住宅 IP，以及容器是否需要改成 rootful Podman 或换网络/端口暴露方案。
- 下一步计划: 先提醒用户当前只是部分启动成功；如果代理测试失败，优先处理 rootless Podman 的 NET_ADMIN/iptables 权限问题，再考虑让 Tuxler 代理监听地址或端口转发方式绕过 DNAT。

## N004 - 代理端口连接重置的原因收敛

- branch_id: B001
- parent_node_ids: N003
- relation_type: next
- 当时问题: 宿主机通过 `curl --proxy socks4://127.0.0.1:10080` 测试代理时返回 `Recv failure: 连接被对方重置`，这说明代理链路坏在什么位置。
- 触发原因（为什么想到这个）: 用户贴出了实际 curl 结果，错误不是连接拒绝或超时，而是连接建立后被重置，需要结合前面 iptables NAT 权限失败重新判断。
- 当时假设: Podman 的宿主机端口映射已经把连接送进容器，但因为 startup.sh 里的 PREROUTING DNAT 没有成功，连接没有转到 Tuxler helper 实际监听的 `127.0.0.1:23321`，所以被内部网络栈或服务重置。
- 采取动作（做了什么实验/改了什么）: 对照 startup.sh 中 `23321` 到 `127.0.0.1` 的 DNAT 规则、run.md 中 `10080:23321` 的 Podman 映射示例，以及用户前一轮日志里的 iptables 权限错误。
- 观察结果（事实）: startup.sh 依赖 `iptables -t nat -I PREROUTING ... --dports 23321 ... -j DNAT --to-destination 127.0.0.1`；前一轮日志显示 nat 表初始化被拒绝；本轮 curl 到宿主机 10080 后收到连接重置。
- 当时结论（解释）: 当前不是代理成功，只是端口映射或服务入口部分可达；最可能的问题是 rootless Podman 没能配置容器内 NAT，导致宿主机入口无法接到 Tuxler 的 loopback SOCKS 代理。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要在容器内确认 `127.0.0.1:23321` 是否能直接代理成功；如果容器内成功而宿主机失败，就优先改 rootful/privileged 或改转发方案。
- 下一步计划: 指导用户先运行容器内 curl 与端口监听检查，按结果决定是权限启动方案问题，还是 Tuxler 代理自身没有真正可用。

## N005 - 容器内代理本体已成功验证

- branch_id: B001
- parent_node_ids: N004
- relation_type: next
- 当时问题: 容器内直接访问 `127.0.0.1:23321` 已返回澳洲 IP，这说明前面宿主机 `10080` 连接重置到底还剩什么问题。
- 触发原因（为什么想到这个）: 用户在容器内执行 `curl --proxy socks4://127.0.0.1:23321 http://lumtest.com/myip.json`，拿到了 `country: AU` 和 Melbourne 地理信息，这是第一次直接验证 Tuxler 代理本体可用。
- 当时假设: 如果容器内 loopback 代理成功，而宿主机映射端口失败，那么 Tuxler helper、账号状态、目标国家切换和前置代理链路已经没问题，问题集中在 Podman 入站端口到容器内 loopback 的转发。
- 采取动作（做了什么实验/改了什么）: 读取用户给出的容器内 curl 返回结果，并把它与前一轮宿主机 `10080` 连接重置、iptables NAT 权限失败的现象串起来判断。
- 观察结果（事实）: 容器内 `127.0.0.1:23321` 通过 SOCKS4 成功访问 lumtest，返回 AU、Melbourne、Superloop 等出口信息；宿主机 `127.0.0.1:10080` 仍然会连接重置。
- 当时结论（解释）: 当前服务在容器内部已经成功，失败点不是 Tuxler 代理本体，而是 rootless Podman 的端口映射无法直接访问容器内只绑定 loopback 的 `23321`，且 startup.sh 用来绕这个问题的 DNAT 规则又因为权限失败没有生效。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要选择让宿主机访问容器内代理的实现方式：用 rootful/privileged 让 DNAT 生效，或在容器里增加一个监听 `0.0.0.0` 的 TCP 转发器，把外部 23321 转到 `127.0.0.1:23321`。
- 下一步计划: 先建议用户做一次 rootful Podman 或 privileged 验证；如果想保持 rootless，再改镜像启动逻辑加轻量端口转发，绕开 iptables PREROUTING。

## N006 - 区分宿主机绑定地址与容器内监听地址

- branch_id: B001
- parent_node_ids: N005
- relation_type: next
- 当时问题: netstat 显示 Tuxler 只监听 `127.0.0.1:1701` 和 `127.0.0.1:23321`，用户怀疑是不是不该用 `127.0.0.1`，应该改用 `0.0.0.0`。
- 触发原因（为什么想到这个）: 用户贴出了容器内端口监听结果，这直接解释了为什么容器内 curl 成功但宿主机 published 端口访问失败。
- 当时假设: 宿主机侧 `--publish 127.0.0.1:10080:...` 是安全合理的，只表示只让宿主机本地访问；真正的问题是容器内目标服务没有监听容器网卡地址或 `0.0.0.0`。
- 采取动作（做了什么实验/改了什么）: 对照 netstat 输出、Podman 端口发布语义和 startup.sh 中原本依赖 DNAT 把容器网卡入站流量转到 loopback 的设计。
- 观察结果（事实）: Tuxler/wineserver 监听在容器 loopback；Podman 的 published 端口进入容器网络时访问的是容器网卡侧目标端口；startup.sh 的 DNAT 规则本应转到 loopback，但 rootless 权限下没有成功。
- 当时结论（解释）: 不应该把宿主机发布地址从 `127.0.0.1` 改成 `0.0.0.0`；要解决的是容器内监听地址问题，即让代理服务或一个转发器监听容器网卡地址/`0.0.0.0`，再转到 Tuxler 的 `127.0.0.1:23321`。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要决定是临时用 rootful/privileged 让 DNAT 生效，还是长期在容器内增加用户态 TCP 转发器。
- 下一步计划: 给用户明确解释两种 `127.0.0.1` 的区别，并建议优先做 rootless 兼容的用户态转发方案。

## N007 - Podman 发布端口与容器内 iptables 不是同一层

- branch_id: B001
- parent_node_ids: N006
- relation_type: next
- 当时问题: 用户已经在 `podman pod create` 里设置了 `--publish`、`allow_host_loopback` 和 `route_localnet`，为什么容器里的 iptables DNAT 仍然不成功。
- 触发原因（为什么想到这个）: 用户把 Podman pod create 命令和 startup.sh 内部 iptables 映射混在一起理解，需要把外层端口发布、容器出站回宿主机、内核 loopback 路由开关、容器内 netfilter 权限拆开解释。
- 当时假设: rootless Podman 的 `--publish` 可以把宿主机端口转到容器网卡地址，但不会帮容器内的 `iptables -t nat PREROUTING` 获得权限；`allow_host_loopback` 只影响容器访问宿主机 loopback；`route_localnet` 只在 DNAT 成功后允许转向 127/8。
- 采取动作（做了什么实验/改了什么）: 对照 run.md 中的 Podman 参数、startup.sh 中的 PREROUTING DNAT，以及前面日志里的 `nat: Permission denied` 和 netstat 监听地址结果。
- 观察结果（事实）: Podman 发布端口已经让宿主机连接进入容器，但 Tuxler 服务只监听容器 loopback；startup.sh 的 DNAT 规则需要容器内修改 nat 表权限，而 rootless 场景下该权限被拒绝；`route_localnet=1` 没有改变这个权限结果。
- 当时结论（解释）: 内部 iptables 不成功不是因为 Podman publish 没写对，而是因为 rootless 容器无权操作 nat 表；即使有 publish 和 sysctl，只要 DNAT 规则没加上，外部连接仍然无法到达 `127.0.0.1:23321`。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 如果坚持 rootless，是否接受在容器里加用户态 TCP 转发器作为长期方案。
- 下一步计划: 向用户解释各参数边界，并建议优先采用用户态转发器，或用 rootful/privileged 作为验证而非长期默认。

## N008 - rootful/privileged 风险与用户态转发改造边界

- branch_id: B001
- parent_node_ids: N007
- relation_type: next
- 当时问题: 用 rootful/privileged 临时验证会不会影响宿主机，以及用户态转发方案是否需要新增文件。
- 触发原因（为什么想到这个）: 用户开始比较两条修复路线的风险和实现成本，需要把“临时验证”和“长期方案”拆开说明。
- 当时假设: rootful/privileged 可以让容器内 iptables 更接近真实 root 权限，可能验证 DNAT 方案，但它扩大了容器对宿主机内核网络栈的操作面；用户态转发方案则可以绕开内核 nat 表，通常只需要一个小转发脚本或利用现有工具。
- 采取动作（做了什么实验/改了什么）: 基于前面已验证的容器内代理成功、rootless DNAT 失败、Tuxler 仅监听 loopback 的结论，比较两种方案对宿主机权限、文件改动和长期维护的影响。
- 观察结果（事实）: 当前失败点只在宿主机 published 端口到容器 loopback 代理之间；rootful/privileged 不需要改代码但提升权限；用户态转发需要改镜像启动逻辑，可能新增一个小脚本或在 Dockerfile 安装/使用转发工具。
- 当时结论（解释）: rootful/privileged 适合一次性验证，不建议作为默认长期方案；长期更稳的是在容器内增加监听 `0.0.0.0` 的用户态转发入口，再把 Podman 端口映射到这个入口。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 如果用户选择长期方案，需要决定转发器实现方式：新增 Node 转发脚本、使用 socat，还是复用已有可用二进制。
- 下一步计划: 先回答用户对宿主机影响和新文件需求的疑问；若用户确认要改，再按最小 patch 增加 rootless 兼容转发入口。

## N009 - 多国家并行下转发端口不能写死到宿主机语义

- branch_id: B001
- parent_node_ids: N008
- relation_type: next
- 当时问题: 用户可能同时创建多个国家代理实例，如果用户态转发器端口写死，会不会导致多实例无法并行使用。
- 触发原因（为什么想到这个）: 用户指出 AU、TR 等多国家实例会同时存在，这要求方案不能把宿主机端口和容器内部转发端口混为一个固定值。
- 当时假设: 在“每个国家一个独立 Pod”的部署方式下，容器内部转发端口可以相同，因为不同 Pod 有独立网络命名空间；真正需要各不相同的是宿主机发布端口。
- 采取动作（做了什么实验/改了什么）: 对照 run.md 中 AU 使用宿主机 10080、TR 使用宿主机 10081 的部署模式，重新审视用户态转发方案的端口设计。
- 观察结果（事实）: 现有多国家示例已经通过不同 Pod 和不同宿主机端口区分实例；Tuxler 在每个容器内固定监听 `127.0.0.1:23321`；端口冲突只会发生在同一个网络命名空间内。
- 当时结论（解释）: 长期方案不应该把宿主机端口写死进镜像；应提供环境变量控制容器内转发监听端口，同时允许多个 Pod 使用相同默认内部端口，再由 Podman publish 映射到不同宿主机端口。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要确定转发器的环境变量命名和默认值，例如 `TUXLER_FORWARD_LISTEN_PORT=10080`、`TUXLER_FORWARD_TARGET_HOST=127.0.0.1`、`TUXLER_FORWARD_TARGET_PORT=23321`。
- 下一步计划: 向用户说明多 Pod 情况下内部端口可复用，并建议实现为可配置环境变量，避免固定宿主机端口。

## N010 - 方法一不必直接上 privileged

- branch_id: B001
- parent_node_ids: N008,N009
- relation_type: merge_into
- 当时问题: 用户追问方法一是不是只能用 `--privileged` 才能让 iptables DNAT 生效。
- 触发原因（为什么想到这个）: 前面为了快速验证提到过 rootful/privileged，但这可能让用户以为 privileged 是唯一可行路径，需要把最小权限验证顺序讲清楚。
- 当时假设: 让 startup.sh 的 DNAT 生效，本质需要容器进程在对应 Pod 网络命名空间里拥有足够的 `CAP_NET_ADMIN` 和 netfilter 操作能力；在 rootful Podman 下，`--cap-add=NET_ADMIN` 可能已经足够，`--privileged` 只是更宽的兜底验证。
- 采取动作（做了什么实验/改了什么）: 回看 startup.sh 的 iptables 需求、run.md 的 `--cap-add=NET_ADMIN` 设计，以及前面 rootless 下 `nat: Permission denied` 的实际错误。
- 观察结果（事实）: 当前报错来自 rootless 场景下容器内无法初始化 nat 表；已有命令已经使用 `--cap-add=NET_ADMIN`，但 rootless 权限边界让它没有达到预期；没有证据表明必须直接使用 privileged。
- 当时结论（解释）: 方法一应按权限从小到大验证：先 rootful Podman + `--cap-add=NET_ADMIN` + pod 级 sysctl；失败后再临时尝试 `--privileged`，不建议把 privileged 作为默认长期启动方式。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要用户在目标机器上验证 rootful + NET_ADMIN 是否足够，并通过日志确认 iptables 是否仍报 `Permission denied`。
- 下一步计划: 给出最小权限验证命令顺序，并提醒保持宿主机端口只绑定 `127.0.0.1`。

## N011 - 宿主机零影响约束排除 rootful/netfilter 路线

- branch_id: B002
- parent_node_ids: N010
- relation_type: split_from
- 当时问题: 用户要求容器中的行为绝对不能对宿主机产生影响，rootful 是否等于 bridge，以及方法一还能不能作为可接受方案。
- 触发原因（为什么想到这个）: 用户提出了更强的安全前提，这改变了方案选择标准，不再只是“能不能跑通”，而是要避免容器获得影响宿主机网络栈的能力。
- 当时假设: rootful 是运行权限边界，bridge 是网络模式，两者不是同一概念；只要方案依赖 rootful、privileged、NET_ADMIN 或容器内改 netfilter，就不符合“容器行为不影响宿主机”的严格约束。
- 采取动作（做了什么实验/改了什么）: 重新评估方法一和方法二的安全边界，把前面为了验证 DNAT 的 rootful/privileged 路线从长期方案候选中降级为不推荐路线。
- 观察结果（事实）: 当前可用性已经在容器内验证成功，失败点只剩宿主机 published 端口到容器 loopback 的连接；这个失败点可以通过用户态 TCP 转发解决，不需要容器改 iptables。
- 当时结论（解释）: 在用户的安全前提下，不应使用方法一作为方案；应保留 rootless Podman，去掉对 NET_ADMIN/sysctl/iptables DNAT 的依赖，用用户态转发把容器网卡监听端口接到 Tuxler loopback 代理。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要实现一个最小用户态转发入口，并决定是否让 startup.sh 在 rootless 安全模式下跳过 iptables 规则。
- 下一步计划: 向用户解释 rootful 与 bridge 的区别，并建议后续代码改造采用 rootless-only 用户态转发方案。

## N012 - 落地 rootless 用户态转发方案

- branch_id: B002
- parent_node_ids: N011
- relation_type: next
- 当时问题: 用户确认采用方法二，并指定多国家部署方式与新增 `proxy-forward.js`，需要把方案落实到代码和运行文档。
- 触发原因（为什么想到这个）: 前面已经验证 Tuxler 容器内代理成功，失败点是宿主机端口到容器 loopback 的连接；用户明确选择“一个国家一个独立 Pod，宿主机端口不同，容器内转发端口可复用”的路线。
- 当时假设: 使用 Node 标准库实现 TCP 转发即可，不需要新增 npm 依赖；容器内默认监听 `0.0.0.0:10080`，转发到 `127.0.0.1:23321`，多个 Pod 可以复用同一个容器内端口。
- 采取动作（做了什么实验/改了什么）: 新增 `proxy-forward.js`；Dockerfile 复制该文件进镜像；startup.sh 增加 `TUXLER_ENABLE_IPTABLES` 开关和 `TUXLER_FORWARD_ENABLED` 转发器启动逻辑；run.md 的 AU/TR 示例改为宿主机端口映射到容器内 `10080`，并禁用 iptables。
- 观察结果（事实）: `node --check proxy-forward.js`、`node --check client.js` 和 `bash -n startup.sh` 均通过；本地 Node 烟测验证 `proxy-forward.js` 能把临时监听端口的数据转发到目标端口；未执行 Docker/Podman 构建，避免触发 apt/npm 安装。
- 当时结论（解释）: 方法二已经具备代码层实现，能够在 rootless Podman 下绕过容器内 iptables DNAT，把宿主机发布端口接到 Tuxler loopback 代理。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要用户重新构建镜像并按新的 AU/TR 命令启动，在目标机器上验证宿主机 `127.0.0.1:10080` 和 `10081` 是否分别返回目标国家 IP。
- 下一步计划: 向用户说明改动、验证结果和新的启动命令；如目标机验证失败，再按容器日志和转发器监听日志继续定位。

## N013 - 容器内存风险与运行上限

- branch_id: B002
- parent_node_ids: N012
- relation_type: next
- 当时问题: 当前镜像运行后会不会占用大量内存，甚至把宿主机拖死。
- 触发原因（为什么想到这个）: 用户准备并行启动多个国家实例，每个实例都会启动 Wine、Xvfb、Tuxler helper、Node、transocks 和转发器，需要确认资源上限是否可控。
- 当时假设: `--shm-size=2g` 只是 `/dev/shm` 的可用上限，不是启动时立即占用 2GB；真正风险来自没有设置容器内存上限，导致单个或多个实例在异常增长时消耗宿主机内存。
- 采取动作（做了什么实验/改了什么）: 搜索 Dockerfile、startup.sh、run.md、run.sh 和 podman.md 中的资源参数与进程启动链路，确认是否存在 `--memory`、`--memory-swap` 等硬限制。
- 观察结果（事实）: 当前启动示例普遍设置 `--shm-size="2g"`，但没有显式 `--memory` 限制；startup.sh 会启动 transocks、两个 Wine/Tuxler helper、proxy-forward 和用户传入的 `node client.js`。
- 当时结论（解释）: 单个容器不一定会立刻占用大量内存，但在没有内存上限的情况下，多国家并行或 Wine/Tuxler 异常增长时有耗尽宿主机内存的风险；应在 `podman run` 中设置内存和进程数上限。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要在目标机器上实测单实例稳定 RSS，并据此决定每个国家实例的 `--memory`、`--memory-swap` 和 `--shm-size`。
- 下一步计划: 建议用户先用 1GB 内存上限和较小 shm 试跑单实例，再通过 `podman stats` 观察并按国家数量规划总内存。

## N014 - 启动命令加资源护栏并做本地威胁扫描

- branch_id: B002
- parent_node_ids: N013
- relation_type: next
- 当时问题: 用户要求修改脚本，并追问旧 Podman 命令启动会出什么问题、是否大量占内存、镜像代码是否有病毒。
- 触发原因（为什么想到这个）: 用户的 `podman.md` 仍然保留旧的 `NET_ADMIN/sysctl/23321` 命令，与 rootless 用户态转发方案和内存护栏不一致，需要同步到可执行命令。
- 当时假设: 将 Podman 命令改为发布宿主机端口到容器内 `10080`、禁用 iptables、启用用户态转发，并加 `--memory=1g`、`--memory-swap=1g`、`--pids-limit=256`、`--shm-size=512m`，可以降低宿主机被拖死的风险。
- 采取动作（做了什么实验/改了什么）: 更新 `podman.md` 的 AU/TR 启动命令；更新 `run.md` 的 AU/TR 示例资源限制；运行 Node 和 bash 静态语法检查；记录关键文件 SHA256；用本机 Microsoft Defender 对仓库目录执行禁用自动处置的自定义扫描。
- 观察结果（事实）: `node --check proxy-forward.js`、`node --check client.js`、`bash -n startup.sh` 均通过；Defender 扫描结果为 `found no threats`；仓库仍包含闭源的 `setup.tar` 内 Windows exe 和 `transocks` 二进制，无法仅靠源码审查证明绝对安全。
- 当时结论（解释）: 新命令比旧命令更符合 rootless 安全前提，并有内存/进程上限；旧命令会继续遇到 rootless iptables DNAT 失败、宿主机端口连接重置和无内存上限风险；当前扫描未报毒但不能给出“绝对无病毒”保证。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要在目标 Linux/Podman 机器上重建镜像并用新命令启动，通过 `podman stats` 和 `curl` 同时验证资源占用和代理出口。
- 下一步计划: 向用户说明具体改动、旧命令问题、内存风险和安全扫描边界。

## N015 - Podman 启动后宿主机内存爆满与不可达事故

- branch_id: B002
- parent_node_ids: N014
- relation_type: next
- 当时问题: 用户用 Podman 启动容器后又删除了，但服务器内存爆掉并且现在连不上，需要判断为什么删除容器后宿主机仍然不可达。
- 触发原因（为什么想到这个）: 用户反馈的是实际运行事故，说明风险已经从“可能占内存”变成“宿主机资源耗尽或网络/SSH 不可用”，需要优先给恢复步骤而不是继续讨论普通启动参数。
- 当时假设: 用户很可能使用了旧命令，旧命令没有 `--memory` 和 `--pids-limit`，且会启动 Wine、Xvfb、Tuxler helper、Node 和 transocks；容器删除不一定能立刻恢复宿主机，如果系统已经进入 OOM、swap 抖动、残留 rootless Podman 进程、pod infra/slirp4netns/conmon 残留或 SSH 服务被 OOM 杀掉，就会继续不可达。
- 采取动作（做了什么实验/改了什么）: 结合当前代码启动链路、旧命令资源参数和用户反馈，形成故障恢复优先级：先通过控制台重启或查杀残留进程恢复宿主机，再查看 OOM 日志和 Podman 残留状态。
- 观察结果（事实）: 当前仓库旧命令确实没有内存硬限制，`startup.sh` 会启动多个较重进程；用户报告容器删除后服务器仍无法连接，符合宿主机 OOM 后 SSH/网络服务不可用或系统仍在资源抖动的表现。
- 当时结论（解释）: 这不一定表示容器删除失败，也可能是宿主机已经被 OOM 或 swap 压垮；短期必须走宿主机控制台/VNC/IPMI/云厂商救援模式恢复，长期必须只用带内存/PID 限制的新 rootless 命令。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要用户通过云控制台或物理控制台确认是否 OOM、是否还有 podman/conmon/slirp4netns/wine 残留进程，以及系统日志里谁被杀。
- 下一步计划: 给用户一套恢复命令和复盘命令，并提醒不要再用旧命令直接启动。

## N016 - rm 清理正确但不保证宿主机立即恢复

- branch_id: B002
- parent_node_ids: N015
- relation_type: next
- 当时问题: 用户已经执行 `podman rm -f tuxler-container-au` 和 `podman pod rm -f tuxler-pod-au`，为什么服务器仍然内存爆掉且不可达。
- 触发原因（为什么想到这个）: 用户补充了实际清理命令，说明不能简单归因于“没删容器”，需要解释清理容器和恢复已经受损的宿主机状态是两回事。
- 当时假设: `podman rm -f` 和 `podman pod rm -f` 在正常情况下会停止并删除容器和 Pod，但如果宿主机已经 OOM、SSH 被杀、swap 抖动、rootless 辅助进程残留或内核仍在回收压力中，删除命令本身不一定让系统马上恢复可连接。
- 采取动作（做了什么实验/改了什么）: 将用户补充的清理命令纳入事故判断，区分“清理容器资源”与“恢复宿主机服务和内存压力”两个阶段。
- 观察结果（事实）: 用户执行的是正确的 Podman 清理命令；此前旧启动命令没有内存/PID 上限，并启动了 Wine/Xvfb/Tuxler 等重进程；用户报告清理后仍不可达。
- 当时结论（解释）: 这两个命令不是没用，而是只能清理 Podman 对象；如果系统已经进入 OOM 或服务被杀，需要通过控制台重启/查 OOM 日志/查残留进程才能恢复和定位。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要在恢复登录后确认是否还有 `conmon`、`slirp4netns`、`wine`、`Xvfb`、`ExtensionHelper`、`transocks` 或 `node` 残留，以及 `sshd` 是否被 OOM killer 杀过。
- 下一步计划: 告诉用户清理命令的边界，并给出登录恢复后需要检查的命令。

## N017 - 当前仓库可用性仍受旧脚本影响

- branch_id: B002
- parent_node_ids: N016
- relation_type: next
- 当时问题: 用户询问当前代码是否已经没有问题，是否能正常使用和运行。
- 触发原因（为什么想到这个）: 用户需要一个最终可用性判断，而不是只看新方案局部是否通过静态检查。
- 当时假设: 新的 rootless 用户态转发链路已经在 `podman.md`、`run.md`、`startup.sh`、`proxy-forward.js` 中落地，但仓库里可能仍有旧启动脚本会误导后续使用。
- 采取动作（做了什么实验/改了什么）: 运行 `node --check proxy-forward.js`、`node --check client.js`、`bash -n startup.sh`、`bash -n run.sh`，并搜索 `privileged`、`NET_ADMIN`、`route_localnet`、`23321:23321` 等旧方案残留。
- 观察结果（事实）: 静态语法检查通过；`run.sh` 仍使用 Docker `--privileged`、`--shm-size=2g` 和大量 `23321/23322...` 直映射；`docker-compose.yml` 仍映射 `23321:23321`；`run.md` 前半部分仍保留旧 Docker/Podman 示例，后半部分和 `podman.md` 才是当前推荐方案。
- 当时结论（解释）: 不能说整个仓库完全没有问题；能推荐使用的是已经更新的 rootless Podman 多国家方案，前提是重新构建镜像并只使用新命令。旧 `run.sh`、旧 compose 和旧文档示例仍应被改造、标记弃用或避免使用。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 是否需要把 `run.sh` 和 `docker-compose.yml` 也改成 rootless 用户态转发/资源限制方案，避免误用旧入口。
- 下一步计划: 先向用户明确当前可用范围和未解决入口；如继续整理，则统一所有启动入口到新方案。

## N018 - Tuxler 提供商、住宅代理属性与免费模式风险确认

- branch_id: B002
- parent_node_ids: N017
- relation_type: next
- 当时问题: 当前代码使用的是什么 VPN/代理提供商，是否提供住宅代理，是否免费，质量如何。
- 触发原因（为什么想到这个）: 用户开始评估服务来源和代理质量，而这会影响是否继续使用该镜像以及如何控制风险。
- 当时假设: 代码中的 `HELLO TUXLER APP`、`/tuxler` WebSocket、`TUXLER_COUNTRY` 和镜像名说明提供商是 TuxlerVPN；官网信息需要核验免费、住宅代理和限制策略。
- 采取动作（做了什么实验/改了什么）: 搜索并打开 Tuxler 官方 FAQ、Windows 下载页和住宅代理说明页；同时在本地代码中搜索 Tuxler 控制命令和端口逻辑。
- 观察结果（事实）: Tuxler 官方称其使用真实住宅 IP，Windows app 页面称免费，FAQ 称免费住宅 VPN 用户会自动把自己的 IP 加入 community pool，免费用户日切换次数低于 premium；FAQ 还说明在 VPS/RDP 上不能选择住宅位置，因为本机 IP 不是住宅 IP；本项目之前容器内测试拿到 AU/Melbourne 出口。
- 当时结论（解释）: 本项目封装的是 TuxlerVPN 的 Windows helper，本质上可以导出住宅 SOCKS 代理；它存在免费模式但并非没有代价，免费住宅模式通常意味着共享自己的 IP 到网络池；质量取决于可用 IP 池、国家库存、账号限制和上游网络，不能按商业级稳定代理来预期。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 如果继续使用，需要决定是否接受社区池共享 IP 和质量不稳定风险，或改用更可控的商业住宅代理。
- 下一步计划: 向用户说明提供商、代理类型、免费代价和质量预期，并提醒不要把它当成稳定高 SLA 服务。

## N019 - 社区池共享 IP 的出口节点风险模型

- branch_id: B002
- parent_node_ids: N018
- relation_type: next
- 当时问题: Tuxler 把用户 IP 加入 community pool 到底有什么用，是否会开反向端口让外界连接本 IP 并把本 IP 当出口。
- 触发原因（为什么想到这个）: 用户开始追问免费住宅网络的底层风险，需要区分“功能上成为出口节点”和“技术上是否暴露公网入站端口”。
- 当时假设: 住宅 VPN/代理社区池通常会让客户端主动连接协调服务器或隧道服务器，再通过已建立的出站连接中转其他用户流量；这能让 NAT 后面的家庭/容器环境也参与网络，不一定需要直接开放公网反向端口。
- 采取动作（做了什么实验/改了什么）: 结合 Tuxler FAQ 中“免费住宅 VPN 会把本机 IP 加入 community pool”的说明、此前容器内外端口监听结果，以及 rootless Podman 的网络边界进行风险推断。
- 观察结果（事实）: 官方明确说免费住宅 VPN 会把你的 IP 加入社区池，并以此换取连接其他用户 IP 的能力；此前容器内只看到 Tuxler 监听 loopback 的本地控制/代理端口，没有证据显示它必须对公网开放入站端口。
- 当时结论（解释）: 功能上你的公网 IP 可能会成为其他用户访问外部网站的出口；技术上更可能是客户端主动建立出站隧道/中转连接，而不是简单在本机开一个公网端口给任意外界直连。风险仍然真实：第三方流量可能以你的 IP 出现在目标网站、风控、日志或投诉中。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 如果要继续跑，需要用网络监控确认 Tuxler 容器有哪些外联目标、带宽消耗和是否有异常监听端口。
- 下一步计划: 向用户解释“出口节点”和“开放反向端口”的区别，并给出检查监听端口和外联流量的命令。

## N020 - 中文化 Podman 说明并明确出口阻断策略

- branch_id: B002
- parent_node_ids: N019
- relation_type: next
- 当时问题: 用户看不懂 `podman.md` 的英文说明，希望改成中文，并追问如何完全限制容器内存、是否能用防火墙断掉“本公网 IP 作为目标网站出口”的链路。
- 触发原因（为什么想到这个）: 用户的核心关注点从普通运行转向可读复盘、资源上限和公网 IP 风险控制，需要把操作说明写到文档里，避免后续误用。
- 当时假设: Podman 的 `--memory`、`--memory-swap`、`--pids-limit` 可以限制容器主要进程资源，但 rootless 辅助进程仍有少量宿主机开销；如果彻底阻断 Tuxler 外联，服务大概率不可用，因为免费住宅网络需要主动外联维持社区池/隧道。
- 采取动作（做了什么实验/改了什么）: 将 `podman.md` 说明整体改为中文；补充推荐 rootless 启动链路、旧命令禁用原因、资源限制含义、检查命令、阻断公网 IP 出口的防火墙思路和清理恢复步骤。
- 观察结果（事实）: 文档明确保留 `--memory=1g`、`--memory-swap=1g`、`--pids-limit=256`、`--shm-size=512m`；文档说明如果不能接受本公网 IP 被加入社区池，最可靠做法是不运行免费住宅模式，防火墙阻断外联会让 Tuxler 很可能无法正常工作。
- 当时结论（解释）: 内存风险可以通过 cgroup 资源限制大幅收敛，但不能保证连 rootless 辅助进程和内核开销都被完全包含；公网 IP 出口风险不能在保持免费 Tuxler 正常工作的同时完全消除，除非改用 premium/商业代理/隔离网络或直接阻断运行。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 是否需要进一步把 `run.md` 和旧 `run.sh` 也统一成同样的中文安全约束，避免多个文档入口不一致。
- 下一步计划: 告知用户文档已中文化，并强调防火墙阻断与服务可用性之间的取舍。

## N021 - 将 rootless 转发设为默认启动行为

- branch_id: B002
- parent_node_ids: N020
- relation_type: next
- 当时问题: 用户希望不再手动传 `TUXLER_ENABLE_IPTABLES=0` 和 `TUXLER_FORWARD_LISTEN_PORT=10080`，默认就不创建 iptables，且转发监听端口默认是 10080。
- 触发原因（为什么想到这个）: 经过前面 rootless 安全方案确认后，这两个环境变量已经从“可选配置”变成推荐默认行为，继续要求用户手动传容易误用或漏传。
- 当时假设: `proxy-forward.js` 已经默认监听 `0.0.0.0:10080` 并转发到 `127.0.0.1:23321`；只需要把 startup.sh 的 iptables 默认值改为关闭，并从文档启动命令移除冗余环境变量。
- 采取动作（做了什么实验/改了什么）: 将 startup.sh 中 `TUXLER_ENABLE_IPTABLES` 默认值从 `1` 改为 `0`，修正跳过 iptables 的日志；从 run.md 和 podman.md 的 AU/TR 命令中删除 `TUXLER_ENABLE_IPTABLES=0` 和 `TUXLER_FORWARD_LISTEN_PORT=10080`；更新 podman.md 说明默认端口可通过环境变量覆盖。
- 观察结果（事实）: `bash -n startup.sh` 和 `node --check proxy-forward.js` 通过；搜索确认启动命令中不再需要手动传这两个变量；`proxy-forward.js` 仍保持默认端口 10080。
- 当时结论（解释）: 当前默认启动行为已经切到 rootless 用户态转发：默认不创建 iptables，默认监听容器内 10080；如需恢复旧 iptables 行为，必须显式传 `TUXLER_ENABLE_IPTABLES=1`。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要在目标 Podman 环境重新构建镜像后，用不带这两个环境变量的新命令验证代理出口。
- 下一步计划: 向用户说明默认值已改好，并给出保留/覆盖方式。

## N022 - 启动链路静态复查与 PROXY_URL 边界

- branch_id: B002
- parent_node_ids: N021
- relation_type: next
- 当时问题: 用户要求再次检查当前功能和启动命令是否正常。
- 触发原因（为什么想到这个）: 经过多轮修改后，推荐命令、默认值、转发器、旧脚本和文档存在交叉，需要重新确认实际文件状态，而不是只凭上一轮结论。
- 当时假设: rootless 用户态转发链路应该能解决宿主机访问容器内 Tuxler SOCKS 代理的问题，但默认关闭 iptables 后，原来依赖 transocks/iptables 的 `PROXY_URL` 透明转发能力不再成立。
- 采取动作（做了什么实验/改了什么）: 运行 `node --check client.js`、`node --check proxy-forward.js`、`bash -n startup.sh` 等静态检查；搜索 `--publish`、`TUXLER_ENABLE_IPTABLES`、`PROXY_URL`、`23321` 等启动关键参数；读取 startup.sh 和 proxy-forward.js 核对实际链路。
- 观察结果（事实）: 静态语法检查通过；startup.sh 默认 `TUXLER_ENABLE_IPTABLES:-0`，会跳过 iptables；proxy-forward.js 默认监听 `0.0.0.0:10080` 并转发到 `127.0.0.1:23321`；podman.md 中仍显式传了与默认值一致的 `TUXLER_ENABLE_IPTABLES=0` 和 `TUXLER_FORWARD_LISTEN_PORT=10080`；run.sh 和 docker-compose.yml 仍保留旧直映射入口。
- 当时结论（解释）: 推荐 rootless 代理出口链路静态上正常，但不能说整个仓库所有启动入口都正常；并且默认关闭 iptables 后，`PROXY_URL` 只会写入 transocks 配置，不能保证 Tuxler/Wine 外联都经过宿主机代理。如果运行环境必须依赖上游代理，仍需额外验证或重新设计出站代理策略。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要在目标 Linux/Podman 环境端到端验证两件事：宿主机 `10080` 是否能访问 Tuxler 出口，以及 Tuxler 外联是否允许直接出网或需要受控上游代理。
- 下一步计划: 向用户给出明确检查结论、可用范围和剩余风险点。

## N023 - Tuxler 连接服务器是否走 PROXY_URL 的矛盾

- branch_id: B002
- parent_node_ids: N022
- relation_type: next
- 当时问题: 用户指出如果不使用 `10.0.2.2:7880`，Tuxler 怎么连接自己的服务器；用户记得需要借助宿主机代理建立连接。
- 触发原因（为什么想到这个）: 当前默认 rootless 方案关闭了 iptables，而 `PROXY_URL` 原本只通过 transocks + iptables 透明重定向生效；这和用户“必须走代理才能连 Tuxler”的运行前提发生冲突。
- 当时假设: 如果容器所在网络可以直连 Tuxler，关闭 iptables 后仍能连接；如果不能直连，则当前默认方案可能无法让 Wine/Tuxler 外联走 `10.0.2.2:7880`，除非 Tuxler 程序自身支持并读取系统代理或另行配置 Wine/WinHTTP 代理。
- 采取动作（做了什么实验/改了什么）: 搜索 startup.sh、podman.md 和 run.md 中 `PROXY_URL`、transocks、iptables OUTPUT/REDIRECT 的关系，核对当前默认启动链路。
- 观察结果（事实）: startup.sh 总是启动 transocks 并写入 `PROXY_URL`，但只有 `TUXLER_ENABLE_IPTABLES=1` 时才会添加 `iptables -t nat -A OUTPUT ... REDIRECT --to-ports 12345`；当前推荐默认是 `TUXLER_ENABLE_IPTABLES=0`，因此 transocks 不会自动接管 Wine/Tuxler 的出站 TCP。
- 当时结论（解释）: 当前默认方案修好了宿主机访问容器内 SOCKS 出口的问题，但没有保证 Tuxler/Wine 连接服务器时一定走宿主机代理；如果目标环境必须通过 `10.0.2.2:7880` 才能连 Tuxler，需要新增非 iptables 的出站代理方案，或重新评估是否接受 rootful/iptables 透明代理。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要验证 Tuxler Windows helper 是否支持 Wine 环境下的系统代理/WinHTTP 代理，或选择外层网络代理方案。
- 下一步计划: 向用户解释当前矛盾，并列出可选修复方向：直接出网、Wine 系统代理、外层网络代理、或恢复 iptables 透明代理但牺牲 rootless 安全边界。

## N024 - 上游代理可能只用于 Tuxler bootstrap 的假设

- branch_id: B002
- parent_node_ids: N023
- relation_type: next
- 当时问题: 用户认为 `10.0.2.2:7880` 代理可能只需要用于 Tuxler 初始建连，连接建立后就不再需要持续走这个代理。
- 触发原因（为什么想到这个）: 用户补充了对 Tuxler 建连机制的理解，这会改变是否必须长期强制所有 Wine/Tuxler 出站走 `PROXY_URL` 的判断。
- 当时假设: Tuxler 可能分为 bootstrap/登录/控制通道和后续代理出口通道；在受限网络里，bootstrap 阶段可能需要宿主机代理，后续出口不一定持续依赖该代理。
- 采取动作（做了什么实验/改了什么）: 重新对照 startup.sh 的现有能力，区分“通过 transocks/iptables 长期透明代理所有 TCP”与“仅在启动早期临时代理建连”两个不同设计。
- 观察结果（事实）: 当前代码没有实现“只在初始建连阶段使用 PROXY_URL，成功后自动关闭代理”的逻辑；只有两种状态：`TUXLER_ENABLE_IPTABLES=1` 时长期透明重定向，或默认 `0` 时不透明重定向。
- 当时结论（解释）: 用户的假设有可能成立，但当前代码不能保证它；如果要采用“bootstrap-only 代理”策略，需要用日志和网络连接实测确认 Tuxler 连接成功后是否还能在关闭上游代理/断开 `10.0.2.2:7880` 后维持工作。
- 证据等级（已验证 / 观察 / 猜想）: 猜想
- 引出的下一步问题: 需要设计验证实验：启动阶段允许访问上游代理，Tuxler 显示 CONNECTED 后关闭上游代理或阻断对应连接，再观察住宅出口和 Tuxler 状态是否持续可用。
- 下一步计划: 向用户说明这个假设的合理性和当前代码缺口，并给出最小验证步骤。

## N025 - TR 容器日志显示控制链路成功但出口未最终确认

- branch_id: B002
- parent_node_ids: N024
- relation_type: next
- 当时问题: 用户贴出 TR 容器日志，询问是否已经正常连接。
- 触发原因（为什么想到这个）: 日志来自新 rootless 默认方案，需要判断 `proxy-forward`、iptables 跳过、Tuxler WebSocket 控制和最终住宅代理出口分别处于什么状态。
- 当时假设: 如果日志出现 `proxy-forward listening` 和 `~onsuccess~ ws://127.0.0.1:1701/tuxler`，说明容器入口转发和 Tuxler 控制链路已经启动；但只有看到 `CONNECTED`/`ACCOUNT_INFO` 或 curl 代理测试成功，才能确认最终代理出口可用。
- 采取动作（做了什么实验/改了什么）: 阅读用户贴出的 `podman logs -f tuxler-container-tr` 完整日志，按 startup.sh、proxy-forward.js 和 client.js 的启动顺序拆解状态。
- 观察结果（事实）: 日志显示 `Skipping iptables chain rules (TUXLER_ENABLE_IPTABLES=0)`，没有 nat 权限错误；`proxy-forward` 监听 `0.0.0.0:10080 -> 127.0.0.1:23321`；client.js 最终连接上 `ws://127.0.0.1:1701/tuxler` 并发送 `SET_PROXY` 和 `changeIPCountryCityNew` 的 TR 请求；日志末尾仍只有 `DISCONNECTED`、`NEW_TYPE`，未看到 `CONNECTED` 和 `ACCOUNT_INFO`。
- 当时结论（解释）: 新 rootless 启动链路已经部分正常，至少不再卡在端口转发和控制口连接；但还不能确认 Tuxler 已经完成 TR 出口连接，必须继续等待日志或执行宿主机 `curl --proxy socks4://127.0.0.1:10081` 验证。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要用户继续观察是否出现 `CONNECTED`，或直接用宿主机代理端口测试 `lumtest` 返回国家。
- 下一步计划: 告诉用户这是部分正常，不是最终成功，并给出下一条验证命令。

## N026 - Tuxler 账号控制链路已连上但 TR 出口仍需验证

- branch_id: B002
- parent_node_ids: N025
- relation_type: next
- 当时问题: 用户贴出 `ACCOUNT_INFO`、`LIMITS_INFO`、`YOUR_IP` 和再次发送 TR 切换命令的日志，询问是否已经连上。
- 触发原因（为什么想到这个）: 日志中首次出现账号和限制信息，说明 Tuxler helper 与 Tuxler 服务端交互已更进一步，需要区分“账号/控制链路连上”和“目标国家住宅代理出口已切换成功”。
- 当时假设: `ACCOUNT_INFO`/`LIMITS_INFO` 表示 Tuxler 应用层已连上并拿到账户状态；`YOUR_IP` 显示 China/Beijing 表示当前底层公网出口仍是中国；之后 `SET_PROXY` 和 `changeIPCountryCityNew(TR)` 才是触发切换目标国家。
- 采取动作（做了什么实验/改了什么）: 读取用户贴出的日志字段，按 client.js 中 `YOUR_IP` 触发 `setProxy` 和 `changeIPCountryCityNew` 的逻辑解释当前状态。
- 观察结果（事实）: 日志包含 `ACCOUNT_INFO`、`LIMITS_INFO`、`PREMIUM_INFO`、`RESET_INFO`、`MAC_VERSION_PORT_BLOCK`、`YOUR_IP`，其中 `isIPSharingActive:true`，`YOUR_IP` 是 China/Beijing；随后 client.js 发出 `SET_PROXY` 和 TR 切换请求。
- 当时结论（解释）: 当前可确认 Tuxler 账号/控制链路已经连上，Tuxler 能识别本机公网 IP 并接收 TR 切换命令；但仍不能仅凭这段日志确认宿主机代理端口已经输出 TR IP，最终要以 `curl --proxy socks4://127.0.0.1:10081 http://lumtest.com/myip.json` 返回 TR 为准。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要执行宿主机代理端口 curl 测试，确认出口国家是否为 TR，且资源占用是否在限制内。
- 下一步计划: 告诉用户这算 Tuxler 控制连接成功，但不是代理出口最终成功，并给出验证命令。

## N027 - 宿主机代理出口可用但目标国家未命中 TR

- branch_id: B002
- parent_node_ids: N026
- relation_type: next
- 当时问题: 用户通过宿主机 `127.0.0.1:10081` 连续 curl lumtest，出口先返回 CN/Beijing，后返回 GB/Harringay，而不是期望的 TR。
- 触发原因（为什么想到这个）: 这是第一次在新 rootless 用户态转发方案下确认宿主机代理端口实际能出网，需要区分“端口链路成功”和“目标国家选择成功”。
- 当时假设: 如果 curl 能返回 CN/GB JSON，说明 host -> podman publish -> proxy-forward -> Tuxler SOCKS 的链路已经打通；国家不为 TR 则说明 Tuxler 的 `changeIPCountryCityNew(TR)` 未稳定命中，可能是 TR 池无可用住宅 IP、切换仍在进行、免费限制/地区回退或 Tuxler 调度选择了其它可用国家。
- 采取动作（做了什么实验/改了什么）: 读取用户连续多次 curl 结果，比较国家从 CN 到 GB 的变化，并与前面日志中 TR 切换请求已发送但未看到明确 TR 成功事件的状态合并判断。
- 观察结果（事实）: 宿主机 `10081` 连续请求均成功返回 lumtest JSON；前三次为 CN/Beijing/China Networks Inter-Exchange，后两次为 GB/Harringay/Virgin Media；没有出现 TR。
- 当时结论（解释）: 新端口转发功能已经可用，容器代理服务能从宿主机访问；但当前 Tuxler 出口国家没有按 TR 生效，不能把这个实例标记为 TR 成功，只能标记为“代理可用但国家不稳定/未命中”。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要继续检查 Tuxler 日志是否有国家池/切换失败信息，或修改 client.js 增加状态日志/重试逻辑来确认 TR 是否可用。
- 下一步计划: 告诉用户当前链路成功但国家失败，并建议观察日志、等待或重试切换、检查免费账号国家池限制。

## N028 - Cloudflare 节点无法直接使用宿主机 loopback 代理

- branch_id: B002
- parent_node_ids: N027
- relation_type: next
- 当时问题: 用户询问 Cloudflare 搭建的节点中能不能使用 `socks4://127.0.0.1:10080` 这个代理。
- 触发原因（为什么想到这个）: 用户开始把本机 Podman 导出的 Tuxler 代理接入其它节点/平台，需要明确 `127.0.0.1` 的作用域，避免把本机可用误解成远端或 Cloudflare 边缘可用。
- 当时假设: `127.0.0.1:10080` 只绑定在运行 Podman 的宿主机本地 loopback；Cloudflare Worker/Pages/边缘节点或其它远端机器里的 `127.0.0.1` 指向的是它自己，不会指向用户这台 Podman 宿主机。
- 采取动作（做了什么实验/改了什么）: 基于当前 podman publish 绑定 `127.0.0.1:10080:10080` 的部署方式，分析本机进程、局域网其它机器、Cloudflare 远端节点三种访问范围。
- 观察结果（事实）: 当前推荐命令只把代理端口发布到宿主机 `127.0.0.1`；宿主机本机 curl 已经可用；未把代理暴露到局域网 IP 或公网 IP。
- 当时结论（解释）: Cloudflare 节点不能直接使用 `socks4://127.0.0.1:10080`，除非 Cloudflare 相关程序实际运行在同一台 Podman 宿主机上，或用户主动把代理监听地址改为可被该节点访问的网络地址；后者会扩大暴露面，需要鉴权和防火墙。
- 证据等级（已验证 / 观察 / 猜想）: 已验证
- 引出的下一步问题: 需要用户明确“Cloudflare 节点”具体是 Worker、Tunnel、WARP、还是本机代理客户端里的 Cloudflare 节点，以便判断是否支持上游 SOCKS。
- 下一步计划: 向用户说明不能直接用本机 loopback，并给出同机可用、局域网暴露、Cloudflare Tunnel/远端不可直接用的区别。

## N029 - 局域网另一台机器 localhost 也能访问代理的拓扑疑点

- branch_id: B002
- parent_node_ids: N028
- relation_type: next
- 当时问题: 用户在局域网另一台 Windows 机器上使用 `socks4://127.0.0.1:10080` 和 `socks4://192.168.1.9:10080` 都能访问 AU 出口，询问为什么 localhost 也可以。
- 触发原因（为什么想到这个）: 这与前面“127.0.0.1 只表示当前机器本机”的网络基本规则冲突，说明实际拓扑里可能有本机转发、代理客户端、端口映射或命令运行位置误判。
- 当时假设: 如果这确实是另一台机器，则 `127.0.0.1:10080` 能通只能说明那台 Windows 机器本地也有进程监听 10080 并转发到 Podman 宿主机或同一个 Tuxler 出口；另一种可能是命令实际运行在 Podman 宿主机/WSL/远程终端里，而不是物理上的另一台机器。
- 采取动作（做了什么实验/改了什么）: 根据用户提供的 curl 输出和当前 Podman publish 绑定语义，重新判断 localhost 与 LAN IP 同时可用的原因范围。
- 观察结果（事实）: 两个 curl 都返回同一个 AU/Brisbane/TPG Telecom Limited 出口；`192.168.1.9:10080` 可用说明宿主机或某层网络已经把代理暴露到了局域网；`127.0.0.1:10080` 可用说明执行 curl 的那台机器本地也存在可用代理或端口转发。
- 当时结论（解释）: `127.0.0.1` 不会跨机器指向 `192.168.1.9`；该现象不是网络规则例外，而是存在本地监听/转发/代理软件，或用户执行环境其实就在代理宿主机上。需要用 `netstat`/`Get-NetTCPConnection` 找出 Windows 本地 10080 的监听进程。
- 证据等级（已验证 / 观察 / 猜想）: 观察
- 引出的下一步问题: 需要在那台 Windows 机器上确认 10080 的监听进程、是否有 Clash/mihomo/v2rayN/ssh tunnel/netsh portproxy/Cloudflare WARP 等本地转发。
- 下一步计划: 给用户解释 localhost 作用域，并提供 Windows 侧定位监听进程和端口转发的命令。
