#!/bin/sh

#========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ / Alpine 3+ /
#   Description: 哪吒监控Agent安装脚本
#========================================================

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_VERSION="v0.18.3"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

os_arch=""
[ -e /etc/os-release ] && grep -i "PRETTY_NAME" /etc/os-release | grep -qi "alpine" && os_alpine='1'

sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "错误: 您的系统未安装 sudo，因此无法进行该项操作。"
            exit 1
        fi
    else
        "$@"
    fi
}


err() {
    printf "${red}$*${plain}\n" >&2
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://dash.cloudflare.com/cdn-cgi/trace https://cf-ns.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (X11; Linux x86_64; rv:60.0) Gecko/20100101 Firefox/81.0"
    set -- $api_list
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
}

pre_check() {
    ## os_arch
    if uname -m | grep -q 'x86_64'; then
        os_arch="amd64"
    elif uname -m | grep -q 'i386\|i686'; then
        os_arch="386"
    elif uname -m | grep -q 'aarch64\|armv8b\|armv8l'; then
        os_arch="arm64"
    elif uname -m | grep -q 'arm'; then
        os_arch="arm"
    elif uname -m | grep -q 's390x'; then
        os_arch="s390x"
    elif uname -m | grep -q 'riscv64'; then
        os_arch="riscv64"
    fi

    ## China_IP
    if [ -z "$CN" ]; then
        geo_check
        if [ ! -z "$isCN" ]; then
            echo "根据geoip api提供的信息，当前IP可能在中国"
            printf "是否选用中国镜像完成安装? [Y/n] :"
            read -r input
            case $input in
            [yY][eE][sS] | [yY])
                echo "使用中国镜像"
                CN=true
                ;;

            [nN][oO] | [nN])
                echo "不使用中国镜像"
                ;;

            *)
                echo "使用中国镜像"
                CN=true
                ;;
            esac
        fi
    fi

    if [ -z "$CN" ]; then
        GITHUB_RAW_URL="github.geekery.cn/raw.githubusercontent.com/naiba/nezha/master"
        GITHUB_URL="github.geekery.cn/github.com"
    else
        GITHUB_RAW_URL="raw.githubusercontent.com/naibahq/nezha/raw/master"
        GITHUB_URL="github.com"
    fi
}

update_script() {
    echo "> 更新脚本"

    curl -sL https://${GITHUB_RAW_URL}/script/install.sh -o /tmp/nezha.sh
    new_version=$(grep "NZ_VERSION" /tmp/nezha.sh | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo "脚本获取失败，请检查本机能否链接 https://${GITHUB_RAW_URL}/script/install.sh"
        return 1
    fi
    echo "当前最新版本为: ${new_version}"
    mv -f /tmp/nezha.sh ./nezha.sh && chmod a+x ./nezha.sh

    echo "3s后执行新脚本"
    sleep 3s
    clear
    exec ./nezha.sh
    exit 0
}

before_show_menu() {
    echo && printf "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1) ||
        (install_soft curl wget unzip)
}

install_arch() {
    printf "${green}提示: ${plain} Arch安装libselinux需添加nezha-agent用户，安装完会自动删除，建议手动检查一次\n"
    read -r -p "是否安装libselinux? [Y/n] " input
    case $input in
    [yY][eE][sS] | [yY])
        useradd -m nezha-agent
        sed -i "$ a\nezha-agent ALL=(ALL ) NOPASSWD:ALL" /etc/sudoers
        sudo -iu nezha-agent bash -c 'gpg --keyserver keys.gnupg.net --recv-keys 4695881C254508D1;
                                        cd /tmp; git clone https://aur.archlinux.org/libsepol.git; cd libsepol; makepkg -si --noconfirm --asdeps; cd ..;
                                        git clone https://aur.archlinux.org/libselinux.git; cd libselinux; makepkg -si --noconfirm; cd ..;
                                        rm -rf libsepol libselinux'
        sed -i '/nezha-agent/d' /etc/sudoers && sleep 30s && killall -u nezha-agent && userdel -r nezha-agent
        echo -e "${red}提示: ${plain}已删除用户nezha-agent，请务必手动核查一遍！\n"
        ;;
    [nN][oO] | [nN])
        echo "不安装libselinux"
        ;;
    *)
        echo "不安装libselinux"
        exit 0
        ;;
    esac
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && sudo yum makecache && sudo yum install $* selinux-policy -y) ||
        (command -v apt >/dev/null 2>&1 && sudo apt update && sudo apt install $* selinux-utils -y) ||
        (command -v pacman >/dev/null 2>&1 && sudo pacman -Syu $* base-devel --noconfirm && install_arch) ||
        (command -v apt-get >/dev/null 2>&1 && sudo apt-get update && sudo apt-get install $* selinux-utils -y) ||
        (command -v apk >/dev/null 2>&1 && sudo apk update && sudo apk add $* -f)
}

selinux() {
    #判断当前的状态
    command -v getenforce >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        getenforce | grep '[Ee]nfor'
        if [ $? -eq 0 ]; then
            echo "SELinux是开启状态，正在关闭！"
            sudo setenforce 0 &>/dev/null
            find_key="SELINUX="
            sudo sed -ri "/^$find_key/c${find_key}disabled" /etc/selinux/config
        fi
    fi
}

