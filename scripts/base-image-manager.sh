#!/bin/bash
# Base Image Manager for PVE LXC K3s Template
# 负责 Alpine 基础镜像的下载、验证和缓存管理

set -euo pipefail

# 脚本目录和配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"
CACHE_DIR="${PROJECT_ROOT}/.cache/images"
LOG_FILE="${PROJECT_ROOT}/logs/base-image-manager.log"

# 创建必要的目录
mkdir -p "$CACHE_DIR" "$(dirname "$LOG_FILE")"

# 日志函数
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# 错误处理
error_exit() {
    log_error "$1"
    exit 1
}

# 加载配置文件
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "配置文件不存在: $CONFIG_FILE"
    fi
    
    # 使用 yq 或 python 解析 YAML（这里使用简单的 grep/sed 方法）
    BASE_IMAGE=$(grep "base_image:" "$CONFIG_FILE" | sed 's/.*base_image: *"\([^"]*\)".*/\1/')
    ARCHITECTURE=$(grep "architecture:" "$CONFIG_FILE" | sed 's/.*architecture: *"\([^"]*\)".*/\1/')
    
    if [[ -z "$BASE_IMAGE" ]]; then
        error_exit "无法从配置文件中读取 base_image"
    fi
    
    log_info "加载配置: BASE_IMAGE=$BASE_IMAGE, ARCHITECTURE=$ARCHITECTURE"
}

# 解析镜像信息
parse_image_info() {
    local image="$1"
    
    # 解析 alpine:3.18 格式
    if [[ "$image" =~ ^([^:]+):(.+)$ ]]; then
        IMAGE_NAME="${BASH_REMATCH[1]}"
        IMAGE_TAG="${BASH_REMATCH[2]}"
    else
        IMAGE_NAME="$image"
        IMAGE_TAG="latest"
    fi
    
    log_info "解析镜像信息: NAME=$IMAGE_NAME, TAG=$IMAGE_TAG"
}

# 检查镜像版本兼容性
check_version_compatibility() {
    local tag="$1"
    
    # Alpine 版本兼容性检查
    if [[ "$IMAGE_NAME" == "alpine" ]]; then
        # 支持的 Alpine 版本列表
        local supported_versions=("3.16" "3.17" "3.18" "3.19" "latest" "edge")
        local is_supported=false
        
        for version in "${supported_versions[@]}"; do
            if [[ "$tag" == "$version" ]]; then
                is_supported=true
                break
            fi
        done
        
        if [[ "$is_supported" == "false" ]]; then
            log_warn "Alpine 版本 $tag 可能不受支持，建议使用: ${supported_versions[*]}"
        else
            log_info "Alpine 版本 $tag 兼容性检查通过"
        fi
    fi
    
    # 架构兼容性检查
    case "$ARCHITECTURE" in
        "amd64"|"x86_64")
            log_info "架构 $ARCHITECTURE 兼容性检查通过"
            ;;
        "arm64"|"aarch64")
            log_info "架构 $ARCHITECTURE 兼容性检查通过"
            ;;
        *)
            log_warn "架构 $ARCHITECTURE 可能不受支持"
            ;;
    esac
}

# 生成镜像缓存路径
get_cache_path() {
    local image_name="$1"
    local image_tag="$2"
    local arch="$3"
    
    echo "${CACHE_DIR}/${image_name}_${image_tag}_${arch}.tar.gz"
}

# 生成校验和文件路径
get_checksum_path() {
    local cache_path="$1"
    echo "${cache_path}.sha256"
}

# 下载镜像校验和
download_checksum() {
    local image_name="$1"
    local image_tag="$2"
    local arch="$3"
    
    # Alpine 官方校验和 URL 模式
    if [[ "$image_name" == "alpine" ]]; then
        # 映射架构名称
        local alpine_arch
        alpine_arch=$(get_alpine_arch "$arch")
        
        # 如果 image_tag 只是主版本号，获取最新的补丁版本
        local full_version="$image_tag"
        if [[ "$image_tag" =~ ^[0-9]+\.[0-9]+$ ]]; then
            full_version=$(get_latest_alpine_version "$image_tag" "$arch")
        fi
        
        local checksum_url="https://dl-cdn.alpinelinux.org/alpine/v${full_version%.*}/releases/${alpine_arch}/alpine-minirootfs-${full_version}-${alpine_arch}.tar.gz.sha256"
        local checksum_file
        checksum_file=$(get_checksum_path "$(get_cache_path "$image_name" "$image_tag" "$arch")")
        
        log_info "下载校验和: $checksum_url"
        
        if curl -fsSL "$checksum_url" -o "$checksum_file"; then
            log_info "校验和下载成功: $checksum_file"
            return 0
        else
            log_warn "无法下载官方校验和，将在下载后生成本地校验和"
            return 1
        fi
    fi
    
    return 1
}

# 验证文件校验和
verify_checksum() {
    local file_path="$1"
    local checksum_file="$2"
    
    if [[ ! -f "$checksum_file" ]]; then
        log_warn "校验和文件不存在: $checksum_file"
        return 1
    fi
    
    log_info "验证文件校验和: $file_path"
    
    # 计算文件的 SHA256
    local calculated_sum
    calculated_sum=$(sha256sum "$file_path" | cut -d' ' -f1)
    
    # 读取期望的校验和
    local expected_sum
    expected_sum=$(cut -d' ' -f1 "$checksum_file")
    
    if [[ "$calculated_sum" == "$expected_sum" ]]; then
        log_info "校验和验证成功"
        return 0
    else
        log_error "校验和验证失败: 期望 $expected_sum, 实际 $calculated_sum"
        return 1
    fi
}

# 生成本地校验和
generate_checksum() {
    local file_path="$1"
    local checksum_file="$2"
    
    log_info "生成本地校验和: $file_path"
    sha256sum "$file_path" > "$checksum_file"
    log_info "校验和已保存到: $checksum_file"
}

# 下载基础镜像
download_base_image() {
    local image_name="$1"
    local image_tag="$2"
    local arch="$3"
    
    local cache_path
    cache_path=$(get_cache_path "$image_name" "$image_tag" "$arch")
    local checksum_file
    checksum_file=$(get_checksum_path "$cache_path")
    
    # 检查缓存是否存在且有效
    if [[ -f "$cache_path" ]] && [[ -f "$checksum_file" ]]; then
        if verify_checksum "$cache_path" "$checksum_file"; then
            log_info "使用缓存的镜像: $cache_path"
            return 0
        else
            log_warn "缓存镜像校验失败，重新下载"
            rm -f "$cache_path" "$checksum_file"
        fi
    fi
    
    log_info "下载基础镜像: $image_name:$image_tag ($arch)"
    
    # 下载校验和（如果可用）
    download_checksum "$image_name" "$image_tag" "$arch" || true
    
    # 根据镜像类型选择下载方法
    case "$image_name" in
        "alpine")
            download_alpine_image "$image_tag" "$arch" "$cache_path"
            ;;
        *)
            download_docker_image "$image_name" "$image_tag" "$arch" "$cache_path"
            ;;
    esac
    
    # 验证或生成校验和
    if [[ -f "$checksum_file" ]]; then
        if ! verify_checksum "$cache_path" "$checksum_file"; then
            error_exit "下载的镜像校验失败"
        fi
    else
        generate_checksum "$cache_path" "$checksum_file"
    fi
    
    log_info "镜像下载完成: $cache_path"
}

# 获取 Alpine 架构名称映射
get_alpine_arch() {
    local arch="$1"
    case "$arch" in
        "amd64") echo "x86_64" ;;
        "arm64") echo "aarch64" ;;
        "armv7") echo "armv7" ;;
        *) echo "$arch" ;;
    esac
}

