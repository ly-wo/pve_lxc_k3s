#!/bin/bash
# Configuration loader script for PVE LXC K3s template
# This script loads and processes configuration with default values

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"

# Source the validator script for utility functions
# shellcheck source=scripts/config-validator.sh
if [ -f "${SCRIPT_DIR}/config-validator.sh" ]; then
    source "${SCRIPT_DIR}/config-validator.sh"
else
    # Fallback logging functions if validator script is not available
    log_info() { echo -e "\033[0;32m[INFO]\033[0m $1" >&2; }
    log_warn() { echo -e "\033[1;33m[WARN]\033[0m $1" >&2; }
    log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1" >&2; }
    yaml_to_json() { echo "{}"; }
fi

# Default configuration values function
get_default_config() {
    local key="$1"
    
    case "$key" in
        # Template defaults
        "template.architecture") echo "amd64" ;;
        "template.description") echo "Alpine Linux LXC template with pre-installed K3s" ;;
        "template.author") echo "PVE LXC K3s Template Generator" ;;
        
        # K3s defaults
        "k3s.cluster_init") echo "true" ;;
        "k3s.install_options") echo '["--disable=traefik", "--disable=servicelb", "--write-kubeconfig-mode=644"]' ;;
        "k3s.server_options") echo "[]" ;;
        "k3s.agent_options") echo "[]" ;;
        
        # System defaults
        "system.timezone") echo "UTC" ;;
        "system.locale") echo "en_US.UTF-8" ;;
        "system.packages") echo '["curl", "wget", "ca-certificates", "openssl", "bash", "coreutils"]' ;;
        "system.remove_packages") echo '["apk-tools-doc", "man-pages", "docs"]' ;;
        "system.services.enable") echo '["k3s"]' ;;
        "system.services.disable") echo '["chronyd"]' ;;
        
        # Security defaults
        "security.disable_root_login") echo "true" ;;
        "security.create_k3s_user") echo "true" ;;
        "security.k3s_user") echo "k3s" ;;
        "security.k3s_uid") echo "1000" ;;
        "security.k3s_gid") echo "1000" ;;
        "security.firewall_rules") echo '[{"port": "6443", "protocol": "tcp", "description": "K3s API Server"}, {"port": "10250", "protocol": "tcp", "description": "Kubelet API"}, {"port": "8472", "protocol": "udp", "description": "Flannel VXLAN"}]' ;;
        "security.remove_packages") echo '["apk-tools", "alpine-keys"]' ;;
        
        # Network defaults
        "network.interfaces") echo "[]" ;;
        "network.dns_servers") echo '["8.8.8.8", "8.8.4.4"]' ;;
        "network.search_domains") echo "[]" ;;
        
        # Storage defaults
        "storage.volumes") echo "[]" ;;
        "storage.mounts") echo "[]" ;;
        "storage.cleanup_paths") echo '["/tmp/*", "/var/cache/apk/*", "/var/log/*"]' ;;
        
        # Build defaults
        "build.cleanup_after_install") echo "true" ;;
        "build.optimize_size") echo "true" ;;
        "build.include_docs") echo "false" ;;
        "build.parallel_jobs") echo "2" ;;
        
        *) echo "" ;;
    esac
}

# Global configuration cache (using simple variables instead of associative arrays)
CONFIG_LOADED=false
CONFIG_CACHE_FILE=""

# Load configuration with defaults
load_config() {
    local config_file="${1:-$CONFIG_FILE}"
    
    if [ "$CONFIG_LOADED" = true ]; then
        log_info "Configuration already loaded from cache" >&2
        return 0
    fi
    
    log_info "Loading configuration from: $config_file" >&2
    
    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Store config file path for later use
    CONFIG_CACHE_FILE="$config_file"
    CONFIG_LOADED=true
    
    log_info "Configuration loaded successfully" >&2
}

# Get configuration value with default fallback
get_config() {
    local key="$1"
    local default_value="${2:-}"
    
    # Load config if not already loaded (suppress all output)
    if [ "$CONFIG_LOADED" = false ]; then
        load_config >/dev/null 2>&1
    fi
    
    # Try to get from loaded config using yq if available
    if [ -n "$CONFIG_CACHE_FILE" ] && command -v yq >/dev/null 2>&1; then
        local value
        value=$(yq eval ".$key" "$CONFIG_CACHE_FILE" 2>/dev/null || echo "null")
        if [ "$value" != "null" ] && [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
    fi
    
    # Check defaults
    local default_config_value
    default_config_value=$(get_default_config "$key")
    if [ -n "$default_config_value" ]; then
        echo "$default_config_value"
        return 0
    fi
    
    # Return provided default or empty
    echo "$default_value"
}

# Get configuration array
get_config_array() {
    local key="$1"
    local value
    value=$(get_config "$key" "[]")
    
    # Parse JSON array and return as bash array elements
    echo "$value" | jq -r '.[]' 2>/dev/null || true
}

# Get configuration object keys
get_config_keys() {
    local key="$1"
    local value
    value=$(get_config "$key" "{}")
    
    # Parse JSON object and return keys
    echo "$value" | jq -r 'keys[]' 2>/dev/null || true
}

# Check if configuration key exists
config_exists() {
    local key="$1"
    local value
    value=$(get_config "$key")
    [ -n "$value" ] && [ "$value" != "null" ]
}

# Validate required configuration
validate_required_config() {
    local required_keys=(
        "template.name"
        "template.version"
        "template.base_image"
        "k3s.version"
    )
    
    local missing_keys=()
    
    for key in "${required_keys[@]}"; do
        if ! config_exists "$key"; then
            missing_keys+=("$key")
        fi
    done
    
    if [ ${#missing_keys[@]} -gt 0 ]; then
        log_error "Missing required configuration keys:"
        for key in "${missing_keys[@]}"; do
            log_error "  - $key"
        done
        return 1
    fi
    
    return 0
}

# Export configuration as environment variables
export_config() {
    local prefix="${1:-TEMPLATE_}"
    
    # Load config if not already loaded
    if [ "$CONFIG_LOADED" = false ]; then
        load_config
    fi
    
    # Export template configuration
    export "${prefix}NAME"=$(get_config "template.name")
    export "${prefix}VERSION"=$(get_config "template.version")
    export "${prefix}DESCRIPTION"=$(get_config "template.description")
    export "${prefix}AUTHOR"=$(get_config "template.author")
    export "${prefix}BASE_IMAGE"=$(get_config "template.base_image")
    export "${prefix}ARCHITECTURE"=$(get_config "template.architecture")
    
    # Export K3s configuration
    export "${prefix}K3S_VERSION"=$(get_config "k3s.version")
    export "${prefix}K3S_CLUSTER_INIT"=$(get_config "k3s.cluster_init")
    
    # Export system configuration
    export "${prefix}TIMEZONE"=$(get_config "system.timezone")
    export "${prefix}LOCALE"=$(get_config "system.locale")
    
    # Export security configuration
    export "${prefix}CREATE_K3S_USER"=$(get_config "security.create_k3s_user")
    export "${prefix}K3S_USER"=$(get_config "security.k3s_user")
    export "${prefix}K3S_UID"=$(get_config "security.k3s_uid")
    export "${prefix}K3S_GID"=$(get_config "security.k3s_gid")
    export "${prefix}DISABLE_ROOT_LOGIN"=$(get_config "security.disable_root_login")
    
    # Export build configuration
    export "${prefix}CLEANUP_AFTER_INSTALL"=$(get_config "build.cleanup_after_install")
    export "${prefix}OPTIMIZE_SIZE"=$(get_config "build.optimize_size")
    export "${prefix}INCLUDE_DOCS"=$(get_config "build.include_docs")
    export "${prefix}PARALLEL_JOBS"=$(get_config "build.parallel_jobs")
    
    log_info "Configuration exported with prefix: $prefix" >&2
}

# Generate configuration report
generate_config_report() {
    local output_file="${1:-}"
    
    # Load config if not already loaded
    if [ "$CONFIG_LOADED" = false ]; then
        load_config
    fi
    
    local report
    report=$(cat << EOF
# Configuration Report
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Template Information
- Name: $(get_config "template.name")
- Version: $(get_config "template.version")
- Description: $(get_config "template.description")
- Author: $(get_config "template.author")
- Base Image: $(get_config "template.base_image")
- Architecture: $(get_config "template.architecture")

## K3s Configuration
- Version: $(get_config "k3s.version")
- Cluster Init: $(get_config "k3s.cluster_init")
- Install Options: $(get_config "k3s.install_options" | jq -r 'join(", ")')

## System Configuration
- Timezone: $(get_config "system.timezone")
- Locale: $(get_config "system.locale")
- Packages to Install: $(get_config "system.packages" | jq -r 'join(", ")')
- Packages to Remove: $(get_config "system.remove_packages" | jq -r 'join(", ")')

## Security Configuration
- Disable Root Login: $(get_config "security.disable_root_login")
- Create K3s User: $(get_config "security.create_k3s_user")
- K3s User: $(get_config "security.k3s_user")
- K3s UID: $(get_config "security.k3s_uid")
- K3s GID: $(get_config "security.k3s_gid")

## Build Configuration
- Cleanup After Install: $(get_config "build.cleanup_after_install")
- Optimize Size: $(get_config "build.optimize_size")
- Include Docs: $(get_config "build.include_docs")
- Parallel Jobs: $(get_config "build.parallel_jobs")
EOF
)
    
    if [ -n "$output_file" ]; then
        echo "$report" > "$output_file"
        log_info "Configuration report saved to: $output_file" >&2
    else
        echo "$report"
    fi
}

# Reset configuration cache
reset_config() {
    CONFIG_CACHE_FILE=""
    CONFIG_LOADED=false
    log_info "Configuration cache reset" >&2
}

# Show configuration help
show_config_help() {
    cat << EOF
Configuration Loader Usage:

Functions:
    load_config [CONFIG_FILE]           Load configuration from file
    get_config KEY [DEFAULT]            Get configuration value
    get_config_array KEY                Get configuration array values
    get_config_keys KEY                 Get configuration object keys
    config_exists KEY                   Check if configuration key exists
    validate_required_config            Validate required configuration
    export_config [PREFIX]              Export as environment variables
    generate_config_report [FILE]       Generate configuration report
    reset_config                        Reset configuration cache

Examples:
    # Load and get values
    load_config
    get_config "template.name"
    get_config "template.description" "Default description"
    
    # Work with arrays
    get_config_array "system.packages"
    
    # Export to environment
    export_config "MY_"
    
    # Generate report
    generate_config_report config-report.md

EOF
}

# Main function for direct script execution
main() {
    local command="${1:-help}"
    
    case "$command" in
        load)
            load_config "${2:-}"
            ;;
        get)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 get KEY [DEFAULT]"
                exit 1
            fi
            get_config "$2" "${3:-}"
            ;;
        array)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 array KEY"
                exit 1
            fi
            get_config_array "$2"
            ;;
        keys)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 keys KEY"
                exit 1
            fi
            get_config_keys "$2"
            ;;
        exists)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 exists KEY"
                exit 1
            fi
            if config_exists "$2"; then
                echo "true"
                exit 0
            else
                echo "false"
                exit 1
            fi
            ;;
        validate)
            validate_required_config
            ;;
        export)
            export_config "${2:-}"
            ;;
        report)
            generate_config_report "${2:-}"
            ;;
        reset)
            reset_config
            ;;
        help|--help|-h)
            show_config_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_config_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi