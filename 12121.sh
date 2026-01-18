#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Config
COMMENT="日本3"                                          # 中文备注
CFZONE_NAMES=("345686.cc")                    # Cloudflare DNS Zone Names
CFRECORD_NAMES=("jp3")                              # 域名前缀
NODE_ID_1=52                                              # 节点id
CFKEY="ab0d638bb9645a0aa5f134ec9988734d741ab"             # Cloudflare API Key
CFUSER="phungduyla@gmail.com"                                 # Cloudflare Account Email
CFTTL=1                                                    # TTL (Time to Live)
FORCE=false                                                # Force update flag
WANIPSITE="http://ipv4.icanhazip.com"                      # WAN IP source site

# Check if a command exists, if not, install it
check_and_install() {
    command -v "$1" &> /dev/null || {
        echo "$1 not found, installing..."
        sudo apt-get install -y "$1"
    }
}

# Install necessary tools (curl, sudo, unzip, etc.)
install_dependencies() {
    echo "### 检查并安装依赖工具 ###"
    check_and_install "curl"
    check_and_install "sudo"
    check_and_install "unzip"
    check_and_install "apt-transport-https"
    check_and_install "gnupg"
    check_and_install "lsb-release"
}

# Function to get WAN IP
get_wan_ip() {
    WAN_IP=$(curl -s ${WANIPSITE})
    if [[ -z "${WAN_IP}" ]]; then
        echo "Error: Unable to retrieve WAN IP."
        exit 1
    else
        echo "WAN IP: ${WAN_IP}"
    fi
}

# Function to check if DNS record exists
check_dns_record() {
    local ZONE_NAME="${1}"
    local RECORD_NAME="${2}"

    # Get zone_identifier
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" -H "X-Auth-Email: ${CFUSER}" -H "X-Auth-Key: ${CFKEY}" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )

    # Check if record exists
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CFZONE_ID}/dns_records?name=${RECORD_NAME}.${ZONE_NAME}" -H "X-Auth-Email: ${CFUSER}" -H "X-Auth-Key: ${CFKEY}" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )

    if [[ -z "${CFRECORD_ID}" ]]; then
        return 1  # Record does not exist
    else
        return 0  # Record exists
    fi
}

# Function to create a new DNS record
create_dns_record() {
    local ZONE_NAME="${1}"
    local RECORD_NAME="${2}"

    # Get zone_identifier
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" -H "X-Auth-Email: ${CFUSER}" -H "X-Auth-Key: ${CFKEY}" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )

    # Create DNS record
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CFZONE_ID}/dns_records" \
      -H "X-Auth-Email: ${CFUSER}" \
      -H "X-Auth-Key: ${CFKEY}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${WAN_IP}\",\"ttl\":${CFTTL},\"proxied\":false,\"comment\":\"${COMMENT}\"}")

    # Check if creation was successful
    if [[ "${RESPONSE}" == *'"success":true'* ]]; then
        echo "Created DNS record for ${RECORD_NAME}.${ZONE_NAME} with IP ${WAN_IP} and comment '${COMMENT}'"
    else
        echo "Failed to create DNS record for ${RECORD_NAME}.${ZONE_NAME}"
        echo "Response: ${RESPONSE}"
    fi
}

# Function to update DNS record
update_dns_record() {
    local ZONE_NAME="${1}"
    local RECORD_NAME="${2}"

    # Get zone_identifier & record_identifier
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" -H "X-Auth-Email: ${CFUSER}" -H "X-Auth-Key: ${CFKEY}" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CFZONE_ID}/dns_records?name=${RECORD_NAME}.${ZONE_NAME}" -H "X-Auth-Email: ${CFUSER}" -H "X-Auth-Key: ${CFKEY}" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )

    # Update DNS record
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CFZONE_ID}/dns_records/${CFRECORD_ID}" \
      -H "X-Auth-Email: ${CFUSER}" \
      -H "X-Auth-Key: ${CFKEY}" \
      -H "Content-Type: application/json" \
      --data "{\"id\":\"${CFZONE_ID}\",\"type\":\"A\",\"name\":\"${RECORD_NAME}\",\"content\":\"${WAN_IP}\",\"ttl\":${CFTTL},\"proxied\":false,\"comment\":\"${COMMENT}\"}")

    # Check if the update was successful
    if [[ "${RESPONSE}" != *'"success":false'* ]]; then
        echo "Updated DNS for ${RECORD_NAME}.${ZONE_NAME} to ${WAN_IP} with comment '${COMMENT}'"
    else
        echo "Failed to update DNS for ${RECORD_NAME}.${ZONE_NAME}"
        echo "Response: ${RESPONSE}"
    fi
}

