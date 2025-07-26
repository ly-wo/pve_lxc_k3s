#!/bin/bash
# Build Performance Optimizer for PVE LXC K3s Template
# 构建性能优化器 - 优化脚本执行效率和资源使用

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_ROOT}/logs/build-optimizer.log"

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")"

# 加载日志系统
source "${SCRIPT_DIR}/logging.sh"

COMPONENT="build-optimizer"

# 性能配置
PARALLEL_JOBS="${BUILD_PARALLEL:-$(nproc 2>/dev/null || echo 2)}"
CACHE_ENABLED="${BUILD_CACHE:-true}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
MEMORY_LIMIT="${BUILD_MEMORY_LIMIT:-2G}"

# 日志函数
log_info() { 
    log_info "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "${4:-}" "$LOG_FILE"
}

log_warn() { 
    log_warn "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "$LOG_FILE"
}

log_error() { 
    log_error "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "$LOG_FILE"
}

log_performance() {
    log_performance "$COMPONENT" "$1" "$2" "${3:-{}}"
}

# 错误处理
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# 显示帮助信息
show_help() {
    cat <<EOF
构建性能优化器

用法: $0 [命令] [选项]

命令:
  optimize-scripts    优化脚本执行效率
  optimize-build      优化构建流程
  optimize-cache      优化缓存策略
  optimize-resources  优化资源使用
  benchmark          执行性能基准测试
  profile            分析性能瓶颈
  cleanup            清理优化缓存
  status             显示优化状态

选项:
  -j, --jobs N        并行任务数 (默认: CPU核心数)
  -c, --cache         启用缓存优化 (默认: true)
  -l, --level N       压缩级别 1-9 (默认: 6)
  -m, --memory SIZE   内存限制 (默认: 2G)
  -v, --verbose       详细输出
  -h, --help          显示帮助信息

环境变量:
  BUILD_PARALLEL      并行任务数
  BUILD_CACHE         启用构建缓存
  COMPRESSION_LEVEL   压缩级别
  BUILD_MEMORY_LIMIT  构建内存限制

示例:
  $0 optimize-scripts              # 优化脚本执行
  $0 optimize-build -j 4          # 使用4个并行任务优化构建
  $0 benchmark                    # 执行性能基准测试
  $0 profile                      # 分析性能瓶颈
EOF
}

# 检测系统性能特征
detect_system_capabilities() {
    log_info "检测系统性能特征"
    
    local cpu_cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
    local memory_gb=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 4)
    local disk_type="unknown"
    
    # 检测磁盘类型
    if [[ -f /sys/block/sda/queue/rotational ]]; then
        if [[ $(cat /sys/block/sda/queue/rotational) == "0" ]]; then
            disk_type="SSD"
        else
            disk_type="HDD"
        fi
    fi
    
    local capabilities="{
        \"cpu_cores\": $cpu_cores,
        \"memory_gb\": $memory_gb,
        \"disk_type\": \"$disk_type\",
        \"parallel_jobs\": $PARALLEL_JOBS
    }"
    
    log_info "系统性能特征" "$capabilities"
    
    # 根据系统特征调整参数
    if [[ $cpu_cores -gt 4 ]]; then
        PARALLEL_JOBS=$((cpu_cores - 1))
    fi
    
    if [[ $memory_gb -lt 2 ]]; then
        MEMORY_LIMIT="1G"
        log_warn "内存不足，降低内存限制到 1G"
    fi
    
    echo "$capabilities"
}

