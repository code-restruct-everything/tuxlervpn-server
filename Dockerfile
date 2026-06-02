FROM ubuntu:20.04

LABEL maintainer="Florin <florin@carcabot.ro>"
LABEL name="docker-tuxlervpn-server"
LABEL version="latest"

# 增加非交互式环境变量，防止 Ubuntu 20.04 安装 tzdata 等服务时弹出时区选择卡死构建
ENV DEBIAN_FRONTEND=noninteractive

# 1. 替换为阿里云 Ubuntu APT 软件源以加速下载
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

# set ENV
ENV DISPLAY :0

# Install wget
RUN apt-get update
RUN apt-get install -y wget

# Add 32-bit architecture
RUN dpkg --add-architecture i386
RUN apt-get update

# Install Wine
RUN apt-get install -y software-properties-common gnupg2
# 2. 将 WineHQ 官方源替换为清华大学开源软件镜像源以加速下载
RUN wget -nc https://mirrors.tuna.tsinghua.edu.cn/winehq/wine-builds/winehq.key
RUN apt-key add winehq.key
# 将 Ubuntu 版本代号由 18.04 的 bionic 修改为 20.04 的 focal
RUN apt-add-repository 'deb https://mirrors.tuna.tsinghua.edu.cn/winehq/wine-builds/ubuntu/ focal main'
# 注：Ubuntu 20.04 已经原生包含现代版 SDL2，无需再从 PPA 安装 'ppa:cybermax-dexter/sdl2-backport'
RUN apt-get install -y --install-recommends winehq-stable winbind iptables xvfb
# DEBUG
RUN apt-get install -y net-tools curl npm nano
# 3. 将 NPM 官方源替换为淘宝/腾讯 NPM 镜像源以加速依赖包下载
RUN npm config set registry https://registry.npmmirror.com && npm i ws

# Install Xvfb
RUN apt-get update

# Turn off Fixme warnings
ENV WINEDEBUG=fixme-all

# Setup Wine prefix
ENV WINEPREFIX=/root/.demo
ENV WINEARCH=win64
RUN winecfg

COPY setup.tar .
COPY startup.sh /usr/local/bin/entrypoint.sh
COPY transocks /usr/local/bin/transocks
COPY client.js .

RUN chmod +x /usr/local/bin/entrypoint.sh && tar -xvf setup.tar

# Run application
ENTRYPOINT ["/bin/bash", "entrypoint.sh"]