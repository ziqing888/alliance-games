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
echo -e "${MENU_COLOR}${BOLD}      联盟游戏 Docker 安装脚本 v2.0            ${NC}"
echo -e "${MENU_COLOR}${BOLD}      由 子清 提供                             ${NC}"
echo -e "${MENU_COLOR}${BOLD}==============================================${NC}"

# 自定义状态显示函数
log_message() {
    local type="$1"
    local message="$2"
    case "$type" in
        INFO) echo -e "${INFO}[INFO] ${message}${NC}" ;;
        WARNING) echo -e "${WARNING}[WARNING] ${message}${NC}" ;;
        ERROR) echo -e "${ERROR}[ERROR] ${message}${NC}" ;;
        SUCCESS) echo -e "${SUCCESS}[SUCCESS] ${message}${NC}" ;;
        *) echo "[UNKNOWN] ${message}" ;;
    esac
}

# 确保输入非空的函数
get_non_empty_input() {
    local prompt="$1"
    local input=""
    while [ -z "$input" ]; do
        read -p "$prompt" input
        if [ -z "$input" ]; then
            log_message "ERROR" "此字段不能为空。"
        fi
    done
    echo "$input"
}

# 生成随机 MAC 地址的函数
generate_mac_address() {
    echo "02:$(od -An -N5 -tx1 /dev/urandom | tr ' ' ':' | cut -c2-)"
}

# 生成 UUID 的函数
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 创建 Docker 容器的函数
create_container() {
    local device_name=$(get_non_empty_input "输入设备名称：")
    local device_dir="./$device_name"

    if [ ! -d "$device_dir" ]; then
        mkdir "$device_dir"
        log_message "INFO" "已为 $device_name 创建目录：$device_dir"
    fi

    local fake_product_uuid_file="$device_dir/fake_uuid.txt"
    if [ ! -f "$fake_product_uuid_file" ]; then
        echo "$(generate_uuid)" > "$fake_product_uuid_file"
    fi

    local mac_address=$(generate_mac_address)
    log_message "INFO" "使用生成的 MAC 地址：$mac_address"

    device_name_lower=$(echo "$device_name" | tr '[:upper:]' '[:lower:]')
    log_message "INFO" "正在构建 Docker 镜像 '$device_name_lower'..."
    docker build -t "$device_name_lower" "$device_dir"

    log_message "SUCCESS" "Docker 容器 '$device_name' 已成功创建。"
}

# 启动 Docker 容器的函数
start_container() {
    local container_name=$(get_non_empty_input "输入要启动的容器名称：")
    log_message "INFO" "启动 Docker 容器 '$container_name'..."
    docker start -i "$container_name"
}

# 停止 Docker 容器的函数
stop_container() {
    local container_name=$(get_non_empty_input "输入要停止的容器名称：")
    log_message "INFO" "停止 Docker 容器 '$container_name'..."
    docker stop "$container_name"
}

# 删除 Docker 容器的函数
delete_container() {
    local container_name=$(get_non_empty_input "输入要删除的容器名称：")
    log_message "WARNING" "即将删除 Docker 容器 '$container_name'..."
    docker rm "$container_name"
    log_message "SUCCESS" "Docker 容器 '$container_name' 已删除。"
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${MENU_COLOR}${BOLD}======== 主菜单 ========${NC}"
        echo "1) 创建 Docker 容器"
        echo "2) 启动 Docker 容器"
        echo "3) 停止 Docker 容器"
        echo "4) 删除 Docker 容器"
        echo "5) 退出"
        echo -n "选择操作: "

        read choice
        case $choice in
            1) create_container ;;
            2) start_container ;;
            3) stop_container ;;
            4) delete_container ;;
            5) log_message "INFO" "退出程序。"; exit 0 ;;
            *) log_message "ERROR" "无效选项，请重试。" ;;
        esac
    done
}

# 启动主菜单
main_menu