# 优化脚本执行效率
optimize_scripts() {
    log_info "开始优化脚本执行效率"
    
    local start_time=$(date +%s)
    local optimizations=0
    
    # 1. 并行化可并行的操作
    log_info "优化并行执行"
    
    # 创建并行执行包装器
    cat > "${PROJECT_ROOT}/.build/parallel-wrapper.sh" << 'EOF'
#!/bin/bash
# 并行执行包装器
set -euo pipefail

PARALLEL_JOBS="${1:-2}"
shift

# 创建任务队列
TASK_QUEUE=()
for task in "$@"; do
    TASK_QUEUE+=("$task")
done

# 并行执行任务
execute_parallel() {
    local max_jobs="$1"
    shift
    local tasks=("$@")
    local pids=()
    local task_index=0
    
    while [[ $task_index -lt ${#tasks[@]} ]] || [[ ${#pids[@]} -gt 0 ]]; do
        # 启动新任务
        while [[ ${#pids[@]} -lt $max_jobs ]] && [[ $task_index -lt ${#tasks[@]} ]]; do
            eval "${tasks[$task_index]}" &
            pids+=($!)
            ((task_index++))
        done
        
        # 等待任务完成
        local new_pids=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=("$pid")
            else
                wait "$pid"
            fi
        done
        pids=("${new_pids[@]}")
        
        sleep 0.1
    done
}

execute_parallel "$PARALLEL_JOBS" "${TASK_QUEUE[@]}"
EOF
    
    chmod +x "${PROJECT_ROOT}/.build/parallel-wrapper.sh"
    ((optimizations++))
    
    # 2. 优化文件操作
    log_info "优化文件操作"
    
    # 创建快速文件操作函数
    cat > "${PROJECT_ROOT}/.build/file-ops-optimized.sh" << 'EOF'
#!/bin/bash
# 优化的文件操作函数

# 快速复制（使用 rsync 或 cp 的最优选项）
fast_copy() {
    local src="$1"
    local dst="$2"
    
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --inplace --no-whole-file "$src" "$dst"
    else
        cp -a "$src" "$dst"
    fi
}

# 快速压缩（根据文件大小选择策略）
fast_compress() {
    local src="$1"
    local dst="$2"
    local level="${3:-6}"
    
    local size=$(du -sb "$src" | cut -f1)
    
    if [[ $size -lt 104857600 ]]; then  # < 100MB
        # 小文件使用高压缩比
        tar -czf "$dst" -C "$(dirname "$src")" "$(basename "$src")" --use-compress-program="gzip -$level"
    else
        # 大文件使用低压缩比但高速度
        tar -czf "$dst" -C "$(dirname "$src")" "$(basename "$src")" --use-compress-program="gzip -1"
    fi
}

# 快速解压
fast_extract() {
    local src="$1"
    local dst="$2"
    
    # 使用 pigz 如果可用（并行 gzip）
    if command -v pigz >/dev/null 2>&1; then
        tar -xf "$src" -C "$dst" --use-compress-program=pigz
    else
        tar -xzf "$src" -C "$dst"
    fi
}

# 快速删除大目录
fast_remove() {
    local target="$1"
    
    if [[ -d "$target" ]]; then
        # 使用 find + rm 比 rm -rf 更快处理大目录
        find "$target" -delete 2>/dev/null || rm -rf "$target"
    elif [[ -f "$target" ]]; then
        rm -f "$target"
    fi
}
EOF
    
    ((optimizations++))
    
    # 3. 缓存优化
    log_info "优化缓存策略"
    
    if [[ "$CACHE_ENABLED" == "true" ]]; then
        # 创建智能缓存管理器
        cat > "${PROJECT_ROOT}/.build/cache-manager.sh" << 'EOF'
#!/bin/bash
# 智能缓存管理器

CACHE_DIR="${PROJECT_ROOT}/.cache"
CACHE_INDEX="${CACHE_DIR}/index.json"

# 初始化缓存
init_cache() {
    mkdir -p "$CACHE_DIR"
    if [[ ! -f "$CACHE_INDEX" ]]; then
        echo '{}' > "$CACHE_INDEX"
    fi
}

# 计算文件哈希
calculate_hash() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        # 备用方案：使用文件大小和修改时间
        stat -c "%s-%Y" "$file" 2>/dev/null || stat -f "%z-%m" "$file"
    fi
}

# 检查缓存
check_cache() {
    local key="$1"
    local source_file="$2"
    
    init_cache
    
    local current_hash=$(calculate_hash "$source_file")
    local cached_hash=$(jq -r ".\"$key\".hash // empty" "$CACHE_INDEX" 2>/dev/null)
    
    if [[ "$current_hash" == "$cached_hash" ]] && [[ -f "${CACHE_DIR}/${key}" ]]; then
        return 0  # 缓存命中
    else
        return 1  # 缓存未命中
    fi
}

# 更新缓存
update_cache() {
    local key="$1"
    local source_file="$2"
    local cached_file="${CACHE_DIR}/${key}"
    
    init_cache
    
    local hash=$(calculate_hash "$source_file")
    cp "$source_file" "$cached_file"
    
    # 更新索引
    local temp_index=$(mktemp)
    jq ".\"$key\" = {\"hash\": \"$hash\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" "$CACHE_INDEX" > "$temp_index"
    mv "$temp_index" "$CACHE_INDEX"
}

# 清理过期缓存
cleanup_cache() {
    local max_age_days="${1:-7}"
    
    init_cache
    
    find "$CACHE_DIR" -type f -mtime +$max_age_days -delete 2>/dev/null || true
    
    # 重建索引
    echo '{}' > "$CACHE_INDEX"
}
EOF
        
        ((optimizations++))
    fi
    
    # 4. 内存优化
    log_info "优化内存使用"
    
    # 设置内存限制
    if command -v ulimit >/dev/null 2>&1; then
        # 转换内存限制为 KB
        local memory_kb
        case "$MEMORY_LIMIT" in
            *G|*g) memory_kb=$((${MEMORY_LIMIT%[Gg]} * 1024 * 1024)) ;;
            *M|*m) memory_kb=$((${MEMORY_LIMIT%[Mm]} * 1024)) ;;
            *K|*k) memory_kb=${MEMORY_LIMIT%[Kk]} ;;
            *) memory_kb=$((MEMORY_LIMIT * 1024)) ;;
        esac
        
        ulimit -v "$memory_kb" 2>/dev/null || log_warn "无法设置内存限制"
    fi
    
    ((optimizations++))
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_performance "脚本优化完成" "${duration}s" "{\"optimizations\": $optimizations, \"parallel_jobs\": $PARALLEL_JOBS}"
    
    echo "脚本执行优化完成，应用了 $optimizations 项优化"
}

# 优化构建流程
optimize_build_process() {
    log_info "开始优化构建流程"
    
    local start_time=$(date +%s)
    
    # 1. 创建优化的构建脚本
    log_info "创建优化的构建脚本"
    
    cat > "${PROJECT_ROOT}/.build/build-optimized.sh" << EOF
#!/bin/bash
# 优化的构建脚本
set -euo pipefail

# 加载优化函数
source "${PROJECT_ROOT}/.build/file-ops-optimized.sh"
source "${PROJECT_ROOT}/.build/cache-manager.sh"

# 并行下载和验证
parallel_download() {
    local urls=("\$@")
    local pids=()
    
    for url in "\${urls[@]}"; do
        {
            local filename="\$(basename "\$url")"
            if ! check_cache "download_\$filename" "\$url"; then
                curl -L -o "\${CACHE_DIR}/\$filename" "\$url"
                update_cache "download_\$filename" "\${CACHE_DIR}/\$filename"
            fi
        } &
        pids+=(\$!)
        
        # 限制并发数
        if [[ \${#pids[@]} -ge $PARALLEL_JOBS ]]; then
            wait "\${pids[0]}"
            pids=("\${pids[@]:1}")
        fi
    done
    
    # 等待所有下载完成
    for pid in "\${pids[@]}"; do
        wait "\$pid"
    done
}

# 优化的包安装
optimized_package_install() {
    local packages=("\$@")
    
    # 批量安装而不是逐个安装
    if [[ \${#packages[@]} -gt 0 ]]; then
        apk add --no-cache "\${packages[@]}"
    fi
}

# 优化的文件系统操作
optimized_filesystem_ops() {
    # 使用内存文件系统加速临时操作
    if [[ -w /dev/shm ]] && [[ \$(df /dev/shm | tail -1 | awk '{print \$4}') -gt 1048576 ]]; then
        export TMPDIR="/dev/shm"
        log_info "使用内存文件系统加速临时操作"
    fi
    
    # 优化文件系统挂载选项
    if mount | grep -q "on / type"; then
        mount -o remount,noatime / 2>/dev/null || true
    fi
}

EOF
    
    chmod +x "${PROJECT_ROOT}/.build/build-optimized.sh"
    
    # 2. 创建构建性能监控
    log_info "创建构建性能监控"
    
    cat > "${PROJECT_ROOT}/.build/build-monitor.sh" << 'EOF'
#!/bin/bash
# 构建性能监控

MONITOR_LOG="${PROJECT_ROOT}/logs/build-performance.log"
MONITOR_PID_FILE="${PROJECT_ROOT}/.build/monitor.pid"

start_monitoring() {
    {
        echo $$ > "$MONITOR_PID_FILE"
        while kill -0 $$ 2>/dev/null; do
            local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "0")
            local memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "0")
            local disk_io=$(iostat -d 1 1 2>/dev/null | tail -n +4 | awk '{sum+=$4} END {print sum}' || echo "0")
            
            echo "$timestamp,CPU:$cpu_usage,MEM:$memory_usage,IO:$disk_io" >> "$MONITOR_LOG"
            sleep 5
        done
    } &
    
    local monitor_pid=$!
    echo "$monitor_pid" > "$MONITOR_PID_FILE"
}

stop_monitoring() {
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        local pid=$(cat "$MONITOR_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$MONITOR_PID_FILE"
    fi
}

# 信号处理
trap stop_monitoring EXIT INT TERM
EOF
    
    chmod +x "${PROJECT_ROOT}/.build/build-monitor.sh"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_performance "构建流程优化完成" "${duration}s" "{\"parallel_jobs\": $PARALLEL_JOBS}"
    
    echo "构建流程优化完成"
}

# 优化资源使用
optimize_resources() {
    log_info "开始优化资源使用"
    
    local start_time=$(date +%s)
    
    # 1. CPU 优化
    log_info "优化 CPU 使用"
    
    # 设置 CPU 亲和性（如果支持）
    if command -v taskset >/dev/null 2>&1; then
        local cpu_count=$(nproc)
        if [[ $cpu_count -gt 2 ]]; then
            # 为构建进程预留部分 CPU
            local build_cpus="0-$((cpu_count - 2))"
            export TASKSET_CPUS="$build_cpus"
            log_info "设置 CPU 亲和性: $build_cpus"
        fi
    fi
    
    # 2. 内存优化
    log_info "优化内存使用"
    
    # 创建内存监控和清理脚本
    cat > "${PROJECT_ROOT}/.build/memory-optimizer.sh" << 'EOF'
#!/bin/bash
# 内存优化器

# 监控内存使用并在必要时清理
monitor_memory() {
    while true; do
        local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        
        if [[ $memory_usage -gt 85 ]]; then
            echo "内存使用率过高 ($memory_usage%)，执行清理"
            
            # 清理页面缓存
            sync
            echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
            
            # 清理临时文件
            find /tmp -type f -atime +0 -delete 2>/dev/null || true
            
            # 强制垃圾回收（如果是在容器中）
            if [[ -f /.dockerenv ]]; then
                echo "容器环境，执行内存整理"
            fi
        fi
        
        sleep 30
    done
}

# 设置内存限制
set_memory_limits() {
    local limit="$1"
    
    # 设置进程内存限制
    ulimit -v "$((limit * 1024))" 2>/dev/null || true
    
    # 设置 cgroup 限制（如果支持）
    if [[ -w /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
        echo "$((limit * 1024 * 1024))" > /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || true
    fi
}
EOF
    
    chmod +x "${PROJECT_ROOT}/.build/memory-optimizer.sh"
    
    # 3. 磁盘 I/O 优化
    log_info "优化磁盘 I/O"
    
    # 创建 I/O 优化脚本
    cat > "${PROJECT_ROOT}/.build/io-optimizer.sh" << 'EOF'
#!/bin/bash
# 磁盘 I/O 优化器

# 优化 I/O 调度器
optimize_io_scheduler() {
    for disk in /sys/block/*/queue/scheduler; do
        if [[ -w "$disk" ]]; then
            # SSD 使用 noop 或 deadline，HDD 使用 cfq
            local device=$(echo "$disk" | cut -d'/' -f4)
            local rotational="/sys/block/$device/queue/rotational"
            
            if [[ -f "$rotational" ]] && [[ $(cat "$rotational") == "0" ]]; then
                # SSD
                echo "deadline" > "$disk" 2>/dev/null || echo "noop" > "$disk" 2>/dev/null || true
            else
                # HDD
                echo "cfq" > "$disk" 2>/dev/null || true
            fi
        fi
    done
}

# 优化文件系统参数
optimize_filesystem() {
    # 增加 dirty ratio 以减少频繁写入
    echo 15 > /proc/sys/vm/dirty_ratio 2>/dev/null || true
    echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null || true
    
    # 增加 dirty 过期时间
    echo 3000 > /proc/sys/vm/dirty_expire_centisecs 2>/dev/null || true
    echo 1500 > /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null || true
}

# 创建高速临时目录
setup_fast_tmpdir() {
    local tmpdir="/dev/shm/build-tmp"
    
    if [[ -w /dev/shm ]] && [[ $(df /dev/shm | tail -1 | awk '{print $4}') -gt 524288 ]]; then
        mkdir -p "$tmpdir"
        export TMPDIR="$tmpdir"
        echo "使用内存文件系统作为临时目录: $tmpdir"
    fi
}
EOF
    
    chmod +x "${PROJECT_ROOT}/.build/io-optimizer.sh"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_performance "资源优化完成" "${duration}s" "{\"memory_limit\": \"$MEMORY_LIMIT\"}"
    
    echo "资源使用优化完成"
}

# 执行性能基准测试
run_benchmark() {
    log_info "开始执行性能基准测试"
    
    local benchmark_dir="${PROJECT_ROOT}/.build/benchmark"
    mkdir -p "$benchmark_dir"
    
    local results_file="$benchmark_dir/results-$(date +%Y%m%d-%H%M%S).json"
    
    # 1. CPU 基准测试
    log_info "执行 CPU 基准测试"
    local cpu_start=$(date +%s.%N)
    
    # 简单的 CPU 密集型任务
    for i in {1..1000}; do
        echo "scale=100; 4*a(1)" | bc -l >/dev/null 2>&1 || true
    done
    
    local cpu_end=$(date +%s.%N)
    local cpu_duration=$(echo "$cpu_end - $cpu_start" | bc -l 2>/dev/null || echo "0")
    
    # 2. 内存基准测试
    log_info "执行内存基准测试"
    local mem_start=$(date +%s.%N)
    
    # 创建和释放大量小对象
    local temp_files=()
    for i in {1..100}; do
        local temp_file=$(mktemp)
        dd if=/dev/zero of="$temp_file" bs=1M count=1 2>/dev/null || true
        temp_files+=("$temp_file")
    done
    
    # 清理
    for file in "${temp_files[@]}"; do
        rm -f "$file"
    done
    
    local mem_end=$(date +%s.%N)
    local mem_duration=$(echo "$mem_end - $mem_start" | bc -l 2>/dev/null || echo "0")
    
    # 3. 磁盘 I/O 基准测试
    log_info "执行磁盘 I/O 基准测试"
    local io_start=$(date +%s.%N)
    
    local test_file="$benchmark_dir/io-test"
    dd if=/dev/zero of="$test_file" bs=1M count=100 2>/dev/null || true
    sync
    dd if="$test_file" of=/dev/null bs=1M 2>/dev/null || true
    rm -f "$test_file"
    
    local io_end=$(date +%s.%N)
    local io_duration=$(echo "$io_end - $io_start" | bc -l 2>/dev/null || echo "0")
    
    # 4. 网络基准测试（如果适用）
    log_info "执行网络基准测试"
    local net_start=$(date +%s.%N)
    
    # 测试 DNS 解析速度
    for domain in google.com github.com alpine.org; do
        nslookup "$domain" >/dev/null 2>&1 || true
    done
    
    local net_end=$(date +%s.%N)
    local net_duration=$(echo "$net_end - $net_start" | bc -l 2>/dev/null || echo "0")
    
    # 生成基准测试报告
    cat > "$results_file" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "system": {
    "cpu_cores": $(nproc 2>/dev/null || echo 1),
    "memory_gb": $(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 4),
    "hostname": "$(hostname)"
  },
  "benchmarks": {
    "cpu": {
      "duration": "$cpu_duration",
      "operations": 1000,
      "ops_per_second": $(echo "scale=2; 1000 / $cpu_duration" | bc -l 2>/dev/null || echo "0")
    },
    "memory": {
      "duration": "$mem_duration",
      "operations": 100,
      "mb_per_second": $(echo "scale=2; 100 / $mem_duration" | bc -l 2>/dev/null || echo "0")
    },
    "disk_io": {
      "duration": "$io_duration",
      "size_mb": 100,
      "mb_per_second": $(echo "scale=2; 100 / $io_duration" | bc -l 2>/dev/null || echo "0")
    },
    "network": {
      "duration": "$net_duration",
      "dns_queries": 3,
      "queries_per_second": $(echo "scale=2; 3 / $net_duration" | bc -l 2>/dev/null || echo "0")
    }
  },
  "configuration": {
    "parallel_jobs": $PARALLEL_JOBS,
    "cache_enabled": $CACHE_ENABLED,
    "compression_level": $COMPRESSION_LEVEL,
    "memory_limit": "$MEMORY_LIMIT"
  }
}
EOF
    
    log_performance "基准测试完成" "${cpu_duration}s" "$(cat "$results_file")"
    
    echo "基准测试完成，结果保存到: $results_file"
    
    # 显示简要结果
    echo ""
    echo "=== 基准测试结果 ==="
    echo "CPU 性能: $(echo "scale=0; 1000 / $cpu_duration" | bc -l 2>/dev/null || echo "N/A") ops/sec"
    echo "内存性能: $(echo "scale=0; 100 / $mem_duration" | bc -l 2>/dev/null || echo "N/A") MB/sec"
    echo "磁盘 I/O: $(echo "scale=0; 100 / $io_duration" | bc -l 2>/dev/null || echo "N/A") MB/sec"
    echo "网络延迟: $(echo "scale=2; $net_duration / 3" | bc -l 2>/dev/null || echo "N/A") sec/query"
}

# 分析性能瓶颈
profile_performance() {
    log_info "开始分析性能瓶颈"
    
    local profile_dir="${PROJECT_ROOT}/.build/profile"
    mkdir -p "$profile_dir"
    
    # 1. 分析脚本执行时间
    log_info "分析脚本执行时间"
    
    local scripts_to_profile=(
        "build-template.sh"
        "k3s-installer.sh"
        "system-optimizer.sh"
        "security-hardening.sh"
        "packager.sh"
    )
    
    for script in "${scripts_to_profile[@]}"; do
        if [[ -f "${SCRIPT_DIR}/$script" ]]; then
            log_info "分析脚本: $script"
            
            # 使用 time 命令分析执行时间
            local time_output
            time_output=$(time bash -n "${SCRIPT_DIR}/$script" 2>&1 || echo "语法检查失败")
            
            echo "脚本: $script" >> "$profile_dir/script-analysis.txt"
            echo "$time_output" >> "$profile_dir/script-analysis.txt"
            echo "---" >> "$profile_dir/script-analysis.txt"
        fi
    done
    
    # 2. 分析系统资源使用
    log_info "分析系统资源使用"
    
    # 创建资源使用分析脚本
    cat > "$profile_dir/resource-analyzer.sh" << 'EOF'
#!/bin/bash
# 资源使用分析器

analyze_cpu_usage() {
    echo "=== CPU 使用分析 ==="
    
    # CPU 信息
    if [[ -f /proc/cpuinfo ]]; then
        echo "CPU 核心数: $(nproc)"
        echo "CPU 型号: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    fi
    
    # 当前 CPU 使用率
    if command -v top >/dev/null 2>&1; then
        echo "当前 CPU 使用率:"
        top -bn1 | grep "Cpu(s)" || echo "无法获取 CPU 使用率"
    fi
    
    echo ""
}

analyze_memory_usage() {
    echo "=== 内存使用分析 ==="
    
    if command -v free >/dev/null 2>&1; then
        free -h
    else
        echo "无法获取内存信息"
    fi
    
    echo ""
}

analyze_disk_usage() {
    echo "=== 磁盘使用分析 ==="
    
    df -h
    
    echo ""
    echo "I/O 统计:"
    if command -v iostat >/dev/null 2>&1; then
        iostat -d 1 1
    else
        echo "iostat 不可用"
    fi
    
    echo ""
}

analyze_network_usage() {
    echo "=== 网络使用分析 ==="
    
    if command -v ss >/dev/null 2>&1; then
        echo "网络连接统计:"
        ss -s
    elif command -v netstat >/dev/null 2>&1; then
        echo "网络连接统计:"
        netstat -s | head -20
    else
        echo "无法获取网络统计"
    fi
    
    echo ""
}

# 执行所有分析
analyze_cpu_usage
analyze_memory_usage
analyze_disk_usage
analyze_network_usage
EOF
    
    chmod +x "$profile_dir/resource-analyzer.sh"
    "$profile_dir/resource-analyzer.sh" > "$profile_dir/resource-analysis.txt"
    
    # 3. 生成性能分析报告
    log_info "生成性能分析报告"
    
    cat > "$profile_dir/performance-report.md" << EOF
# 性能分析报告

生成时间: $(date)
系统信息: $(uname -a)

## 脚本分析

\`\`\`
$(cat "$profile_dir/script-analysis.txt" 2>/dev/null || echo "脚本分析数据不可用")
\`\`\`

## 资源使用分析

\`\`\`
$(cat "$profile_dir/resource-analysis.txt" 2>/dev/null || echo "资源分析数据不可用")
\`\`\`

## 优化建议

### CPU 优化
- 当前并行任务数: $PARALLEL_JOBS
- 建议: 根据 CPU 核心数调整并行度

### 内存优化
- 当前内存限制: $MEMORY_LIMIT
- 建议: 监控内存使用，适当调整限制

### 磁盘 I/O 优化
- 当前压缩级别: $COMPRESSION_LEVEL
- 建议: 根据磁盘类型调整压缩策略

### 缓存优化
- 缓存状态: $CACHE_ENABLED
- 建议: 启用缓存以加速重复构建

## 性能瓶颈识别

$(if [[ -f "$profile_dir/script-analysis.txt" ]]; then
    echo "### 脚本执行瓶颈"
    grep -E "(real|user|sys)" "$profile_dir/script-analysis.txt" | head -10
fi)

## 下一步行动

1. 根据分析结果调整配置参数
2. 实施建议的优化措施
3. 重新运行基准测试验证改进
4. 监控生产环境性能表现
EOF
    
    log_info "性能分析完成，报告保存到: $profile_dir/performance-report.md"
    
    echo "性能分析完成"
    echo "详细报告: $profile_dir/performance-report.md"
    echo "资源分析: $profile_dir/resource-analysis.txt"
    echo "脚本分析: $profile_dir/script-analysis.txt"
}

# 清理优化缓存
cleanup_optimization() {
    log_info "清理优化缓存"
    
    local cleanup_items=(
        "${PROJECT_ROOT}/.build/parallel-wrapper.sh"
        "${PROJECT_ROOT}/.build/file-ops-optimized.sh"
        "${PROJECT_ROOT}/.build/cache-manager.sh"
        "${PROJECT_ROOT}/.build/build-optimized.sh"
        "${PROJECT_ROOT}/.build/build-monitor.sh"
        "${PROJECT_ROOT}/.build/memory-optimizer.sh"
        "${PROJECT_ROOT}/.build/io-optimizer.sh"
        "${PROJECT_ROOT}/.build/benchmark"
        "${PROJECT_ROOT}/.build/profile"
        "${PROJECT_ROOT}/.cache"
    )
    
    for item in "${cleanup_items[@]}"; do
        if [[ -e "$item" ]]; then
            rm -rf "$item"
            log_info "已清理: $item"
        fi
    done
    
    echo "优化缓存清理完成"
}

# 显示优化状态
show_optimization_status() {
    echo "=== 构建优化状态 ==="
    echo ""
    
    echo "配置参数:"
    echo "  并行任务数: $PARALLEL_JOBS"
    echo "  缓存启用: $CACHE_ENABLED"
    echo "  压缩级别: $COMPRESSION_LEVEL"
    echo "  内存限制: $MEMORY_LIMIT"
    echo ""
    
    echo "优化组件状态:"
    local components=(
        "parallel-wrapper.sh:并行执行包装器"
        "file-ops-optimized.sh:文件操作优化"
        "cache-manager.sh:缓存管理器"
        "build-optimized.sh:优化构建脚本"
        "memory-optimizer.sh:内存优化器"
        "io-optimizer.sh:I/O优化器"
    )
    
    for component in "${components[@]}"; do
        local file="${component%:*}"
        local desc="${component#*:}"
        
        if [[ -f "${PROJECT_ROOT}/.build/$file" ]]; then
            echo "  ✓ $desc"
        else
            echo "  ✗ $desc"
        fi
    done
    
    echo ""
    
    # 显示最近的基准测试结果
    local latest_benchmark=$(find "${PROJECT_ROOT}/.build/benchmark" -name "results-*.json" -type f 2>/dev/null | sort | tail -1)
    if [[ -n "$latest_benchmark" ]]; then
        echo "最近的基准测试结果:"
        echo "  文件: $latest_benchmark"
        echo "  时间: $(jq -r '.timestamp // "未知"' "$latest_benchmark" 2>/dev/null)"
        
        local cpu_ops=$(jq -r '.benchmarks.cpu.ops_per_second // "N/A"' "$latest_benchmark" 2>/dev/null)
        local mem_speed=$(jq -r '.benchmarks.memory.mb_per_second // "N/A"' "$latest_benchmark" 2>/dev/null)
        local io_speed=$(jq -r '.benchmarks.disk_io.mb_per_second // "N/A"' "$latest_benchmark" 2>/dev/null)
        
        echo "  CPU 性能: $cpu_ops ops/sec"
        echo "  内存性能: $mem_speed MB/sec"
        echo "  磁盘 I/O: $io_speed MB/sec"
    else
        echo "无基准测试结果，运行 'benchmark' 命令执行测试"
    fi
}

# 主函数
main() {
    local command=""
    local jobs=""
    local cache=""
    local level=""
    local memory=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            optimize-scripts|optimize-build|optimize-cache|optimize-resources|benchmark|profile|cleanup|status)
                command="$1"
                shift
                ;;
            -j|--jobs)
                jobs="$2"
                shift 2
                ;;
            -c|--cache)
                cache="true"
                shift
                ;;
            -l|--level)
                level="$2"
                shift 2
                ;;
            -m|--memory)
                memory="$2"
                shift 2
                ;;
            -v|--verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 应用参数
    [[ -n "$jobs" ]] && PARALLEL_JOBS="$jobs"
    [[ -n "$cache" ]] && CACHE_ENABLED="$cache"
    [[ -n "$level" ]] && COMPRESSION_LEVEL="$level"
    [[ -n "$memory" ]] && MEMORY_LIMIT="$memory"
    
    # 创建构建目录
    mkdir -p "${PROJECT_ROOT}/.build"
    
    # 检测系统能力
    detect_system_capabilities >/dev/null
    
    # 执行命令
    case "$command" in
        "optimize-scripts")
            optimize_scripts
            ;;
        "optimize-build")
            optimize_build_process
            ;;
        "optimize-cache")
            if [[ "$CACHE_ENABLED" == "true" ]]; then
                optimize_scripts  # 包含缓存优化
                echo "缓存优化完成"
            else
                echo "缓存未启用，使用 -c 选项启用缓存"
            fi
            ;;
        "optimize-resources")
            optimize_resources
            ;;
        "benchmark")
            run_benchmark
            ;;
        "profile")
            profile_performance
            ;;
        "cleanup")
            cleanup_optimization
            ;;
        "status")
            show_optimization_status
            ;;
        "")
            echo "请指定命令"
            show_help
            exit 1
            ;;
        *)
            echo "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi