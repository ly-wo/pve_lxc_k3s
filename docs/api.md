# API 文档

本文档详细描述了 PVE LXC K3s 模板生成器的脚本接口和函数 API。

## 概述

项目采用模块化设计，每个脚本都提供标准化的命令行接口和函数 API。所有脚本都遵循统一的接口规范，便于集成和扩展。

## 通用接口规范

### 命令行接口

所有脚本都支持以下通用选项：

```bash
script-name.sh [GLOBAL_OPTIONS] COMMAND [COMMAND_OPTIONS] [ARGUMENTS]
```

#### 全局选项

| 选项 | 描述 | 默认值 |
|------|------|--------|
| `--config FILE` | 指定配置文件路径 | `config/template.yaml` |
| `--debug` | 启用调试模式 | `false` |
| `--verbose` | 详细输出模式 | `false` |
| `--quiet` | 静默模式 | `false` |
| `--help` | 显示帮助信息 | - |
| `--version` | 显示版本信息 | - |

#### 返回码规范

| 返回码 | 含义 | 使用场景 |
|--------|------|----------|
| `0` | 成功 | 正常执行完成 |
| `1` | 一般错误 | 脚本执行失败 |
| `2` | 参数错误 | 命令行参数无效 |
| `3` | 配置错误 | 配置文件问题 |
| `4` | 网络错误 | 网络连接失败 |
| `5` | 权限错误 | 文件或目录权限不足 |
| `6` | 资源不足 | 磁盘空间或内存不足 |

### 环境变量

| 变量名 | 描述 | 默认值 |
|--------|------|--------|
| `DEBUG` | 全局调试开关 | `0` |
| `CONFIG_FILE` | 默认配置文件路径 | `config/template.yaml` |
| `LOG_LEVEL` | 日志级别 | `INFO` |
| `OUTPUT_DIR` | 输出目录 | `output` |

## 核心脚本 API

### build-template.sh

主构建脚本，协调整个模板构建流程。

#### 命令行接口

```bash
./scripts/build-template.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `build` | 构建模板（默认） | 无 |
| `clean` | 清理构建输出 | 无 |
| `status` | 显示构建状态 | 无 |

#### 选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `--output-dir DIR` | 指定输出目录 | `--output-dir /tmp/build` |
| `--base-image IMAGE` | 指定基础镜像 | `--base-image alpine:3.18` |
| `--k3s-version VERSION` | 指定 K3s 版本 | `--k3s-version v1.28.4+k3s1` |
| `--no-cache` | 禁用构建缓存 | `--no-cache` |

#### 示例

```bash
# 基本构建
./scripts/build-template.sh build

# 使用自定义配置构建
./scripts/build-template.sh --config config/prod.yaml build

# 指定输出目录
./scripts/build-template.sh --output-dir /tmp/output build

# 调试模式构建
./scripts/build-template.sh --debug build
```

#### 函数 API

```bash
# 主构建函数
build_template() {
    # 参数: 无
    # 返回: 0=成功, 1=失败
    # 描述: 执行完整的模板构建流程
}

# 清理函数
clean_build() {
    # 参数: 无
    # 返回: 0=成功, 1=失败
    # 描述: 清理构建输出和临时文件
}

# 状态检查函数
check_build_status() {
    # 参数: 无
    # 返回: 0=构建完成, 1=构建中, 2=构建失败
    # 描述: 检查当前构建状态
}
```

### config-loader.sh

配置文件加载和解析脚本。

#### 命令行接口

```bash
./scripts/config-loader.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `load` | 加载配置（默认） | 无 |
| `validate` | 验证配置文件 | 无 |
| `get KEY` | 获取配置值 | 配置键名 |
| `set KEY VALUE` | 设置配置值 | 键名和值 |

#### 示例

```bash
# 加载配置
./scripts/config-loader.sh load

# 验证配置
./scripts/config-loader.sh validate

# 获取配置值
./scripts/config-loader.sh get template.name

# 设置配置值
./scripts/config-loader.sh set k3s.version v1.28.5+k3s1
```

#### 函数 API

```bash
# 加载配置文件
load_config() {
    local config_file="${1:-$CONFIG_FILE}"
    # 参数: config_file - 配置文件路径
    # 返回: 0=成功, 3=配置错误
    # 描述: 加载并解析 YAML 配置文件
}

# 获取配置值
get_config() {
    local key="$1"
    # 参数: key - 配置键名（支持点号分隔）
    # 返回: 配置值（字符串）
    # 描述: 获取指定键的配置值
}

# 验证配置
validate_config() {
    local config_file="${1:-$CONFIG_FILE}"
    # 参数: config_file - 配置文件路径
    # 返回: 0=有效, 3=无效
    # 描述: 验证配置文件格式和必需字段
}
```