# 获取最新的 Alpine 版本
get_latest_alpine_version() {
    local major_minor="$1"  # 例如 "3.18"
    local arch="$2"
    local alpine_arch
    alpine_arch=$(get_alpine_arch "$arch")
    
    local base_url="https://dl-cdn.alpinelinux.org/alpine/v${major_minor}/releases/${alpine_arch}/"
    
    # 获取最新版本号
    local latest_version
    latest_version=$(curl -s "$base_url" | \
        grep -o "alpine-minirootfs-${major_minor}\.[0-9]*-${alpine_arch}\.tar\.gz" | \
        sed "s/alpine-minirootfs-\(${major_minor}\.[0-9]*\)-${alpine_arch}\.tar\.gz/\1/" | \
        sort -V | tail -1)
    
    if [[ -n "$latest_version" ]]; then
        echo "$latest_version"
    else
        # 如果无法获取最新版本，返回基础版本
        echo "${major_minor}.0"
    fi
}

# 下载 Alpine 镜像
download_alpine_image() {
    local tag="$1"
    local arch="$2"
    local output_path="$3"
    
    # 映射架构名称
    local alpine_arch
    alpine_arch=$(get_alpine_arch "$arch")
    
    # 如果 tag 只是主版本号（如 3.18），获取最新的补丁版本
    local full_version="$tag"
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_info "检测到主版本号 $tag，获取最新补丁版本..."
        full_version=$(get_latest_alpine_version "$tag" "$arch")
        log_info "使用 Alpine 版本: $full_version"
    fi
    
    # Alpine minirootfs 下载 URL
    local base_url="https://dl-cdn.alpinelinux.org/alpine"
    local version_path="v${full_version%.*}"  # 3.18.12 -> v3.18
    local filename="alpine-minirootfs-${full_version}-${alpine_arch}.tar.gz"
    local download_url="${base_url}/${version_path}/releases/${alpine_arch}/${filename}"
    
    log_info "从 Alpine 官方源下载: $download_url"
    
    # 使用 curl 下载，支持重试和进度显示
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -fsSL --connect-timeout 30 --max-time 300 \
               --retry 3 --retry-delay 5 \
               -o "$output_path" "$download_url"; then
            log_info "Alpine 镜像下载成功"
            return 0
        else
            retry_count=$((retry_count + 1))
            log_warn "下载失败，重试 $retry_count/$max_retries"
            sleep 5
        fi
    done
    
    error_exit "Alpine 镜像下载失败，已重试 $max_retries 次"
}

# 下载 Docker 镜像（备用方法）
download_docker_image() {
    local image_name="$1"
    local image_tag="$2"
    local arch="$3"
    local output_path="$4"
    
    log_info "使用 Docker 方式下载镜像: $image_name:$image_tag"
    
    # 检查 Docker 是否可用
    if ! command -v docker &> /dev/null; then
        error_exit "Docker 未安装或不可用"
    fi
    
    # 拉取镜像
    if ! docker pull --platform "linux/$arch" "$image_name:$image_tag"; then
        error_exit "Docker 镜像拉取失败"
    fi
    
    # 导出镜像
    if ! docker save "$image_name:$image_tag" | gzip > "$output_path"; then
        error_exit "Docker 镜像导出失败"
    fi
    
    log_info "Docker 镜像导出成功"
}

# 清理缓存
cleanup_cache() {
    local max_age_days="${1:-30}"  # 默认保留30天
    
    log_info "清理超过 $max_age_days 天的缓存文件"
    
    find "$CACHE_DIR" -type f -mtime +$max_age_days -name "*.tar.gz" -o -name "*.sha256" | while read -r file; do
        log_info "删除过期缓存: $file"
        rm -f "$file"
    done
}

# 显示缓存信息
show_cache_info() {
    log_info "缓存目录: $CACHE_DIR"
    
    if [[ -d "$CACHE_DIR" ]]; then
        local total_size
        total_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
        log_info "缓存总大小: $total_size"
        
        log_info "缓存文件列表:"
        find "$CACHE_DIR" -type f -name "*.tar.gz" | while read -r file; do
            local size
            size=$(du -sh "$file" | cut -f1)
            local mtime
            mtime=$(stat -c %y "$file" | cut -d' ' -f1)
            log_info "  $(basename "$file") - $size - $mtime"
        done
    else
        log_info "缓存目录不存在"
    fi
}

# 解析配置中的包列表
parse_packages_config() {
    # 读取要安装的包
    INSTALL_PACKAGES=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
            local package="${BASH_REMATCH[1]}"
            INSTALL_PACKAGES+=("$package")
        fi
    done < <(sed -n '/^[[:space:]]*packages:/,/^[[:space:]]*[^[:space:]-]/p' "$CONFIG_FILE" | grep '^[[:space:]]*-')
    
    # 读取要移除的包
    REMOVE_PACKAGES=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
            local package="${BASH_REMATCH[1]}"
            REMOVE_PACKAGES+=("$package")
        fi
    done < <(sed -n '/^[[:space:]]*remove_packages:/,/^[[:space:]]*[^[:space:]-]/p' "$CONFIG_FILE" | grep '^[[:space:]]*-')
    
    # 读取系统配置
    TIMEZONE=$(grep "timezone:" "$CONFIG_FILE" | sed 's/.*timezone: *"\([^"]*\)".*/\1/')
    LOCALE=$(grep "locale:" "$CONFIG_FILE" | sed 's/.*locale: *"\([^"]*\)".*/\1/')
    
    log_info "解析包配置完成: 安装 ${#INSTALL_PACKAGES[@]} 个包, 移除 ${#REMOVE_PACKAGES[@]} 个包"
}

# 安装系统包
install_system_packages() {
    local rootfs_path="$1"
    
    if [[ ${#INSTALL_PACKAGES[@]} -eq 0 ]]; then
        log_info "没有需要安装的包"
        return 0
    fi
    
    log_info "安装系统包: ${INSTALL_PACKAGES[*]}"
    
    # 在 chroot 环境中执行包安装
    cat > "${rootfs_path}/tmp/install_packages.sh" << 'EOF'
#!/bin/sh
set -e

# 更新包索引
apk update

# 安装包
for package in "$@"; do
    echo "安装包: $package"
    if ! apk add --no-cache "$package"; then
        echo "警告: 包 $package 安装失败，跳过"
    fi
done

# 清理包缓存
rm -rf /var/cache/apk/*
EOF
    
    chmod +x "${rootfs_path}/tmp/install_packages.sh"
    
    # 执行安装脚本
    if chroot "$rootfs_path" /tmp/install_packages.sh "${INSTALL_PACKAGES[@]}"; then
        log_info "系统包安装完成"
    else
        log_error "系统包安装失败"
        return 1
    fi
    
    # 清理安装脚本
    rm -f "${rootfs_path}/tmp/install_packages.sh"
}

# 移除不必要的包
remove_unnecessary_packages() {
    local rootfs_path="$1"
    
    if [[ ${#REMOVE_PACKAGES[@]} -eq 0 ]]; then
        log_info "没有需要移除的包"
        return 0
    fi
    
    log_info "移除不必要的包: ${REMOVE_PACKAGES[*]}"
    
    # 在 chroot 环境中执行包移除
    cat > "${rootfs_path}/tmp/remove_packages.sh" << 'EOF'
#!/bin/sh
set -e

# 移除包
for package in "$@"; do
    echo "移除包: $package"
    if apk info --installed "$package" >/dev/null 2>&1; then
        if ! apk del --no-cache "$package"; then
            echo "警告: 包 $package 移除失败，跳过"
        fi
    else
        echo "包 $package 未安装，跳过"
    fi
done

# 清理孤立的依赖
apk autoremove || true

# 清理包缓存
rm -rf /var/cache/apk/*
EOF
    
    chmod +x "${rootfs_path}/tmp/remove_packages.sh"
    
    # 执行移除脚本
    if chroot "$rootfs_path" /tmp/remove_packages.sh "${REMOVE_PACKAGES[@]}"; then
        log_info "不必要包移除完成"
    else
        log_warn "部分包移除失败，继续执行"
    fi
    
    # 清理移除脚本
    rm -f "${rootfs_path}/tmp/remove_packages.sh"
}

# 配置系统优化
configure_system_optimization() {
    local rootfs_path="$1"
    
    log_info "配置系统优化"
    
    # 配置时区
    if [[ -n "$TIMEZONE" ]]; then
        log_info "设置时区: $TIMEZONE"
        
        # 创建时区链接
        if [[ -f "${rootfs_path}/usr/share/zoneinfo/${TIMEZONE}" ]]; then
            ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${rootfs_path}/etc/localtime"
            echo "$TIMEZONE" > "${rootfs_path}/etc/timezone"
        else
            log_warn "时区文件不存在: $TIMEZONE，使用默认时区"
        fi
    fi
    
    # 配置语言环境
    if [[ -n "$LOCALE" ]]; then
        log_info "设置语言环境: $LOCALE"
        echo "export LANG=$LOCALE" >> "${rootfs_path}/etc/profile"
        echo "export LC_ALL=$LOCALE" >> "${rootfs_path}/etc/profile"
    fi
    
    # 优化系统配置
    configure_system_settings "$rootfs_path"
    
    # 清理系统文件
    cleanup_system_files "$rootfs_path"
    
    log_info "系统优化配置完成"
}

# 配置系统设置
configure_system_settings() {
    local rootfs_path="$1"
    
    log_info "配置系统设置"
    
    # 禁用不必要的服务
    local services_to_disable=("chronyd" "acpid" "crond")
    for service in "${services_to_disable[@]}"; do
        if [[ -f "${rootfs_path}/etc/init.d/${service}" ]]; then
            log_info "禁用服务: $service"
            chroot "$rootfs_path" rc-update del "$service" default 2>/dev/null || true
        fi
    done
    
    # 配置网络
    cat > "${rootfs_path}/etc/resolv.conf" << 'EOF'
# DNS configuration for LXC template
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    
    # 配置主机名
    echo "alpine-k3s" > "${rootfs_path}/etc/hostname"
    
    # 配置 hosts 文件
    cat > "${rootfs_path}/etc/hosts" << 'EOF'
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
127.0.1.1   alpine-k3s
EOF
    
    # 配置 sysctl 优化
    cat > "${rootfs_path}/etc/sysctl.d/99-k3s.conf" << 'EOF'
# K3s 优化配置
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv6.conf.all.forwarding = 1
vm.overcommit_memory = 1
kernel.panic = 10
kernel.panic_on_oops = 1
EOF
    
    # 配置内核模块
    cat > "${rootfs_path}/etc/modules-load.d/k3s.conf" << 'EOF'
# K3s 所需的内核模块
br_netfilter
overlay
iptable_nat
iptable_filter
EOF
    
    log_info "系统设置配置完成"
}

# 清理系统文件
cleanup_system_files() {
    local rootfs_path="$1"
    
    log_info "清理系统文件"
    
    # 清理路径列表
    local cleanup_paths=(
        "/tmp/*"
        "/var/cache/apk/*"
        "/var/log/*"
        "/var/tmp/*"
        "/usr/share/man/*"
        "/usr/share/doc/*"
        "/usr/share/info/*"
        "/usr/share/locale/*"
        "/var/cache/misc/*"
    )
    
    for path in "${cleanup_paths[@]}"; do
        local full_path="${rootfs_path}${path}"
        if ls $full_path >/dev/null 2>&1; then
            log_info "清理: $path"
            rm -rf $full_path 2>/dev/null || true
        fi
    done
    
    # 清理包管理器缓存
    rm -rf "${rootfs_path}/var/cache/apk"/*
    rm -rf "${rootfs_path}/etc/apk/cache"/*
    
    # 清理日志文件
    find "${rootfs_path}/var/log" -type f -name "*.log" -delete 2>/dev/null || true
    
    # 清理临时文件
    find "${rootfs_path}/tmp" -mindepth 1 -delete 2>/dev/null || true
    find "${rootfs_path}/var/tmp" -mindepth 1 -delete 2>/dev/null || true
    
    # 创建必要的空目录
    mkdir -p "${rootfs_path}/var/log"
    mkdir -p "${rootfs_path}/tmp"
    mkdir -p "${rootfs_path}/var/tmp"
    
    log_info "系统文件清理完成"
}

# 优化镜像大小
optimize_image_size() {
    local rootfs_path="$1"
    
    log_info "优化镜像大小"
    
    # 压缩可执行文件（如果安装了 upx）
    if command -v upx >/dev/null 2>&1; then
        log_info "压缩可执行文件"
        find "${rootfs_path}/usr/bin" "${rootfs_path}/bin" "${rootfs_path}/sbin" \
             -type f -executable -size +100k \
             -exec upx --best {} \; 2>/dev/null || true
    fi
    
    # 移除符号表信息
    find "${rootfs_path}" -type f -name "*.so*" -exec strip --strip-unneeded {} \; 2>/dev/null || true
    find "${rootfs_path}" -type f -executable -exec strip --strip-unneeded {} \; 2>/dev/null || true
    
    # 压缩内核模块
    find "${rootfs_path}/lib/modules" -name "*.ko" -exec gzip {} \; 2>/dev/null || true
    
    log_info "镜像大小优化完成"
}

# 处理系统包管理和优化
manage_system_packages() {
    local rootfs_path="$1"
    
    if [[ ! -d "$rootfs_path" ]]; then
        error_exit "根文件系统路径不存在: $rootfs_path"
    fi
    
    log_info "开始系统包管理和优化"
    
    # 解析配置
    parse_packages_config
    
    # 安装系统包
    install_system_packages "$rootfs_path"
    
    # 移除不必要的包
    remove_unnecessary_packages "$rootfs_path"
    
    # 配置系统优化
    configure_system_optimization "$rootfs_path"
    
    # 优化镜像大小
    optimize_image_size "$rootfs_path"
    
    log_info "系统包管理和优化完成"
}

# 主函数
main() {
    local action="${1:-download}"
    
    case "$action" in
        "download")
            log_info "开始基础镜像管理器"
            load_config
            parse_image_info "$BASE_IMAGE"
            check_version_compatibility "$IMAGE_TAG"
            download_base_image "$IMAGE_NAME" "$IMAGE_TAG" "$ARCHITECTURE"
            log_info "基础镜像管理完成"
            ;;
        "optimize")
            if [[ $# -lt 2 ]]; then
                error_exit "用法: $0 optimize <rootfs_path>"
            fi
            local rootfs_path="$2"
            load_config
            manage_system_packages "$rootfs_path"
            ;;
        "cleanup")
            cleanup_cache "${2:-30}"
            ;;
        "info")
            show_cache_info
            ;;
        "verify")
            if [[ $# -lt 2 ]]; then
                error_exit "用法: $0 verify <image_file>"
            fi
            local image_file="$2"
            local checksum_file="${image_file}.sha256"
            if verify_checksum "$image_file" "$checksum_file"; then
                log_info "镜像验证成功: $image_file"
            else
                error_exit "镜像验证失败: $image_file"
            fi
            ;;
        *)
            echo "用法: $0 {download|optimize|cleanup|info|verify}"
            echo "  download  - 下载和缓存基础镜像"
            echo "  optimize  - 系统包管理和优化 (参数: rootfs_path)"
            echo "  cleanup   - 清理过期缓存 (可选参数: 天数)"
            echo "  info      - 显示缓存信息"
            echo "  verify    - 验证镜像文件"
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi