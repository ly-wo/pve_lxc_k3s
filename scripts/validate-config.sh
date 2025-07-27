#!/bin/bash
# Configuration validation script
# This script validates that configuration loading works correctly

set -euo pipefail

# Source the config loader
source "$(dirname "$0")/config-loader.sh"

# Test configuration loading
echo "Validate Configuration"

# Test basic configuration values
K3S_VERSION=$(get_config "k3s.version")
TEMPLATE_NAME=$(get_config "template.name")
TEMPLATE_VERSION=$(get_config "template.version")

# Output results (clean, no log messages)
echo "$K3S_VERSION"

# Validate that we got expected values
if [[ -z "$K3S_VERSION" ]]; then
    echo "Error: Failed to load K3s version" >&2
    exit 1
fi

if [[ -z "$TEMPLATE_NAME" ]]; then
    echo "Error: Failed to load template name" >&2
    exit 1
fi

if [[ -z "$TEMPLATE_VERSION" ]]; then
    echo "Error: Failed to load template version" >&2
    exit 1
fi

# Success - configuration loaded correctly
exit 0