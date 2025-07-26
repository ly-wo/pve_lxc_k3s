#!/bin/bash
# PVE Deployment Automation Script
# PVE 部署自动化脚本

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载依赖
source "${PROJECT_ROOT}/scripts/logging.sh"
source "${PROJECT_ROOT}/scripts/config-loader.sh"

# 组件名称
COMPONENT="pve-deployment"

# 默认配置
DEFAULT_PVE_NODE="pve-node"
DEFAULT_STORAGE="local-lvm"
DEFAULT_NETWORK_BRIDGE="vmbr0"
DEFAULT_CONTAINER_ID_START=9000
DEFAULT_MEMORY_MB=2048
DEFAULT_CPU_CORES=2
DEFAULT_DISK_SIZE_GB=20

# 部署配置
PVE_NODE="${PVE_NODE:-$DEFAULT_PVE_NODE}"
PVE_STORAGE="${PVE_STORAGE:-$DEFAULT_STORAGE}"
NETWORK_BRIDGE="${NETWORK_BRIDGE:-$DEFAULT_NETWORK_BRIDGE}"
CONTAINER_ID_START="${CONTAINER_ID_START:-$DEFAULT_CONTAINER_ID_START}"
MEMORY_MB="${MEMORY_MB:-$DEFAULT_MEMORY_MB}"
CPU_CORES="${CPU_CORES:-$DEFAULT_CPU_CORES}"
DISK_SIZE_GB="${DISK_SIZE_GB:-$DEFAULT_DISK_SIZE_GB}"

# 部署状态
DEPLOYMENT_LOG="${PROJECT_ROOT}/logs/pve-deployment.log"
DEPLOYED_CONTAINERS=()

# 初始化部署环境
initialize_deployment() {
    log_info "$COMPONENT" "初始化PVE部署环境"
    
    # 创建日志目录
    mkdir -p "$(dirname "$DEPLOYMENT_LOG")"
    
    # 检查PVE环境
    check_pve_environment
    
    # 验证配置
    validate_deployment_config
    
    log_info "$COMPONENT" "部署环境初始化完成"
}

# 检查PVE环境
check_pve_environment() {
    log_info "$COMPONENT" "检查PVE环境"
    
    # 检查PVE命令
    if ! command -v pct >/dev/null 2>&1; then
        log_error "$COMPONENT" "PVE容器工具(pct)不可用"
        exit 1
    fi
    
    if ! command -v pvesm >/dev/null 2>&1; then
        log_error "$COMPONENT" "PVE存储管理器(pvesm)不可用"
        exit 1
    fi
    
    # 检查节点状态
    if ! pvesh get /nodes/"$PVE_NODE"/status >/dev/null 2>&1; then
        log_warn "$COMPONENT" "无法连接到PVE节点: $PVE_NODE"
    fi
    
    # 检查存储状态
    if ! pvesm status | grep -q "$PVE_STORAGE"; then
        log_error "$COMPONENT" "存储不可用: $PVE_STORAGE"
        exit 1
    fi
    
    # 检查网络桥接
    if ! ip link show "$NETWORK_BRIDGE" >/dev/null 2>&1; then
        log_warn "$COMPONENT" "网络桥接可能不存在: $NETWORK_BRIDGE"
    fi
    
    log_info "$COMPONENT" "PVE环境检查完成"
}

# 验证部署配置
validate_deployment_config() {
    log_info "$COMPONENT" "验证部署配置"
    
    # 验证容器ID范围
    if [[ $CONTAINER_ID_START -lt 100 || $CONTAINER_ID_START -gt 999999 ]]; then
        log_error "$COMPONENT" "容器ID范围无效: $CONTAINER_ID_START"
        exit 1
    fi
    
    # 验证资源配置
    if [[ $MEMORY_MB -lt 512 ]]; then
        log_error "$COMPONENT" "内存配置过低: ${MEMORY_MB}MB"
        exit 1
    fi
    
    if [[ $CPU_CORES -lt 1 ]]; then
        log_error "$COMPONENT" "CPU核心数无效: $CPU_CORES"
        exit 1
    fi
    
    if [[ $DISK_SIZE_GB -lt 5 ]]; then
        log_error "$COMPONENT" "磁盘大小过小: ${DISK_SIZE_GB}GB"
        exit 1
    fi
    
    log_info "$COMPONENT" "部署配置验证通过"
}

# 上传模板到PVE
upload_template_to_pve() {
    local template_file="$1"
    local template_name="$2"
    
    log_info "$COMPONENT" "上传模板到PVE: $template_name"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "$COMPONENT" "模板文件不存在: $template_file"
        return 1
    fi
    
    # 检查模板是否已存在
    if pvesm list "$PVE_STORAGE" | grep -q "$template_name"; then
        log_warn "$COMPONENT" "模板已存在，跳过上传: $template_name"
        return 0
    fi
    
    # 上传模板
    if ! pvesm upload "$PVE_STORAGE" "$template_file"; then
        log_error "$COMPONENT" "模板上传失败: $template_file"
        return 1
    fi
    
    # 验证上传结果
    if ! pvesm list "$PVE_STORAGE" | grep -q "$template_name"; then
        log_error "$COMPONENT" "模板上传验证失败: $template_name"
        return 1
    fi
    
    log_info "$COMPONENT" "模板上传成功: $template_name"
    return 0
}

# 创建LXC容器
create_lxc_container() {
    local container_id="$1"
    local template_name="$2"
    local hostname="$3"
    local ip_config="${4:-dhcp}"
    
    log_info "$COMPONENT" "创建LXC容器: $container_id ($hostname)"
    
    # 检查容器ID是否已被使用
    if pct list | grep -q "^$container_id"; then
        log_error "$COMPONENT" "容器ID已被使用: $container_id"
        return 1
    fi
    
    # 构建创建命令
    local create_cmd=(
        pct create "$container_id"
        "$PVE_STORAGE:vztmpl/$template_name"
        --memory "$MEMORY_MB"
        --cores "$CPU_CORES"
        --rootfs "$PVE_STORAGE:$DISK_SIZE_GB"
        --hostname "$hostname"
        --unprivileged 1
        --onboot 1
        --start 1
    )
    
    # 配置网络
    if [[ "$ip_config" == "dhcp" ]]; then
        create_cmd+=(--net0 "name=eth0,bridge=$NETWORK_BRIDGE,ip=dhcp")
    else
        create_cmd+=(--net0 "name=eth0,bridge=$NETWORK_BRIDGE,ip=$ip_config")
    fi
    
    # 执行创建命令
    if ! "${create_cmd[@]}"; then
        log_error "$COMPONENT" "容器创建失败: $container_id"
        return 1
    fi
    
    # 记录已部署的容器
    DEPLOYED_CONTAINERS+=("$container_id")
    
    log_info "$COMPONENT" "容器创建成功: $container_id"
    return 0
}

# 等待容器就绪
wait_for_container_ready() {
    local container_id="$1"
    local timeout="${2:-300}"
    
    log_info "$COMPONENT" "等待容器就绪: $container_id"
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        # 检查容器状态
        if pct list | grep "^$container_id" | grep -q "running"; then
            # 检查K3s服务状态
            if pct exec "$container_id" -- systemctl is-active k3s >/dev/null 2>&1; then
                # 检查K3s API健康状态
                if pct exec "$container_id" -- curl -k -s https://localhost:6443/healthz | grep -q "ok"; then
                    log_info "$COMPONENT" "容器就绪: $container_id (耗时: ${elapsed}秒)"
                    return 0
                fi
            fi
        fi
        
        sleep 10
        ((elapsed += 10))
        
        if [[ $((elapsed % 60)) -eq 0 ]]; then
            log_info "$COMPONENT" "等待容器就绪: $container_id (已等待: ${elapsed}秒)"
        fi
    done
    
    log_error "$COMPONENT" "容器就绪超时: $container_id"
    return 1
}

# 验证容器功能
verify_container_functionality() {
    local container_id="$1"
    
    log_info "$COMPONENT" "验证容器功能: $container_id"
    
    # 检查容器状态
    if ! pct list | grep "^$container_id" | grep -q "running"; then
        log_error "$COMPONENT" "容器未运行: $container_id"
        return 1
    fi
    
    # 检查K3s服务
    if ! pct exec "$container_id" -- systemctl is-active k3s >/dev/null 2>&1; then
        log_error "$COMPONENT" "K3s服务未运行: $container_id"
        return 1
    fi
    
    # 检查K3s API
    if ! pct exec "$container_id" -- curl -k -s https://localhost:6443/healthz | grep -q "ok"; then
        log_error "$COMPONENT" "K3s API不健康: $container_id"
        return 1
    fi
    
    # 检查节点状态
    if ! pct exec "$container_id" -- k3s kubectl get nodes | grep -q "Ready"; then
        log_error "$COMPONENT" "K3s节点状态异常: $container_id"
        return 1
    fi
    
    # 检查系统Pod状态
    local system_pods_ready=true
    if ! pct exec "$container_id" -- k3s kubectl get pods -n kube-system --no-headers | grep -v "Running\|Completed" >/dev/null; then
        system_pods_ready=false
    fi
    
    if [[ "$system_pods_ready" == "false" ]]; then
        log_warn "$COMPONENT" "部分系统Pod未就绪: $container_id"
    fi
    
    log_info "$COMPONENT" "容器功能验证通过: $container_id"
    return 0
}

# 配置集群节点
configure_cluster_node() {
    local container_id="$1"
    local node_type="$2"  # server 或 agent
    local master_ip="${3:-}"
    local cluster_token="${4:-}"
    
    log_info "$COMPONENT" "配置集群节点: $container_id ($node_type)"
    
    case "$node_type" in
        "server")
            # 配置服务器节点
            log_info "$COMPONENT" "配置K3s服务器节点: $container_id"
            
            # 如果是第一个服务器节点，初始化集群
            if [[ -z "$master_ip" ]]; then
                pct exec "$container_id" -- sh -c "echo 'cluster-init: true' >> /etc/rancher/k3s/config.yaml"
            else
                # 加入现有集群
                pct exec "$container_id" -- sh -c "echo 'server: https://$master_ip:6443' >> /etc/rancher/k3s/config.yaml"
                pct exec "$container_id" -- sh -c "echo 'token: $cluster_token' >> /etc/rancher/k3s/config.yaml"
            fi
            ;;
        "agent")
            # 配置代理节点
            log_info "$COMPONENT" "配置K3s代理节点: $container_id"
            
            if [[ -z "$master_ip" || -z "$cluster_token" ]]; then
                log_error "$COMPONENT" "代理节点需要主节点IP和集群令牌"
                return 1
            fi
            
            # 配置代理节点
            pct exec "$container_id" -- sh -c "echo 'server: https://$master_ip:6443' > /etc/rancher/k3s/config.yaml"
            pct exec "$container_id" -- sh -c "echo 'token: $cluster_token' >> /etc/rancher/k3s/config.yaml"
            
            # 重启K3s服务以应用配置
            pct exec "$container_id" -- systemctl restart k3s
            ;;
        *)
            log_error "$COMPONENT" "未知节点类型: $node_type"
            return 1
            ;;
    esac
    
    log_info "$COMPONENT" "集群节点配置完成: $container_id"
    return 0
}

# 获取集群令牌
get_cluster_token() {
    local master_container_id="$1"
    
    log_info "$COMPONENT" "获取集群令牌: $master_container_id"
    
    local token
    token=$(pct exec "$master_container_id" -- cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "")
    
    if [[ -z "$token" ]]; then
        log_error "$COMPONENT" "无法获取集群令牌: $master_container_id"
        return 1
    fi
    
    echo "$token"
    return 0
}

# 获取容器IP地址
get_container_ip() {
    local container_id="$1"
    
    local ip
    ip=$(pct exec "$container_id" -- ip route get 1 | awk '{print $7; exit}' 2>/dev/null || echo "")
    
    if [[ -z "$ip" ]]; then
        log_warn "$COMPONENT" "无法获取容器IP: $container_id"
        return 1
    fi
    
    echo "$ip"
    return 0
}

# 部署单节点集群
deploy_single_node_cluster() {
    local template_file="$1"
    local template_name="$2"
    local hostname="${3:-k3s-single}"
    
    log_info "$COMPONENT" "部署单节点K3s集群"
    
    # 上传模板
    if ! upload_template_to_pve "$template_file" "$template_name"; then
        log_error "$COMPONENT" "模板上传失败"
        return 1
    fi
    
    # 创建容器
    local container_id=$CONTAINER_ID_START
    if ! create_lxc_container "$container_id" "$template_name" "$hostname"; then
        log_error "$COMPONENT" "容器创建失败"
        return 1
    fi
    
    # 等待容器就绪
    if ! wait_for_container_ready "$container_id"; then
        log_error "$COMPONENT" "容器就绪超时"
        return 1
    fi
    
    # 验证容器功能
    if ! verify_container_functionality "$container_id"; then
        log_error "$COMPONENT" "容器功能验证失败"
        return 1
    fi
    
    log_info "$COMPONENT" "单节点K3s集群部署成功: $container_id"
    return 0
}

