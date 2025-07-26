#!/usr/bin/env bats
# BATS tests for template packaging functionality

# Setup and teardown
setup() {
    # Set up test environment
    export TEST_CONFIG_FILE="${BATS_TEST_DIRNAME}/../config/template.yaml"
    export TEST_OUTPUT_DIR="${BATS_TEST_DIRNAME}/../output"
    export TEST_BUILD_DIR="${BATS_TEST_DIRNAME}/../.build"
    
    # Create minimal test directories if they don't exist
    mkdir -p "$TEST_OUTPUT_DIR"
    mkdir -p "$TEST_BUILD_DIR"
}

teardown() {
    # Clean up test artifacts
    rm -rf "${BATS_TEST_DIRNAME}/../.test" || true
}

# Test packager script existence and permissions
@test "packager script exists and is executable" {
    [ -f "${BATS_TEST_DIRNAME}/../scripts/packager.sh" ]
    [ -x "${BATS_TEST_DIRNAME}/../scripts/packager.sh" ]
}

# Test validator script existence and permissions
@test "template validator script exists and is executable" {
    [ -f "${BATS_TEST_DIRNAME}/../scripts/template-validator.sh" ]
    [ -x "${BATS_TEST_DIRNAME}/../scripts/template-validator.sh" ]
}

# Test packager help output
@test "packager shows help information" {
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "PVE LXC K3s Template Packager" ]]
    [[ "$output" =~ "package" ]]
    [[ "$output" =~ "verify" ]]
}

# Test validator help output
@test "validator shows help information" {
    run "${BATS_TEST_DIRNAME}/../scripts/template-validator.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "PVE LXC K3s Template Validator" ]]
    [[ "$output" =~ "validate" ]]
    [[ "$output" =~ "quick" ]]
}

# Test packager info command
@test "packager info command works" {
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" info
    [ "$status" -eq 0 ]
    [[ "$output" =~ "模板信息" ]]
}

# Test packager clean command
@test "packager clean command works" {
    # Create some test files
    mkdir -p "$TEST_OUTPUT_DIR"
    touch "$TEST_OUTPUT_DIR/test-file.txt"
    
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" clean
    [ "$status" -eq 0 ]
    
    # Check that files were cleaned
    [ ! -f "$TEST_OUTPUT_DIR/test-file.txt" ]
}

# Test configuration loading
@test "packager loads configuration correctly" {
    if [ -f "$TEST_CONFIG_FILE" ]; then
        run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" info
        [ "$status" -eq 0 ]
        [[ "$output" =~ "alpine-k3s" ]]
    else
        skip "Configuration file not found"
    fi
}

# Test validator configuration loading
@test "validator loads configuration correctly" {
    if [ -f "$TEST_CONFIG_FILE" ]; then
        run "${BATS_TEST_DIRNAME}/../scripts/template-validator.sh" --help
        [ "$status" -eq 0 ]
    else
        skip "Configuration file not found"
    fi
}

# Test error handling for missing build directory
@test "packager handles missing build directory gracefully" {
    # Remove build directory if it exists
    rm -rf "$TEST_BUILD_DIR"
    
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" package
    [ "$status" -ne 0 ]
    [[ "$output" =~ "构建目录不存在" ]] || [[ "$output" =~ "build" ]]
}

# Test error handling for missing template package
@test "validator handles missing template package gracefully" {
    # Ensure no template package exists
    rm -f "$TEST_OUTPUT_DIR"/*.tar.gz
    
    run "${BATS_TEST_DIRNAME}/../scripts/template-validator.sh" package-only
    [ "$status" -ne 0 ]
    [[ "$output" =~ "模板包不存在" ]] || [[ "$output" =~ "not exist" ]]
}

# Test script dependencies
@test "required commands are available" {
    # Test for basic commands that scripts depend on
    command -v tar
    command -v gzip
    command -v sha256sum
    command -v find
    command -v du
}

# Test log file creation
@test "packager creates log files" {
    # Run packager info to create logs
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" info
    
    # Check if log directory and files are created
    [ -d "${BATS_TEST_DIRNAME}/../logs" ]
    [ -f "${BATS_TEST_DIRNAME}/../logs/packager.log" ]
}

# Test validator log file creation
@test "validator creates log files" {
    # Run validator help to create logs
    run "${BATS_TEST_DIRNAME}/../scripts/template-validator.sh" --help
    
    # Check if log directory exists (logs may not be created for help)
    [ -d "${BATS_TEST_DIRNAME}/../logs" ]
}

# Test script error handling with invalid config
@test "scripts handle invalid configuration gracefully" {
    # Create invalid config file
    local invalid_config="${BATS_TEST_DIRNAME}/../config/invalid.yaml"
    echo "invalid: yaml: content:" > "$invalid_config"
    
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" --config "$invalid_config" info
    [ "$status" -ne 0 ]
    
    # Clean up
    rm -f "$invalid_config"
}

# Test output directory creation
@test "packager creates output directory" {
    # Remove output directory
    rm -rf "$TEST_OUTPUT_DIR"
    
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" info
    [ "$status" -eq 0 ]
    
    # Check that output directory was created
    [ -d "$TEST_OUTPUT_DIR" ]
}

# Test debug mode
@test "scripts support debug mode" {
    export DEBUG=true
    
    run "${BATS_TEST_DIRNAME}/../scripts/packager.sh" info
    [ "$status" -eq 0 ]
    
    run "${BATS_TEST_DIRNAME}/../scripts/template-validator.sh" --help
    [ "$status" -eq 0 ]
    
    unset DEBUG
}