### base-image-manager.sh

基础镜像管理脚本。

#### 命令行接口

```bash
./scripts/base-image-manager.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `download` | 下载基础镜像 | 无 |
| `verify` | 验证镜像完整性 | 无 |
| `prepare` | 准备镜像环境 | 无 |
| `cleanup` | 清理镜像缓存 | 无 |

#### 选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `--image IMAGE` | 指定镜像名称 | `--image alpine:3.18` |
| `--cache-dir DIR` | 指定缓存目录 | `--cache-dir /tmp/cache` |
| `--force` | 强制重新下载 | `--force` |

#### 示例

```bash
# 下载默认镜像
./scripts/base-image-manager.sh download

# 下载指定镜像
./scripts/base-image-manager.sh --image alpine:3.17 download

# 验证镜像
./scripts/base-image-manager.sh verify

# 强制重新下载
./scripts/base-image-manager.sh --force download
```

#### 函数 API

```bash
# 下载基础镜像
download_base_image() {
    local image_name="$1"
    local cache_dir="${2:-cache}"
    # 参数: image_name - 镜像名称, cache_dir - 缓存目录
    # 返回: 0=成功, 4=网络错误
    # 描述: 下载并缓存基础镜像
}

# 验证镜像完整性
verify_image() {
    local image_path="$1"
    # 参数: image_path - 镜像文件路径
    # 返回: 0=验证通过, 1=验证失败
    # 描述: 验证镜像文件的完整性和签名
}

# 准备镜像环境
prepare_image_env() {
    local image_path="$1"
    local work_dir="$2"
    # 参数: image_path - 镜像路径, work_dir - 工作目录
    # 返回: 0=成功, 1=失败
    # 描述: 解压镜像并准备构建环境
}
```

### k3s-installer.sh

K3s 安装和配置脚本。

#### 命令行接口

```bash
./scripts/k3s-installer.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `install` | 安装 K3s（默认） | 无 |
| `configure` | 配置 K3s 服务 | 无 |
| `uninstall` | 卸载 K3s | 无 |
| `status` | 检查 K3s 状态 | 无 |

#### 选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `--version VERSION` | 指定 K3s 版本 | `--version v1.28.4+k3s1` |
| `--install-dir DIR` | 安装目录 | `--install-dir /usr/local/bin` |
| `--config-file FILE` | K3s 配置文件 | `--config-file k3s.yaml` |
| `--server` | 安装为服务器模式 | `--server` |
| `--agent` | 安装为代理模式 | `--agent` |

#### 示例

```bash
# 安装默认版本 K3s
./scripts/k3s-installer.sh install

# 安装指定版本
./scripts/k3s-installer.sh --version v1.28.5+k3s1 install

# 配置 K3s 服务
./scripts/k3s-installer.sh configure

# 检查状态
./scripts/k3s-installer.sh status
```

#### 函数 API

```bash
# 安装 K3s
install_k3s() {
    local version="$1"
    local install_dir="${2:-/usr/local/bin}"
    # 参数: version - K3s 版本, install_dir - 安装目录
    # 返回: 0=成功, 4=网络错误, 5=权限错误
    # 描述: 下载并安装 K3s 二进制文件
}

# 配置 K3s 服务
configure_k3s_service() {
    local config_file="$1"
    # 参数: config_file - 配置文件路径
    # 返回: 0=成功, 3=配置错误
    # 描述: 创建 systemd 服务文件和配置
}

# 检查 K3s 状态
check_k3s_status() {
    # 参数: 无
    # 返回: 0=运行中, 1=已停止, 2=错误状态
    # 描述: 检查 K3s 服务运行状态
}
```

### security-hardening.sh

安全加固脚本。

#### 命令行接口

```bash
./scripts/security-hardening.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `harden` | 执行安全加固（默认） | 无 |
| `audit` | 安全审计 | 无 |
| `restore` | 恢复默认设置 | 无 |

#### 选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `--level LEVEL` | 安全级别 | `--level strict` |
| `--skip-firewall` | 跳过防火墙配置 | `--skip-firewall` |
| `--custom-rules FILE` | 自定义规则文件 | `--custom-rules rules.yaml` |

#### 示例

```bash
# 执行标准安全加固
./scripts/security-hardening.sh harden

# 执行严格安全加固
./scripts/security-hardening.sh --level strict harden

# 安全审计
./scripts/security-hardening.sh audit
```

#### 函数 API

```bash
# 系统安全加固
harden_system() {
    local level="${1:-standard}"
    # 参数: level - 安全级别 (standard|strict)
    # 返回: 0=成功, 5=权限错误
    # 描述: 执行系统级安全加固
}

# 配置防火墙
configure_firewall() {
    local rules_file="$1"
    # 参数: rules_file - 防火墙规则文件
    # 返回: 0=成功, 5=权限错误
    # 描述: 配置防火墙规则
}

# 安全审计
security_audit() {
    # 参数: 无
    # 返回: 0=通过, 1=发现问题
    # 描述: 执行安全配置审计
}
```

### packager.sh

模板打包脚本。

#### 命令行接口

```bash
./scripts/packager.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `package` | 打包模板（默认） | 无 |
| `verify` | 验证模板包 | 模板文件路径 |
| `info` | 显示模板信息 | 模板文件路径 |
| `clean` | 清理输出目录 | 无 |

#### 选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `--output FILE` | 输出文件名 | `--output template.tar.gz` |
| `--compress LEVEL` | 压缩级别 | `--compress 9` |
| `--exclude PATTERN` | 排除文件模式 | `--exclude "*.log"` |

#### 示例

```bash
# 打包模板
./scripts/packager.sh package

# 指定输出文件
./scripts/packager.sh --output custom-template.tar.gz package

# 验证模板包
./scripts/packager.sh verify output/template.tar.gz

# 显示模板信息
./scripts/packager.sh info output/template.tar.gz
```

#### 函数 API

```bash
# 打包模板
package_template() {
    local source_dir="$1"
    local output_file="$2"
    # 参数: source_dir - 源目录, output_file - 输出文件
    # 返回: 0=成功, 6=磁盘空间不足
    # 描述: 将构建结果打包为 LXC 模板
}

# 验证模板包
verify_package() {
    local package_file="$1"
    # 参数: package_file - 模板包文件路径
    # 返回: 0=验证通过, 1=验证失败
    # 描述: 验证模板包的完整性和格式
}

# 提取模板信息
extract_template_info() {
    local package_file="$1"
    # 参数: package_file - 模板包文件路径
    # 返回: JSON 格式的模板信息
    # 描述: 提取模板的元数据信息
}
```

### template-validator.sh

模板验证脚本。

#### 命令行接口

```bash
./scripts/template-validator.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `validate` | 完整验证（默认） | 模板文件路径 |
| `quick` | 快速验证 | 模板文件路径 |
| `package-only` | 仅验证包格式 | 模板文件路径 |
| `performance` | 性能测试 | 模板文件路径 |

#### 选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `--timeout SECONDS` | 测试超时时间 | `--timeout 300` |
| `--skip-docker` | 跳过 Docker 测试 | `--skip-docker` |
| `--report FILE` | 生成测试报告 | `--report report.json` |

#### 示例

```bash
# 完整验证
./scripts/template-validator.sh validate output/template.tar.gz

# 快速验证
./scripts/template-validator.sh quick output/template.tar.gz

# 性能测试
./scripts/template-validator.sh performance output/template.tar.gz

# 生成报告
./scripts/template-validator.sh --report validation-report.json validate
```

#### 函数 API

```bash
# 验证模板包
validate_template_package() {
    local package_file="$1"
    local validation_level="${2:-full}"
    # 参数: package_file - 模板包路径, validation_level - 验证级别
    # 返回: 0=验证通过, 1=验证失败
    # 描述: 验证模板包的各个方面
}

# 性能测试
performance_test() {
    local package_file="$1"
    # 参数: package_file - 模板包路径
    # 返回: JSON 格式的性能数据
    # 描述: 执行模板性能基准测试
}

# 生成验证报告
generate_validation_report() {
    local results="$1"
    local output_file="$2"
    # 参数: results - 验证结果, output_file - 报告文件
    # 返回: 0=成功, 1=失败
    # 描述: 生成详细的验证报告
}
```

## 工具脚本 API

### logging.sh

日志管理工具脚本。

#### 函数 API

```bash
# 日志函数
log_info() {
    local message="$1"
    # 参数: message - 日志消息
    # 描述: 输出信息级别日志
}

log_warn() {
    local message="$1"
    # 参数: message - 警告消息
    # 描述: 输出警告级别日志
}