install_agent() {
    pre_check
    install_base
    selinux

    echo "> 安装监控Agent"


    # 哪吒监控文件夹
    sudo mkdir -p $NZ_AGENT_PATH
    sudo chmod -R 700 $NZ_AGENT_PATH

    echo "正在下载监控端"

    NZ_AGENT_URL="https://${GITHUB_URL}/naibahq/agent/releases/download/${NZ_VERSION}/nezha-agent_linux_${os_arch}.zip"

    wget -t 2 -T 60 -O nezha-agent_linux_${os_arch}.zip ${NZ_AGENT_URL} >/dev/null 2>&1
    if [ $? != 0 ]; then
        err "Release 下载失败，请检查本机能否连接 ${NZ_AGENT_URL}"
        return 1
    fi

    sudo unzip -qo nezha-agent_linux_${os_arch}.zip &&
        sudo mv nezha-agent $NZ_AGENT_PATH &&
        sudo rm -rf nezha-agent_linux_${os_arch}.zip README.md

    if [ $# -ge 3 ]; then
        modify_agent_config "$@"
    else
        modify_agent_config 0
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

modify_agent_config() {
    echo "> 修改Agent配置"

    if [ $# -lt 3 ]; then
        echo "请先在管理面板上添加Agent，记录下密钥"
            printf "请输入一个解析到面板所在IP的域名（不可套CDN）: "
            read -r nz_grpc_host
            printf "请输入面板RPC端口 (默认值 5555): "
            read -r nz_grpc_port
            printf "请输入Agent 密钥: "
            read -r nz_client_secret
            printf "是否启用针对 gRPC 端口的 SSL/TLS加密 (--tls)，需要请按 [y]，默认是不需要，不理解用户可回车跳过: "
            read -r nz_grpc_proxy
        echo "${nz_grpc_proxy}" | grep -qiw 'Y' && args='--tls'
        if [ -z "$nz_grpc_host" ] || [ -z "$nz_client_secret" ]; then
            err "所有选项都不能为空"
            before_show_menu
            return 1
        fi
        if [ -z "$nz_grpc_port" ]; then
            nz_grpc_port=5555
        fi
    else
        nz_grpc_host=$1
        nz_grpc_port=$2
        nz_client_secret=$3
        shift 3
        if [ $# -gt 0 ]; then
            args="$*"
        fi
    fi

    sudo ${NZ_AGENT_PATH}/nezha-agent service install -s "$nz_grpc_host:$nz_grpc_port" -p $nz_client_secret $args >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        sudo ${NZ_AGENT_PATH}/nezha-agent service uninstall >/dev/null 2>&1
        sudo ${NZ_AGENT_PATH}/nezha-agent service install -s "$nz_grpc_host:$nz_grpc_port" -p $nz_client_secret $args >/dev/null 2>&1
    fi
    
    printf "Agent配置 ${green}修改成功，请稍等重启生效${plain}\n"
}

show_agent_log() {
    echo "> 获取Agent日志"

    if [ "$os_alpine" != 1 ]; then
        sudo journalctl -xf -u nezha-agent.service
    else
        sudo tail -n 10 /var/log/nezha-agent.err
    fi

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

uninstall_agent() {
    echo "> 卸载Agent"

    sudo ${NZ_AGENT_PATH}/nezha-agent service uninstall

    sudo rm -rf $NZ_AGENT_PATH
    clean_all

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

restart_agent() {
    echo "> 重启Agent"

    sudo ${NZ_AGENT_PATH}/nezha-agent service restart

    if [ $# = 0 ]; then
        before_show_menu
    fi
}

clean_all() {
    if [ -z "$(ls -A ${NZ_BASE_PATH})" ]; then
        sudo rm -rf ${NZ_BASE_PATH}
    fi
}

show_usage() {
    echo "哪吒监控 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "./nezha.sh                            - 显示管理菜单"
    echo "--------------------------------------------------------"
    echo "./nezha.sh install_agent              - 安装监控Agent"
    echo "./nezha.sh modify_agent_config        - 修改Agent配置"
    echo "./nezha.sh show_agent_log             - 查看Agent日志"
    echo "./nezha.sh uninstall_agent            - 卸载Agen"
    echo "./nezha.sh restart_agent              - 重启Agen"
    echo "./nezha.sh update_script              - 更新脚本"
    echo "--------------------------------------------------------"
}

show_menu() {
    printf "
    ${green}哪吒监控管理脚本${plain} ${red}${NZ_VERSION}${plain}
    ————————————————-
    ${green}8.${plain}  安装监控Agent
    ${green}9.${plain}  修改Agent配置
    ${green}10.${plain} 查看Agent日志
    ${green}11.${plain} 卸载Agent
    ${green}12.${plain} 重启Agent
    ————————————————-
    ${green}13.${plain} 更新脚本
    ————————————————-
    ${green}0.${plain}  退出脚本
    "
    echo && printf "请输入选择 [0,8-13]: " && read -r num
    case "${num}" in
        0)
            exit 0
            ;;
        8)
            install_agent
            ;;
        9)
            modify_agent_config
            ;;
        10)
            show_agent_log
            ;;
        11)
            uninstall_agent
            ;;
        12)
            restart_agent
            ;;
        13)
            update_script
            ;;
        *)
            err "请输入正确的数字 [0,8-13]"
            ;;
    esac
}

pre_check

if [ $# -gt 0 ]; then
    case $1 in
        "install_agent")
            shift
            if [ $# -ge 3 ]; then
                install_agent "$@"
            else
                install_agent 0
            fi
            ;;
        "modify_agent_config")
            modify_agent_config 0
            ;;
        "show_agent_log")
            show_agent_log 0
            ;;
        "uninstall_agent")
            uninstall_agent 0
            ;;
        "restart_agent")
            restart_agent 0
            ;;
        "update_script")
            update_script 0
            ;;
        *) show_usage ;;
    esac
else
    show_menu
fi