# 部署多节点集群
deploy_multi_node_cluster() {
    local template_file="$1"
    local template_name="$2"
    local master_count="${3:-1}"
    local worker_count="${4:-2}"
    
    log_info "$COMPONENT" "部署多节点K3s集群 (主节点: $master_count, 工作节点: $worker_count)"
    
    # 上传模板
    if ! upload_template_to_pve "$template_file" "$template_name"; then
        log_error "$COMPONENT" "模板上传失败"
        return 1
    fi
    
    local master_containers=()
    local worker_containers=()
    local current_id=$CONTAINER_ID_START
    
    # 创建主节点
    log_info "$COMPONENT" "创建主节点"
    for ((i=1; i<=master_count; i++)); do
        local hostname="k3s-master-$i"
        
        if ! create_lxc_container "$current_id" "$template_name" "$hostname"; then
            log_error "$COMPONENT" "主节点创建失败: $current_id"
            return 1
        fi
        
        master_containers+=("$current_id")
        ((current_id++))
    done
    
    # 等待第一个主节点就绪
    local first_master="${master_containers[0]}"
    if ! wait_for_container_ready "$first_master"; then
        log_error "$COMPONENT" "第一个主节点就绪超时: $first_master"
        return 1
    fi
    
    # 获取集群信息
    local master_ip
    master_ip=$(get_container_ip "$first_master")
    local cluster_token
    cluster_token=$(get_cluster_token "$first_master")
    
    if [[ -z "$master_ip" || -z "$cluster_token" ]]; then
        log_error "$COMPONENT" "无法获取集群信息"
        return 1
    fi
    
    log_info "$COMPONENT" "集群主节点IP: $master_ip"
    
    # 配置其他主节点加入集群
    for ((i=1; i<${#master_containers[@]}; i++)); do
        local master_id="${master_containers[$i]}"
        
        if ! wait_for_container_ready "$master_id"; then
            log_error "$COMPONENT" "主节点就绪超时: $master_id"
            return 1
        fi
        
        if ! configure_cluster_node "$master_id" "server" "$master_ip" "$cluster_token"; then
            log_error "$COMPONENT" "主节点集群配置失败: $master_id"
            return 1
        fi
    done
    
    # 创建工作节点
    log_info "$COMPONENT" "创建工作节点"
    for ((i=1; i<=worker_count; i++)); do
        local hostname="k3s-worker-$i"
        
        if ! create_lxc_container "$current_id" "$template_name" "$hostname"; then
            log_error "$COMPONENT" "工作节点创建失败: $current_id"
            return 1
        fi
        
        worker_containers+=("$current_id")
        ((current_id++))
    done
    
    # 配置工作节点加入集群
    for worker_id in "${worker_containers[@]}"; do
        if ! wait_for_container_ready "$worker_id"; then
            log_error "$COMPONENT" "工作节点就绪超时: $worker_id"
            return 1
        fi
        
        if ! configure_cluster_node "$worker_id" "agent" "$master_ip" "$cluster_token"; then
            log_error "$COMPONENT" "工作节点集群配置失败: $worker_id"
            return 1
        fi
    done
    
    # 验证集群状态
    log_info "$COMPONENT" "验证集群状态"
    if ! pct exec "$first_master" -- k3s kubectl get nodes | grep -q "Ready"; then
        log_error "$COMPONENT" "集群节点状态异常"
        return 1
    fi
    
    local node_count
    node_count=$(pct exec "$first_master" -- k3s kubectl get nodes --no-headers | wc -l)
    local expected_count=$((master_count + worker_count))
    
    if [[ $node_count -ne $expected_count ]]; then
        log_warn "$COMPONENT" "集群节点数量不匹配: 期望 $expected_count, 实际 $node_count"
    fi
    
    log_info "$COMPONENT" "多节点K3s集群部署成功"
    log_info "$COMPONENT" "主节点: ${master_containers[*]}"
    log_info "$COMPONENT" "工作节点: ${worker_containers[*]}"
    
    return 0
}

# 清理部署
cleanup_deployment() {
    log_info "$COMPONENT" "清理部署"
    
    for container_id in "${DEPLOYED_CONTAINERS[@]}"; do
        log_info "$COMPONENT" "清理容器: $container_id"
        
        # 停止容器
        if pct list | grep "^$container_id" | grep -q "running"; then
            pct stop "$container_id" || true
        fi
        
        # 删除容器
        if pct list | grep -q "^$container_id"; then
            pct destroy "$container_id" || true
        fi
    done
    
    log_info "$COMPONENT" "部署清理完成"
}

# 显示部署状态
show_deployment_status() {
    log_info "$COMPONENT" "部署状态"
    
    if [[ ${#DEPLOYED_CONTAINERS[@]} -eq 0 ]]; then
        log_info "$COMPONENT" "没有已部署的容器"
        return 0
    fi
    
    echo "已部署的容器:"
    for container_id in "${DEPLOYED_CONTAINERS[@]}"; do
        local status="unknown"
        local hostname="unknown"
        local ip="unknown"
        
        if pct list | grep -q "^$container_id"; then
            status=$(pct list | grep "^$container_id" | awk '{print $2}')
            hostname=$(pct config "$container_id" | grep "^hostname:" | cut -d' ' -f2 || echo "unknown")
            
            if [[ "$status" == "running" ]]; then
                ip=$(get_container_ip "$container_id" || echo "unknown")
            fi
        fi
        
        echo "  容器 $container_id: $hostname ($status) - IP: $ip"
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
PVE部署自动化脚本

用法: $0 <命令> [选项]

命令:
    single-node <template_file>     部署单节点K3s集群
    multi-node <template_file>      部署多节点K3s集群
    cleanup                         清理所有部署的容器
    status                          显示部署状态
    help                           显示此帮助信息

选项:
    --pve-node NODE                指定PVE节点 (默认: $DEFAULT_PVE_NODE)
    --storage STORAGE              指定存储 (默认: $DEFAULT_STORAGE)
    --network-bridge BRIDGE       指定网络桥接 (默认: $DEFAULT_NETWORK_BRIDGE)
    --container-id-start ID        指定起始容器ID (默认: $DEFAULT_CONTAINER_ID_START)
    --memory MB                    指定内存大小 (默认: ${DEFAULT_MEMORY_MB}MB)
    --cpu-cores CORES              指定CPU核心数 (默认: $DEFAULT_CPU_CORES)
    --disk-size GB                 指定磁盘大小 (默认: ${DEFAULT_DISK_SIZE_GB}GB)
    --master-count COUNT           指定主节点数量 (默认: 1)
    --worker-count COUNT           指定工作节点数量 (默认: 2)
    --hostname HOSTNAME            指定主机名 (单节点模式)

环境变量:
    PVE_NODE                       PVE节点名称
    PVE_STORAGE                    PVE存储名称
    NETWORK_BRIDGE                 网络桥接名称
    CONTAINER_ID_START             起始容器ID
    MEMORY_MB                      内存大小(MB)
    CPU_CORES                      CPU核心数
    DISK_SIZE_GB                   磁盘大小(GB)

示例:
    # 部署单节点集群
    $0 single-node /path/to/template.tar.gz
    
    # 部署多节点集群
    $0 multi-node /path/to/template.tar.gz --master-count 3 --worker-count 5
    
    # 使用自定义配置
    $0 single-node /path/to/template.tar.gz --memory 4096 --cpu-cores 4
    
    # 清理部署
    $0 cleanup
    
    # 查看状态
    $0 status

EOF
}

# 主函数
main() {
    local command="${1:-help}"
    shift || true
    
    # 解析通用选项
    while [[ $# -gt 0 ]]; do
        case $1 in
            --pve-node)
                PVE_NODE="$2"
                shift 2
                ;;
            --storage)
                PVE_STORAGE="$2"
                shift 2
                ;;
            --network-bridge)
                NETWORK_BRIDGE="$2"
                shift 2
                ;;
            --container-id-start)
                CONTAINER_ID_START="$2"
                shift 2
                ;;
            --memory)
                MEMORY_MB="$2"
                shift 2
                ;;
            --cpu-cores)
                CPU_CORES="$2"
                shift 2
                ;;
            --disk-size)
                DISK_SIZE_GB="$2"
                shift 2
                ;;
            --master-count)
                MASTER_COUNT="$2"
                shift 2
                ;;
            --worker-count)
                WORKER_COUNT="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            -*)
                log_error "$COMPONENT" "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                # 非选项参数，重新放回参数列表
                set -- "$1" "$@"
                break
                ;;
        esac
    done
    
    # 初始化部署环境
    if [[ "$command" != "help" ]]; then
        initialize_deployment
    fi
    
    # 执行命令
    case "$command" in
        "single-node")
            local template_file="${1:-}"
            if [[ -z "$template_file" ]]; then
                log_error "$COMPONENT" "请指定模板文件"
                show_help
                exit 1
            fi
            
            local template_name
            template_name=$(basename "$template_file")
            local hostname="${HOSTNAME:-k3s-single}"
            
            deploy_single_node_cluster "$template_file" "$template_name" "$hostname"
            ;;
        "multi-node")
            local template_file="${1:-}"
            if [[ -z "$template_file" ]]; then
                log_error "$COMPONENT" "请指定模板文件"
                show_help
                exit 1
            fi
            
            local template_name
            template_name=$(basename "$template_file")
            local master_count="${MASTER_COUNT:-1}"
            local worker_count="${WORKER_COUNT:-2}"
            
            deploy_multi_node_cluster "$template_file" "$template_name" "$master_count" "$worker_count"
            ;;
        "cleanup")
            cleanup_deployment
            ;;
        "status")
            show_deployment_status
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi