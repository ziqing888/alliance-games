#!/bin/bash

# 定义颜色代码
INFO='\033[0;36m'  # 青色
WARNING='\033[0;33m'  # 警告黄色
ERROR='\033[0;31m'  # 错误红色
SUCCESS='\033[0;32m'  # 成功绿色
MENU_COLOR='\033[0;34m'  # 蓝色
BOLD='\033[1m'  # 加粗
NC='\033[0m'  # 无颜色

# 显示横幅
echo -e "${MENU_COLOR}${BOLD}==============================================${NC}"
echo -e "${MENU_COLOR}${BOLD}      联盟游戏 Docker 安装脚本                  ${NC}"
echo -e "${MENU_COLOR}${BOLD}      由 子清 提供 @qklxsqf                     ${NC}"
echo -e "${MENU_COLOR}${BOLD}==============================================${NC}"

# 确保输入非空的函数
get_non_empty_input() {
    local prompt="$1"
    local input=""
    while [ -z "$input" ]; do
        read -p "$prompt" input
        if [ -z "$input" ]; then
            echo -e "${ERROR}[ERROR] 此字段不能为空。${NC}"
        fi
    done
    echo "$input"
}

# 生成随机 MAC 地址的函数
generate_mac_address() {
    echo "02:$(od -An -N5 -tx1 /dev/urandom | tr ' ' ':' | cut -c2-)"
}

# 为伪造的 product_uuid 生成 UUID 的函数
generate_uuid() {
    uuid=$(cat /proc/sys/kernel/random/uuid)
    echo $uuid
}

# 获取并验证参数
device_name=$(get_non_empty_input "输入设备名称：")

# 创建配置目录
device_dir="./$device_name"
if [ ! -d "$device_dir" ]; then
    mkdir "$device_dir"
    echo -e "${INFO}[INFO] 已为 $device_name 创建目录：$device_dir${NC}"
fi

# 代理配置
read -p "是否使用代理？(Y/N): " use_proxy

proxy_type=""
proxy_ip=""
proxy_port=""
proxy_username=""
proxy_password=""

if [[ "$use_proxy" == "Y" || "$use_proxy" == "y" ]]; then
    read -p "输入代理类型 (http/socks5): " proxy_type
    read -p "输入代理 IP： " proxy_ip
    read -p "输入代理端口： " proxy_port
    read -p "输入代理用户名 (如果不需要可留空)： " proxy_username
    read -p "输入代理密码 (如果不需要可留空)： " proxy_password
    if [[ "$proxy_type" == "http" ]]; then
        proxy_type="http-connect"
    fi
fi

# 创建 Dockerfile
echo -e "${INFO}[INFO] 正在创建 Dockerfile...${NC}"
cat << 'EOL' > "$device_dir/Dockerfile"
FROM ubuntu:latest
WORKDIR /app
RUN apt-get update && apt-get install -y bash curl jq make gcc bzip2 lbzip2 vim git lz4 telnet build-essential net-tools wget tcpdump systemd dbus redsocks iptables iproute2 nano
RUN curl -L https://github.com/Impa-Ventures/coa-launch-binaries/raw/main/linux/amd64/compute/launcher -o launcher && \
    curl -L https://github.com/Impa-Ventures/coa-launch-binaries/raw/main/linux/amd64/compute/worker -o worker
RUN chmod +x ./launcher && chmod +x ./worker
EOL

if [[ "$use_proxy" == "Y" || "$use_proxy" == "y" ]]; then
    cat <<EOL >> "$device_dir/Dockerfile"
COPY redsocks.conf /etc/redsocks.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EOL
fi

cat <<EOL >> "$device_dir/Dockerfile"
CMD ["/bin/bash", "-c", "exec /bin/bash"]
EOL

# 如果使用代理，则创建 redsocks 配置文件和入口脚本
if [[ "$use_proxy" == "Y" || "$use_proxy" == "y" ]]; then
    cat <<EOL > "$device_dir/redsocks.conf"
base {
    log_debug = off;
    log_info = on;
    log = "file:/var/log/redsocks.log";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = $proxy_ip;
    port = $proxy_port;
    type = $proxy_type;
EOL

    if [[ -n "$proxy_username" ]]; then
        cat <<EOL >> "$device_dir/redsocks.conf"
    login = "$proxy_username";
EOL
    fi

    if [[ -n "$proxy_password" ]]; then
        cat <<EOL >> "$device_dir/redsocks.conf"
    password = "$proxy_password";
EOL
    fi

    cat <<EOL >> "$device_dir/redsocks.conf"
}
EOL

    cat <<EOL > "$device_dir/entrypoint.sh"
#!/bin/sh

echo -e "${INFO}[INFO] 启动 redsocks...${NC}"
redsocks -c /etc/redsocks.conf &
sleep 5

echo -e "${INFO}[INFO] 配置 iptables...${NC}"
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 12345
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 12345

exec "\$@"
EOL
fi

# 生成伪造的 UUID 并存储在设备目录中
fake_product_uuid_file="$device_dir/fake_uuid.txt"
if [ ! -f "$fake_product_uuid_file" ]; then
    generated_uuid=$(generate_uuid)
    echo "$generated_uuid" > "$fake_product_uuid_file"
fi

mac_address=$(generate_mac_address)
echo -e "${INFO}[INFO] 使用生成的 MAC 地址：$mac_address${NC}"

device_name_lower=$(echo "$device_name" | tr '[:upper:]' '[:lower:]')

echo -e "${INFO}[INFO] 正在构建 Docker 镜像 '$device_name_lower'...${NC}"
docker build -t "$device_name_lower" "$device_dir"

echo -e "${SUCCESS}[SUCCESS] Docker 容器 '$device_name' 已成功设置并生成伪造的 UUID。${NC}"

# 提示用户粘贴第三条命令
echo -e "${INFO}[INFO] 现在将 AG 设备初始化板上的第 3 条命令复制并粘贴到以下命令提示符中...${NC}"

if [[ "$use_proxy" == "Y" || "$use_proxy" == "y" ]]; then
    docker run -it --cap-add=NET_ADMIN --mac-address="$mac_address" \
        -v "$fake_product_uuid_file:/sys/class/dmi/id/product_uuid" \
        --name="$device_name" "$device_name_lower" /bin/bash
else
    docker run -it --mac-address="$mac_address" \
        -v "$fake_product_uuid_file:/sys/class/dmi/id/product_uuid" \
        --name="$device_name" "$device_name_lower" /bin/bash
fi