log_error() {
    local message="$1"
    # 参数: message - 错误消息
    # 描述: 输出错误级别日志
}

log_debug() {
    local message="$1"
    # 参数: message - 调试消息
    # 描述: 输出调试级别日志（仅在调试模式下）
}

# 日志配置
setup_logging() {
    local log_file="${1:-logs/build.log}"
    local log_level="${2:-INFO}"
    # 参数: log_file - 日志文件路径, log_level - 日志级别
    # 描述: 配置日志输出
}
```

### system-diagnostics.sh

系统诊断脚本。

#### 命令行接口

```bash
./scripts/system-diagnostics.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `check` | 系统检查（默认） | 无 |
| `report` | 生成诊断报告 | 无 |
| `fix` | 自动修复问题 | 无 |

#### 函数 API

```bash
# 系统健康检查
system_health_check() {
    # 参数: 无
    # 返回: 0=健康, 1=发现问题
    # 描述: 检查系统健康状态
}

# 生成诊断报告
generate_diagnostic_report() {
    local output_file="${1:-diagnostic-report.txt}"
    # 参数: output_file - 报告文件路径
    # 返回: 0=成功, 1=失败
    # 描述: 生成详细的系统诊断报告
}
```

### monitoring.sh

监控脚本。

#### 命令行接口

```bash
./scripts/monitoring.sh [OPTIONS] COMMAND
```

#### 命令

| 命令 | 描述 | 参数 |
|------|------|------|
| `status` | 显示状态（默认） | 无 |
| `enable` | 启用监控 | 无 |
| `disable` | 禁用监控 | 无 |
| `metrics` | 显示指标 | 无 |

#### 函数 API

```bash
# 获取系统指标
get_system_metrics() {
    # 参数: 无
    # 返回: JSON 格式的系统指标
    # 描述: 收集系统性能指标
}

# 监控 K3s 状态
monitor_k3s_status() {
    # 参数: 无
    # 返回: 0=正常, 1=异常
    # 描述: 监控 K3s 集群状态
}
```

## 配置文件 API

### template.yaml

主配置文件结构和字段说明。

#### 配置结构

```yaml
# 模板基本信息
template:
  name: string              # 模板名称
  version: string           # 版本号（语义化版本）
  description: string       # 模板描述
  author: string           # 作者信息
  base_image: string       # 基础镜像
  architecture: string     # 目标架构

# K3s 配置
k3s:
  version: string          # K3s 版本
  cluster_init: boolean    # 是否初始化集群
  install_options: array   # 安装选项
  server_options: array    # 服务器选项
  agent_options: array     # 代理选项

# 系统配置
system:
  timezone: string         # 时区
  locale: string          # 语言环境
  packages: array         # 要安装的包
  remove_packages: array  # 要移除的包
  services:
    enable: array         # 启用的服务
    disable: array        # 禁用的服务

# 安全配置
security:
  disable_root_login: boolean    # 禁用 root 登录
  create_k3s_user: boolean      # 创建 K3s 用户
  k3s_user: string              # K3s 用户名
  firewall_rules: array         # 防火墙规则

# 网络配置
network:
  dns_servers: array       # DNS 服务器
  search_domains: array    # 搜索域
  cluster_cidr: string     # Pod 网络 CIDR
  service_cidr: string     # 服务网络 CIDR

# 构建配置
build:
  cleanup_after_install: boolean  # 安装后清理
  optimize_size: boolean          # 优化大小
  parallel_jobs: integer          # 并行任务数
```

#### 配置验证

配置文件使用 JSON Schema 进行验证，Schema 文件位于 `config/template-schema.json`。

## 错误处理和调试

### 错误处理模式

所有脚本都遵循统一的错误处理模式：

```bash
# 错误处理函数
handle_error() {
    local exit_code="$1"
    local error_message="$2"
    local context="${3:-}"
    
    log_error "$error_message"
    if [[ -n "$context" ]]; then
        log_error "Context: $context"
    fi
    
    cleanup_on_error
    exit "$exit_code"
}

# 在脚本中使用
some_command || handle_error 1 "Command failed" "additional context"
```

### 调试支持

#### 调试模式

```bash
# 启用调试模式
export DEBUG=1
./scripts/script-name.sh

# 或使用命令行选项
./scripts/script-name.sh --debug
```

#### 详细输出

```bash
# 启用详细输出
./scripts/script-name.sh --verbose

# 或设置环境变量
export VERBOSE=1
```

#### 日志级别

支持的日志级别：
- `DEBUG`: 调试信息
- `INFO`: 一般信息
- `WARN`: 警告信息
- `ERROR`: 错误信息

```bash
# 设置日志级别
export LOG_LEVEL=DEBUG
```

## 扩展 API

### 添加新脚本

创建新脚本时，请遵循以下模板：

```bash
#!/bin/bash
# 脚本描述
# 
# 用法: script-name.sh [OPTIONS] COMMAND [ARGS...]
#
# 命令:
#   command1    命令1描述
#   command2    命令2描述
#
# 选项:
#   --option1   选项1描述
#   --option2   选项2描述

set -euo pipefail

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCRIPT_NAME="$(basename "$0")"

# 导入公共函数
source "$SCRIPT_DIR/logging.sh"

# 默认配置
DEFAULT_CONFIG="$PROJECT_ROOT/config/template.yaml"
DEBUG=${DEBUG:-0}
VERBOSE=${VERBOSE:-0}

# 显示帮助信息
show_help() {
    cat << EOF
用法: $SCRIPT_NAME [OPTIONS] COMMAND [ARGS...]

命令:
  command1    命令1描述
  command2    命令2描述

选项:
  --config FILE    配置文件路径 (默认: $DEFAULT_CONFIG)
  --debug          启用调试模式
  --verbose        详细输出
  --help           显示此帮助信息
  --version        显示版本信息

示例:
  $SCRIPT_NAME command1
  $SCRIPT_NAME --debug command2
EOF
}

# 显示版本信息
show_version() {
    echo "$SCRIPT_NAME version 1.0.0"
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                exit 2
                ;;
            *)
                break
                ;;
        esac
    done
    
    COMMAND="${1:-default}"
    shift || true
    ARGS=("$@")
}

# 命令实现函数
command1_function() {
    log_info "执行命令1"
    # 实现逻辑
}

command2_function() {
    log_info "执行命令2"
    # 实现逻辑
}

# 主函数
main() {
    parse_args "$@"
    
    # 设置日志
    setup_logging
    
    case "$COMMAND" in
        "command1")
            command1_function "${ARGS[@]}"
            ;;
        "command2")
            command2_function "${ARGS[@]}"
            ;;
        "default")
            command1_function "${ARGS[@]}"
            ;;
        *)
            log_error "未知命令: $COMMAND"
            show_help
            exit 2
            ;;
    esac
}

# 如果直接执行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### 添加新配置选项

1. 更新 `config/template.yaml`
2. 更新 `config/template-schema.json`
3. 在 `config-loader.sh` 中添加解析逻辑
4. 更新相关文档

### 添加新测试

使用 BATS 框架编写测试：

```bash
#!/usr/bin/env bats

# 测试文件: tests/test-new-feature.bats

load test_helper

@test "新功能应该正常工作" {
    run scripts/new-feature.sh command
    [ "$status" -eq 0 ]
    [[ "$output" =~ "预期输出" ]]
}

@test "新功能应该处理错误输入" {
    run scripts/new-feature.sh invalid-command
    [ "$status" -eq 2 ]
    [[ "$output" =~ "错误" ]]
}
```

## 性能考虑

### 脚本性能优化

1. **避免不必要的子进程**
   ```bash
   # 好的做法
   [[ "$var" =~ pattern ]]
   
   # 避免的做法
   echo "$var" | grep pattern
   ```

2. **使用内置命令**
   ```bash
   # 好的做法
   [[ -f "$file" ]]
   
   # 避免的做法
   test -f "$file"
   ```

3. **批量操作**
   ```bash
   # 好的做法
   find . -name "*.tmp" -delete
   
   # 避免的做法
   for file in *.tmp; do rm "$file"; done
   ```

### 内存使用优化

1. **使用局部变量**
   ```bash
   function_name() {
       local var="value"  # 而不是全局变量
   }
   ```

2. **及时清理临时文件**
   ```bash
   cleanup() {
       rm -rf "$TEMP_DIR"
   }
   trap cleanup EXIT
   ```

## 总结

本 API 文档提供了 PVE LXC K3s 模板生成器所有脚本和函数的详细接口说明。通过遵循这些 API 规范，您可以：

1. 正确使用现有脚本
2. 开发新的扩展功能
3. 集成到自动化流程中
4. 进行有效的调试和故障排查

如果您需要更多信息或有任何问题，请参考其他文档或通过 GitHub Issues 联系我们。