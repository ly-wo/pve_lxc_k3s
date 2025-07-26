#!/bin/bash
# Basic functionality test for configuration management system
# This script tests core functionality without requiring bats

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create temporary test directory
TEST_DIR="$(mktemp -d)"
echo "Using test directory: $TEST_DIR"

# Create test configuration file
TEST_CONFIG="$TEST_DIR/test-template.yaml"
cat > "$TEST_CONFIG" << 'EOF'
template:
  name: "test-alpine-k3s"
  version: "1.0.0"
  description: "Test template"
  author: "Test Author"
  base_image: "alpine:3.18"
  architecture: "amd64"

k3s:
  version: "v1.28.4+k3s1"
  install_options:
    - "--disable=traefik"
    - "--disable=servicelb"
  cluster_init: true

system:
  timezone: "UTC"
  locale: "en_US.UTF-8"
  packages:
    - curl
    - wget
  remove_packages:
    - docs

security:
  disable_root_login: true
  create_k3s_user: true
  k3s_user: "k3s"
  k3s_uid: 1000
  k3s_gid: 1000

build:
  cleanup_after_install: true
  optimize_size: true
  parallel_jobs: 2
EOF

echo "Created test configuration file"

# Test 1: Check if scripts exist and are executable
echo -e "\n${YELLOW}Testing script existence and permissions...${NC}"

test_result "config-validator.sh exists and is executable" \
    $([ -x "$PROJECT_ROOT/scripts/config-validator.sh" ] && echo 0 || echo 1)

test_result "config-loader.sh exists and is executable" \
    $([ -x "$PROJECT_ROOT/scripts/config-loader.sh" ] && echo 0 || echo 1)

test_result "template-schema.json exists" \
    $([ -f "$PROJECT_ROOT/config/template-schema.json" ] && echo 0 || echo 1)

# Test 2: Basic YAML validation (if yq is available)
echo -e "\n${YELLOW}Testing YAML validation...${NC}"

if command -v yq >/dev/null 2>&1; then
    # Test valid YAML
    if yq eval '.' "$TEST_CONFIG" >/dev/null 2>&1; then
        test_result "Valid YAML syntax validation" 0
    else
        test_result "Valid YAML syntax validation" 1
    fi
    
    # Test invalid YAML
    INVALID_YAML="$TEST_DIR/invalid.yaml"
    echo "invalid: [unclosed" > "$INVALID_YAML"
    
    if ! yq eval '.' "$INVALID_YAML" >/dev/null 2>&1; then
        test_result "Invalid YAML syntax detection" 0
    else
        test_result "Invalid YAML syntax detection" 1
    fi
else
    echo -e "${YELLOW}⚠${NC} yq not available, skipping YAML validation tests"
fi

# Test 3: JSON Schema validation (basic structure check)
echo -e "\n${YELLOW}Testing JSON Schema structure...${NC}"

SCHEMA_FILE="$PROJECT_ROOT/config/template-schema.json"
if jq empty "$SCHEMA_FILE" >/dev/null 2>&1; then
    test_result "JSON Schema is valid JSON" 0
else
    test_result "JSON Schema is valid JSON" 1
fi

# Check if schema has required properties
if jq -e '.properties.template' "$SCHEMA_FILE" >/dev/null 2>&1; then
    test_result "Schema has template properties" 0
else
    test_result "Schema has template properties" 1
fi

if jq -e '.properties.k3s' "$SCHEMA_FILE" >/dev/null 2>&1; then
    test_result "Schema has k3s properties" 0
else
    test_result "Schema has k3s properties" 1
fi

# Test 4: Configuration file structure
echo -e "\n${YELLOW}Testing configuration file structure...${NC}"

MAIN_CONFIG="$PROJECT_ROOT/config/template.yaml"
if [ -f "$MAIN_CONFIG" ]; then
    test_result "Main configuration file exists" 0
    
    if command -v yq >/dev/null 2>&1; then
        # Test required fields
        if yq eval '.template.name' "$MAIN_CONFIG" >/dev/null 2>&1; then
            test_result "Configuration has template.name" 0
        else
            test_result "Configuration has template.name" 1
        fi
        
        if yq eval '.k3s.version' "$MAIN_CONFIG" >/dev/null 2>&1; then
            test_result "Configuration has k3s.version" 0
        else
            test_result "Configuration has k3s.version" 1
        fi
    fi
else
    test_result "Main configuration file exists" 1
fi

# Test 5: Script help functionality
echo -e "\n${YELLOW}Testing script help functionality...${NC}"

if "$PROJECT_ROOT/scripts/config-validator.sh" help >/dev/null 2>&1; then
    test_result "config-validator.sh help works" 0
else
    test_result "config-validator.sh help works" 1
fi

if "$PROJECT_ROOT/scripts/config-loader.sh" help >/dev/null 2>&1; then
    test_result "config-loader.sh help works" 0
else
    test_result "config-loader.sh help works" 1
fi

# Test 6: Basic script functionality (if dependencies available)
echo -e "\n${YELLOW}Testing basic script functionality...${NC}"

if command -v yq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # Test config validation
    if "$PROJECT_ROOT/scripts/config-validator.sh" validate "$TEST_CONFIG" >/dev/null 2>&1; then
        test_result "Configuration validation passes" 0
    else
        test_result "Configuration validation passes" 1
    fi
    
    # Test config summary
    if "$PROJECT_ROOT/scripts/config-validator.sh" summary "$TEST_CONFIG" >/dev/null 2>&1; then
        test_result "Configuration summary generation" 0
    else
        test_result "Configuration summary generation" 1
    fi
else
    echo -e "${YELLOW}⚠${NC} yq or jq not available, skipping script functionality tests"
fi

# Cleanup
rm -rf "$TEST_DIR"

# Print summary
echo -e "\n${YELLOW}Test Summary:${NC}"
echo "Tests run: $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed.${NC}"
    exit 1
fi