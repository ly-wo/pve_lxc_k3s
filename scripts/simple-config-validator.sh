#!/bin/bash
# Simple Configuration Validator for GitHub Actions
# 简化的配置验证器，用于 GitHub Actions 环境

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 默认配置文件
DEFAULT_CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"

# 简单的日志函数
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

# 检查 YAML 语法（使用 Python 作为后备）
validate_yaml_syntax() {
    local config_file="$1"
    
    log_info "Validating YAML syntax..."
    
    # 尝试使用 yq
    if command -v yq >/dev/null 2>&1; then
        if yq eval '.' "$config_file" >/dev/null 2>&1; then
            log_info "YAML syntax is valid (verified with yq)"
            return 0
        else
            log_error "Invalid YAML syntax in $config_file"
            return 1
        fi
    fi
    
    # 尝试使用 Python
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
            log_info "YAML syntax is valid (verified with Python)"
            return 0
        else
            log_error "Invalid YAML syntax in $config_file"
            return 1
        fi
    fi
    
    # 如果都不可用，进行基本检查
    log_info "Performing basic YAML syntax check..."
    
    # 检查基本的 YAML 结构
    if grep -q "^[[:space:]]*[^#].*:" "$config_file"; then
        log_info "Basic YAML structure appears valid"
        return 0
    else
        log_error "File does not appear to be valid YAML"
        return 1
    fi
}

# 基本配置验证
validate_basic_config() {
    local config_file="$1"
    
    log_info "Performing basic configuration validation..."
    
    # 检查必需的字段
    local required_sections=(
        "template:"
        "k3s:"
        "system:"
        "security:"
    )
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "^$section" "$config_file"; then
            log_error "Required section missing: $section"
            return 1
        fi
    done
    
    # 检查必需的字段
    if ! grep -q "name:" "$config_file"; then
        log_error "Required field missing: name"
        return 1
    fi
    
    if ! grep -q "version:" "$config_file"; then
        log_error "Required field missing: version"
        return 1
    fi
    
    log_info "Basic configuration validation passed"
    return 0
}

# 提取配置值（简化版本）
extract_config_values() {
    local config_file="$1"
    
    log_info "Extracting configuration values..."
    
    # 使用简单的 grep 和 sed 提取值
    local template_name
    template_name=$(grep "name:" "$config_file" | head -n1 | sed 's/.*name:[[:space:]]*["'\'']*\([^"'\'']*\)["'\'']*$/\1/')
    
    local template_version
    template_version=$(grep "version:" "$config_file" | head -n1 | sed 's/.*version:[[:space:]]*["'\'']*\([^"'\'']*\)["'\'']*$/\1/')
    
    local base_image
    base_image=$(grep "base_image:" "$config_file" | head -n1 | sed 's/.*base_image:[[:space:]]*["'\'']*\([^"'\'']*\)["'\'']*$/\1/')
    
    local k3s_version
    k3s_version=$(grep -A5 "^k3s:" "$config_file" | grep "version:" | head -n1 | sed 's/.*version:[[:space:]]*["'\'']*\([^"'\'']*\)["'\'']*$/\1/')
    
    log_info "Configuration Summary:"
    log_info "  Template Name: ${template_name:-unknown}"
    log_info "  Template Version: ${template_version:-unknown}"
    log_info "  Base Image: ${base_image:-unknown}"
    log_info "  K3s Version: ${k3s_version:-unknown}"
    
    return 0
}

# 主验证函数
validate_config() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    log_info "Starting simple configuration validation..."
    log_info "Config file: $config_file"
    
    # 检查文件是否存在
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # 验证 YAML 语法
    if ! validate_yaml_syntax "$config_file"; then
        return 1
    fi
    
    # 基本配置验证
    if ! validate_basic_config "$config_file"; then
        return 1
    fi
    
    # 提取配置值
    if ! extract_config_values "$config_file"; then
        return 1
    fi
    
    log_info "Simple configuration validation completed successfully"
    return 0
}

# 显示帮助信息
show_help() {
    cat << EOF
Simple Configuration Validator

Usage: $0 [CONFIG_FILE]

Arguments:
    CONFIG_FILE    Path to configuration file (default: config/template.yaml)

Examples:
    $0
    $0 config/template.yaml
    $0 /path/to/custom-config.yaml

EOF
}

# 主函数
main() {
    local config_file="${1:-}"
    
    # 处理帮助选项
    case "${config_file:-}" in
        help|--help|-h)
            show_help
            exit 0
            ;;
    esac
    
    # 如果没有提供配置文件，使用默认值
    if [[ -z "$config_file" ]]; then
        config_file="$DEFAULT_CONFIG_FILE"
    fi
    
    # 执行验证
    validate_config "$config_file"
}

# 脚本入口点
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi