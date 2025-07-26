#!/bin/bash
# Configuration validation and parsing script for PVE LXC K3s template
# This script validates the template.yaml configuration file against the JSON schema

set -euo pipefail

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config/template.yaml"
SCHEMA_FILE="${PROJECT_ROOT}/config/template-schema.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if required tools are installed
check_dependencies() {
    local missing_deps=()
    
    if ! command -v yq >/dev/null 2>&1; then
        missing_deps+=("yq")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                yq)
                    log_error "  - yq: https://github.com/mikefarah/yq#install"
                    ;;
                jq)
                    log_error "  - jq: https://stedolan.github.io/jq/download/"
                    ;;
            esac
        done
        return 1
    fi
}

# Validate YAML syntax
validate_yaml_syntax() {
    local config_file="$1"
    
    log_info "Validating YAML syntax..."
    
    if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
        log_error "Invalid YAML syntax in $config_file"
        return 1
    fi
    
    log_info "YAML syntax is valid"
    return 0
}

# Convert YAML to JSON for schema validation
yaml_to_json() {
    local config_file="$1"
    yq eval -o=json "$config_file"
}

# Validate configuration against JSON schema
validate_schema() {
    local config_file="$1"
    local schema_file="$2"
    
    log_info "Validating configuration against schema..."
    
    # Convert YAML to JSON
    local config_json
    if ! config_json=$(yaml_to_json "$config_file"); then
        log_error "Failed to convert YAML to JSON"
        return 1
    fi
    
    # Validate against schema using a simple validation approach
    # Note: This is a basic validation. For production, consider using ajv-cli or similar
    local validation_errors=()
    
    # Check required fields
    if ! echo "$config_json" | jq -e '.template.name' >/dev/null 2>&1; then
        validation_errors+=("Missing required field: template.name")
    fi
    
    if ! echo "$config_json" | jq -e '.template.version' >/dev/null 2>&1; then
        validation_errors+=("Missing required field: template.version")
    fi
    
    if ! echo "$config_json" | jq -e '.template.base_image' >/dev/null 2>&1; then
        validation_errors+=("Missing required field: template.base_image")
    fi
    
    if ! echo "$config_json" | jq -e '.k3s.version' >/dev/null 2>&1; then
        validation_errors+=("Missing required field: k3s.version")
    fi
    
    # Validate version format
    local template_version
    template_version=$(echo "$config_json" | jq -r '.template.version // ""')
    if [[ -n "$template_version" && ! "$template_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        validation_errors+=("Invalid template.version format: $template_version (expected: x.y.z)")
    fi
    
    # Validate K3s version format
    local k3s_version
    k3s_version=$(echo "$config_json" | jq -r '.k3s.version // ""')
    if [[ -n "$k3s_version" && ! "$k3s_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]]; then
        validation_errors+=("Invalid k3s.version format: $k3s_version (expected: vx.y.z+k3sN)")
    fi
    
    # Validate base image format
    local base_image
    base_image=$(echo "$config_json" | jq -r '.template.base_image // ""')
    if [[ -n "$base_image" && ! "$base_image" =~ ^alpine:[0-9]+\.[0-9]+$ ]]; then
        validation_errors+=("Invalid template.base_image format: $base_image (expected: alpine:x.y)")
    fi
    
    # Validate architecture
    local architecture
    architecture=$(echo "$config_json" | jq -r '.template.architecture // "amd64"')
    if [[ ! "$architecture" =~ ^(amd64|arm64|armv7)$ ]]; then
        validation_errors+=("Invalid template.architecture: $architecture (allowed: amd64, arm64, armv7)")
    fi
    
    # Report validation errors
    if [ ${#validation_errors[@]} -gt 0 ]; then
        log_error "Configuration validation failed:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_info "Configuration validation passed"
    return 0
}

# Extract configuration value
get_config_value() {
    local config_file="$1"
    local path="$2"
    local default_value="${3:-}"
    
    local value
    value=$(yq eval "$path" "$config_file" 2>/dev/null || echo "null")
    
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Print configuration summary
print_config_summary() {
    local config_file="$1"
    
    log_info "Configuration Summary:"
    echo "  Template Name: $(get_config_value "$config_file" '.template.name')"
    echo "  Template Version: $(get_config_value "$config_file" '.template.version')"
    echo "  Base Image: $(get_config_value "$config_file" '.template.base_image')"
    echo "  Architecture: $(get_config_value "$config_file" '.template.architecture' 'amd64')"
    echo "  K3s Version: $(get_config_value "$config_file" '.k3s.version')"
    echo "  Cluster Init: $(get_config_value "$config_file" '.k3s.cluster_init' 'true')"
    echo "  Timezone: $(get_config_value "$config_file" '.system.timezone' 'UTC')"
    echo "  Create K3s User: $(get_config_value "$config_file" '.security.create_k3s_user' 'true')"
}

# Main validation function
validate_config() {
    local config_file="${1:-$CONFIG_FILE}"
    
    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if schema file exists
    if [ ! -f "$SCHEMA_FILE" ]; then
        log_error "Schema file not found: $SCHEMA_FILE"
        return 1
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        return 1
    fi
    
    # Validate YAML syntax
    if ! validate_yaml_syntax "$config_file"; then
        return 1
    fi
    
    # Validate against schema
    if ! validate_schema "$config_file" "$SCHEMA_FILE"; then
        return 1
    fi
    
    # Print summary
    print_config_summary "$config_file"
    
    log_info "Configuration validation completed successfully"
    return 0
}

# Export configuration as environment variables
export_config_env() {
    local config_file="${1:-$CONFIG_FILE}"
    local prefix="${2:-TEMPLATE_}"
    
    # Template configuration
    export "${prefix}NAME"=$(get_config_value "$config_file" '.template.name')
    export "${prefix}VERSION"=$(get_config_value "$config_file" '.template.version')
    export "${prefix}BASE_IMAGE"=$(get_config_value "$config_file" '.template.base_image')
    export "${prefix}ARCHITECTURE"=$(get_config_value "$config_file" '.template.architecture' 'amd64')
    
    # K3s configuration
    export "${prefix}K3S_VERSION"=$(get_config_value "$config_file" '.k3s.version')
    export "${prefix}K3S_CLUSTER_INIT"=$(get_config_value "$config_file" '.k3s.cluster_init' 'true')
    
    # System configuration
    export "${prefix}TIMEZONE"=$(get_config_value "$config_file" '.system.timezone' 'UTC')
    export "${prefix}LOCALE"=$(get_config_value "$config_file" '.system.locale' 'en_US.UTF-8')
    
    # Security configuration
    export "${prefix}CREATE_K3S_USER"=$(get_config_value "$config_file" '.security.create_k3s_user' 'true')
    export "${prefix}K3S_USER"=$(get_config_value "$config_file" '.security.k3s_user' 'k3s')
    export "${prefix}K3S_UID"=$(get_config_value "$config_file" '.security.k3s_uid' '1000')
    export "${prefix}K3S_GID"=$(get_config_value "$config_file" '.security.k3s_gid' '1000')
    
    log_info "Configuration exported as environment variables with prefix: $prefix"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    validate [CONFIG_FILE]    Validate configuration file (default: config/template.yaml)
    export [CONFIG_FILE]      Export configuration as environment variables
    summary [CONFIG_FILE]     Show configuration summary
    help                      Show this help message

Examples:
    $0 validate
    $0 validate /path/to/custom-config.yaml
    $0 export
    $0 summary

EOF
}

# Main script logic
main() {
    local command="${1:-validate}"
    
    case "$command" in
        validate)
            validate_config "${2:-}"
            ;;
        export)
            export_config_env "${2:-}"
            ;;
        summary)
            print_config_summary "${2:-$CONFIG_FILE}"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi