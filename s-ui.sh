#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

# Check OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "$ID" != "alpine" ]]; then
        echo -e "${red}This script is only for Alpine Linux!${plain}"
        exit 1
    fi
else
    echo "Failed to check the system OS." >&2
    exit 1
fi

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;; 
    i*86 | x86) echo '386' ;; 
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;; 
    armv7* | armv7 | arm) echo 'armv7' ;; 
    armv6* | armv6) echo 'armv6' ;; 
    armv5* | armv5) echo 'armv5' ;; 
    s390x) echo 's390x' ;; 
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && exit 1 ;; 
    esac
}

echo "OS: Alpine"
echo "arch: $(arch)"

install_base() {
    echo -e "${green}Installing base dependencies (wget, curl, tar, tzdata)...${plain}"
    apk add --no-cache --update wget curl tar tzdata bash
}

config_after_install() {
    echo -e "${yellow}Migration... ${plain}"
    /usr/local/s-ui/sui migrate
    
    echo -e "${yellow}Install/update finished! For security it's recommended to modify panel settings ${plain}"
    read -p "Do you want to continue with the modification [y/n]? " config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        echo -e "Enter the ${yellow}panel port${plain} (leave blank for existing/default value):"
        read config_port
        echo -e "Enter the ${yellow}panel path${plain} (leave blank for existing/default value):"
        read config_path

        # Sub configuration
        echo -e "Enter the ${yellow}subscription port${plain} (leave blank for existing/default value):"
        read config_subPort
        echo -e "Enter the ${yellow}subscription path${plain} (leave blank for existing/default value):" 
        read config_subPath

        # Set configs
        echo -e "${yellow}Initializing, please wait...${plain}"
        params=""
        [ -z "$config_port" ] || params="$params -port $config_port"
        [ -z "$config_path" ] || params="$params -path $config_path"
        [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
        [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
        /usr/local/s-ui/sui setting ${params}

        read -p "Do you want to change admin credentials [y/n]? " admin_confirm
        if [[ "${admin_confirm}" == "y" || "${admin_confirm}" == "Y" ]]; then
            # First admin credentials
            read -p "Please set up your username:" config_account
            read -p "Please set up your password:" config_password

            # Set credentials
            echo -e "${yellow}Initializing, please wait...${plain}"
            /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
        else
            echo -e "${yellow}Your current admin credentials: ${plain}"
            /usr/local/s-ui/sui admin -show
        fi
    else
        echo -e "${red}cancel...${plain}"
        if [[ ! -f "/usr/local/s-ui/db/s-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            echo -e "this is a fresh installation,will generate random login info for security concerns:"
            echo -e "###############################################"
            echo -e "${green}username:${usernameTemp}${plain}"
            echo -e "${green}password:${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}if you forgot your login info,you can type ${green}s-ui${red} for configuration menu${plain}"
            /usr/local/s-ui/sui admin -username ${usernameTemp} -password ${passwordTemp}
        else
            echo -e "${red} this is your upgrade,will keep old settings,if you forgot your login info,you can type ${green}s-ui${red} for configuration menu${plain}"
        fi
    fi
}

create_init_script() {
    cat > /etc/init.d/s-ui <<-"EOF"
#!/sbin/openrc-run

command="/usr/glibc/bin/glibc-ld.so"
command_args="/usr/local/s-ui/sui"
command_user="root"

pidfile="/var/run/s-ui.pid"

name="s-ui"
description="s-ui panel"

depend() {
    need net
}

start() {
    start-stop-daemon --start --quiet --pidfile "\$pidfile" --exec "\$command" \
        --background --make-pidfile -- \$command_args
}

stop() {
    start-stop-daemon --stop --quiet --pidfile "\$pidfile"
}
EOF
    chmod +x /etc/init.d/s-ui
}

install_glibc() {
    echo "正在准备 glibc 安装修复环境..."

    # 1. 删除 /etc/nsswitch.conf（防止冲突）
    rm -f /etc/nsswitch.conf

    # 2. 下载 sgerrand 的公钥
    curl -Lo /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub

    # 3. 下载指定版本的 glibc 包
    GLIBC_VER="2.34-r0"
    curl -Lo glibc-${GLIBC_VER}.apk https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/glibc-${GLIBC_VER}.apk

    # 4. 安装 glibc，允许覆盖
    apk add --allow-untrusted --force-overwrite glibc-${GLIBC_VER}.apk

    rm glibc-${GLIBC_VER}.apk

    echo "glibc ${GLIBC_VER} 安装完成"

    if [ ! -f /usr/glibc/bin/glibc-ld.so ]; then
        echo -e "${red}错误：glibc loader 未在 /usr/glibc/bin/glibc-ld.so 找到！${plain}"
        echo -e "${red}s-ui 服务可能无法启动。${plain}"
    else
        echo -e "${green}glibc loader 在 /usr/glibc/bin/glibc-ld.so 找到。${plain}"
    fi
}

install_s-ui() {
    cd /tmp/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/alireza0/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to fetch s-ui version, it maybe due to Github API restrictions, please try it later${plain}"
            exit 1
        fi
        echo -e "Got s-ui latest version: ${last_version}, beginning the installation..."
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading s-ui failed, please be sure that your server can access Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"
        echo -e "Beginning the install s-ui v$1"
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}download s-ui v$1 failed,please check the version exists${plain}"
            exit 1
        fi
    fi

    if [ -f /etc/init.d/s-ui ]; then
        rc-service s-ui stop
        rc-update del s-ui default
    fi

    tar zxvf s-ui-linux-$(arch).tar.gz
    rm s-ui-linux-$(arch).tar.gz -f

    chmod +x s-ui/sui s-ui/s-ui.sh
    cp s-ui/s-ui.sh /usr/bin/s-ui
    cp -rf s-ui /usr/local/
    rm -rf s-ui
    
    create_init_script

    config_after_install

    rc-update add s-ui default
    rc-service s-ui start

    echo -e "${green}s-ui v${last_version}${plain} installation finished, it is up and running now..."
    echo -e "You may access the Panel with following URL(s):${green}"
    /usr/local/s-ui/sui uri
    echo -e "${plain}"
    echo -e ""
    s-ui help
}

echo -e "${green}Executing...${plain}"
install_base
install_glibc
install_s-ui $1
