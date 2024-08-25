#!/bin/bash

# 默认配置
NZ_BASE_PATH="/usr/local/src"
NZ_AGENT_PATH="${NZ_BASE_PATH}/sysctl"
NZ_VERSION="v0.19.1-1"
NZ_GRPC_HOST="your-domain.com"
NZ_GRPC_PORT=5555
NZ_CLIENT_SECRET="your-secret"
USE_CHINA_MIRROR=false

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

geo_check() {
    local api_list="https://blog.cloudflare.com/cdn-cgi/trace https://dash.cloudflare.com/cdn-cgi/trace https://cf-ns.com/cdn-cgi/trace"
    local ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    local isCN=false

    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s $url)"
        endpoint="$(echo $text | sed -n 's/.*h=\([^ ]*\).*/\1/p')"
        if echo $text | grep -qw 'CN'; then
            isCN=true
            break
        elif echo $url | grep -q $endpoint; then
            break
        fi
    done

    if [ "$isCN" = true ]; then
        USE_CHINA_MIRROR=true
        echo "Detected China region. Using China mirror."
    else
        USE_CHINA_MIRROR=false
        echo "Not detected in China region. Using default mirror."
    fi
}

if [ "$#" -eq 3 ]; then
    NZ_GRPC_HOST="$1"
    NZ_GRPC_PORT="$2"
    NZ_CLIENT_SECRET="$3"
elif [ "$#" -ne 0 ]; then
    echo "Usage: $0 [<grpc-host> <grpc-port> <client-secret>]"
    exit 1
fi

geo_check

os_arch=$(uname -m)
case $os_arch in
    x86_64) os_arch="amd64" ;;
    i386|i686) os_arch="386" ;;
    aarch64|armv8b|armv8l) os_arch="arm64" ;;
    arm) os_arch="arm" ;;
    s390x) os_arch="s390x" ;;
    riscv64) os_arch="riscv64" ;;
    *) echo "Unsupported architecture"; exit 1 ;;
esac

if [ "$USE_CHINA_MIRROR" = true ]; then
    GITHUB_RAW_URL="github.geekery.cn/raw.githubusercontent.com/Paper-Dragon/nezha/new-world"
    GITHUB_URL="github.geekery.cn/github.com"
else
    GITHUB_RAW_URL="raw.githubusercontent.com/Paper-Dragon/nezha/raw/new-world"
    GITHUB_URL="github.com"
fi

install_base() {
    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y curl wget unzip
    elif command -v yum >/dev/null 2>&1; then
        sudo yum makecache && sudo yum install -y curl wget unzip
    else
        echo "${red}Unsupported package manager. Install curl, wget, and unzip manually.${plain}"
        exit 1
    fi
}

selinux() {
    if command -v getenforce >/dev/null 2>&1 && getenforce | grep -qi 'enfor'; then
        echo "Disabling SELinux"
        sudo setenforce 0
        sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    fi
}

install_agent() {
    install_base
    selinux

    echo "> Installing Nezha Agent"

    sudo mkdir -p $NZ_AGENT_PATH
    sudo chmod -R 700 $NZ_AGENT_PATH

    NZ_AGENT_URL="https://${GITHUB_URL}/Paper-Dragon/agent/releases/download/${NZ_VERSION}/nezha-agent_linux_${os_arch}.zip"

    wget -t 2 -T 60 -O nezha-agent_linux_${os_arch}.zip ${NZ_AGENT_URL} && \
    sudo unzip -qo nezha-agent_linux_${os_arch}.zip -d $NZ_AGENT_PATH && \
    sudo rm -f nezha-agent_linux_${os_arch}.zip
    sudo mv nezha-agent sysctl-init

    sudo ${NZ_AGENT_PATH}/sysctl-init service install -s "$NZ_GRPC_HOST:$NZ_GRPC_PORT" -p $NZ_CLIENT_SECRET

    echo "${green}Sysctl Init installed and configured successfully.${plain}"
}

# 执行安装
install_agent