# Install Docker (for Debian or Ubuntu)
function install_docker(){
    echo "### 安装 Docker ###"
    DISTRO=$(lsb_release -is)

    if [[ "$DISTRO" == "Ubuntu" ]]; then
        echo "检测到 Ubuntu 系统，安装 Docker..."
        sudo apt-get update -y
        sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update -y
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    elif [[ "$DISTRO" == "Debian" ]]; then
        DEBIAN_VERSION=$(lsb_release -rs)

        # 对 Debian 13 使用特定的 Docker 安装步骤
        if [[ "$DEBIAN_VERSION" == "13" ]]; then
            echo "检测到 Debian 13 系统，使用特殊安装方法安装 Docker..."
            sudo apt update
            sudo apt install -y ca-certificates curl gnupg lsb-release

            # 安装 Docker GPG key 和源列表
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg | \
            sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/debian bookworm stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

            sudo apt update
            sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        else
            echo "检测到其他 Debian 版本，安装 Docker..."
            sudo apt update -y
            sudo apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
            curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
            sudo apt update -y
            sudo apt install -y docker-ce docker-ce-cli containerd.io
        fi
    else
        echo "不支持的系统类型: $DISTRO"
        exit 1
    fi

    # 启动并设置 Docker 服务为开机自启
    sudo systemctl enable --now docker
    echo "Docker 安装完成，服务已启动并设置为开机自启。"
}

# Start v2ray backend setup
function v2ray(){
    echo "### 安装 v2ray 后端 ###"
    sysctl -p /etc/sysctl.conf

    # Install dependencies
    install_dependencies

    # Install Docker
    install_docker

    docker run --restart=always --name f1 -d \
    -v /etc/soga/:/etc/soga/ --network host \
    -e type=xiaov2board \
    -e server_type=ss \
    -e node_id=${NODE_ID_1} \
    -e soga_key=69QBm4gue2atGRO2XsWT9aOR0yfYaJRr \
    -e api=webapi \
    -e webapi_url=https://www.345686.cc/ \
    -e webapi_key=cFdYIpphU37DnxQXMgCa \
    -e proxy_protocol=true \
    -e tunnel_proxy_protocol=true \
    -e udp_proxy_protocol=true \
    -e redis_enable=true \
    -e redis_addr=ip.dlbtizi.net:1357 \
    -e redis_password=damai \
    -e redis_db=1 \
    -e conn_limit_expiry=60 \
    -e user_conn_limit=4 \
    vaxilu/soga:2.12.7

    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p

    echo "安装完成"
}

# Main loop for Cloudflare DNS records update
for i in "${!CFZONE_NAMES[@]}"; do
    ZONE_NAME="${CFZONE_NAMES[$i]}"
    RECORD_NAME="${CFRECORD_NAMES[$i]}"

    # Get current WAN IP
    get_wan_ip

    # Check if DNS record exists
    if check_dns_record "${ZONE_NAME}" "${RECORD_NAME}"; then
        echo "DNS record for ${RECORD_NAME}.${ZONE_NAME} exists, updating..."
        update_dns_record "${ZONE_NAME}" "${RECORD_NAME}"
    else
        echo "DNS record for ${RECORD_NAME}.${ZONE_NAME} does not exist, creating..."
        create_dns_record "${ZONE_NAME}" "${RECORD_NAME}"
    fi
done

# Call v2ray setup
v2ray
