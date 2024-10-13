#!/bin/bash

# 定义文本格式
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
SUCCESS_COLOR='\033[1;32m' # 绿色
ERROR_COLOR='\033[1;31m'   # 红色
INFO_COLOR='\033[1;36m'    # 青色
MENU_COLOR='\033[1;34m'    # 蓝色

# 自定义状态显示函数
show_message() {
    local message="$1"
    local status="$2"
    case $status in
        "error")
            echo -e "${ERROR_COLOR}${BOLD}❌ 错误: ${message}${NORMAL}"
            ;;
        "info")
            echo -e "${INFO_COLOR}${BOLD}ℹ️ 信息: ${message}${NORMAL}"
            ;;
        "success")
            echo -e "${SUCCESS_COLOR}${BOLD}✅ 成功: ${message}${NORMAL}"
            ;;
        *)
            echo -e "${message}"
            ;;
    esac
}

# 确保输入非空的函数
get_non_empty_input() {
    local prompt="$1"
    local input=""
    while [ -z "$input" ]; do
        read -p "$prompt" input
        if [ -z "$input" ]; then
            show_message "此字段不能为空。" "error"
        fi
    done
    echo "$input"
}

# 生成随机 MAC 地址的函数
generate_mac_address() {
    echo "02:$(od -An -N5 -tx1 /dev/urandom | tr ' ' ':' | cut -c2-)"
}

# 生成新的虚拟产品 UUID 的函数
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 获取并验证参数
device_name=$(get_non_empty_input "请输入设备名称：")

# 为设备创建配置目录
device_dir="./$device_name"
if [ ! -d "$device_dir" ]; then
    mkdir "$device_dir"
    show_message "已为设备 '$device_name' 创建目录：$device_dir" "info"
fi

# 代理配置
read -p "是否使用代理？(Y/N): " use_proxy

proxy_type=""
proxy_ip=""
proxy_port=""
proxy_username=""
proxy_password=""

if [[ "$use_proxy" == "Y" || "$use_proxy" == "y" ]]; then
    read -p "请输入代理类型 (http/socks5): " proxy_type
    read -p "请输入代理 IP: " proxy_ip
    read -p "请输入代理端口: " proxy_port
    read -p "请输入代理用户名 (若无则留空): " proxy_username
    read -p "请输入代理密码 (若无则留空): " proxy_password
    if [[ "$proxy_type" == "http" ]]; then
        proxy_type="http-connect"
    fi
fi

# 创建 Dockerfile
show_message "正在创建 Dockerfile..." "info"
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

# 创建 redsocks 配置（如启用代理）
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
        echo "    login = \"$proxy_username\";" >> "$device_dir/redsocks.conf"
    fi

    if [[ -n "$proxy_password" ]]; then
        echo "    password = \"$proxy_password\";" >> "$device_dir/redsocks.conf"
    fi

    echo "}" >> "$device_dir/redsocks.conf"

    cat <<EOL > "$device_dir/entrypoint.sh"
#!/bin/sh

echo "启动 redsocks..."
redsocks -c /etc/redsocks.conf &
echo "redsocks 已启动。"

sleep 5

echo "配置 iptables..."
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-ports 12345
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports 12345
echo "iptables 配置完成。"

exec "\$@"
EOL
fi

# 生成虚拟 UUID 并存入文件
fake_product_uuid_file="$device_dir/fake_uuid.txt"
if [ ! -f "$fake_product_uuid_file" ]; then
    generated_uuid=$(generate_uuid)
    echo "$generated_uuid" > "$fake_product_uuid_file"
    show_message "生成的虚拟 UUID: $generated_uuid" "info"
fi

# 使用随机 MAC 地址
mac_address=$(generate_mac_address)
show_message "生成的 MAC 地址：$mac_address" "info"

device_name_lower=$(echo "$device_name" | tr '[:upper:]' '[:lower:]')

# 构建 Docker 镜像
show_message "正在构建 Docker 镜像 '$device_name_lower'..." "info"
docker build -t "$device_name_lower" "$device_dir"

show_message "容器 '${device_name}' 已成功设置。" "success"

# 运行 Docker 容器
if [[ "$use_proxy" == "Y" || "$use_proxy" == "y" ]]; then
    docker run -it --cap-add=NET_ADMIN --mac-address="$mac_address" \
    -v "$fake_product_uuid_file:/sys/class/dmi/id/product_uuid" \
    --name="$device_name" "$device_name_lower"
else
    docker run -it --mac-address="$mac_address" \
    -v "$fake_product_uuid_file:/sys/class/dmi/id/product_uuid" \
    --name="$device_name" "$device_name_lower"
fi
