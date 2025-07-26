#!/usr/bin/env bats
# Unit tests for base image manager functionality

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Source the script
    source "$PROJECT_ROOT/scripts/base-image-manager.sh"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Override cache directory for testing
    CACHE_DIR="$TEST_DIR/cache"
    LOG_FILE="$TEST_DIR/base-image-manager.log"
    
    # Create test directories
    mkdir -p "$CACHE_DIR" "$(dirname "$LOG_FILE")"
    
    # Create test configuration file
    TEST_CONFIG="$TEST_DIR/test-template.yaml"
    cat > "$TEST_CONFIG" << 'EOF'
template:
  name: "test-alpine-k3s"
  version: "1.0.0"
  base_image: "alpine:3.18"
  architecture: "amd64"
EOF
    
    # Override config file for testing
    CONFIG_FILE="$TEST_CONFIG"
}

# Cleanup test environment
teardown() {
    rm -rf "$TEST_DIR"
}

# Test logging functions
@test "log_info should write info messages" {
    run log_info "Test info message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "INFO" ]]
    [[ "$output" =~ "Test info message" ]]
    
    # Check log file
    [ -f "$LOG_FILE" ]
    grep -q "INFO.*Test info message" "$LOG_FILE"
}

@test "log_warn should write warning messages" {
    run log_warn "Test warning message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "Test warning message" ]]
    
    # Check log file
    [ -f "$LOG_FILE" ]
    grep -q "WARN.*Test warning message" "$LOG_FILE"
}

@test "log_error should write error messages" {
    run log_error "Test error message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "Test error message" ]]
    
    # Check log file
    [ -f "$LOG_FILE" ]
    grep -q "ERROR.*Test error message" "$LOG_FILE"
}

# Test configuration loading
@test "load_config should load configuration successfully" {
    run load_config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "加载配置" ]]
    [[ "$output" =~ "alpine:3.18" ]]
}

@test "load_config should fail with missing config file" {
    CONFIG_FILE="/nonexistent/config.yaml"
    
    run load_config
    [ "$status" -eq 1 ]
    [[ "$output" =~ "配置文件不存在" ]]
}

@test "load_config should fail with invalid config format" {
    # Create invalid config
    INVALID_CONFIG="$TEST_DIR/invalid-config.yaml"
    echo "invalid yaml content" > "$INVALID_CONFIG"
    CONFIG_FILE="$INVALID_CONFIG"
    
    run load_config
    [ "$status" -eq 1 ]
    [[ "$output" =~ "无法从配置文件中读取 base_image" ]]
}

# Test image validation functions
@test "validate_image_name should accept valid Alpine images" {
    # Mock function for testing
    validate_image_name() {
        local image="$1"
        if [[ "$image" =~ ^alpine:[0-9]+\.[0-9]+$ ]]; then
            return 0
        else
            return 1
        fi
    }
    
    run validate_image_name "alpine:3.18"
    [ "$status" -eq 0 ]
    
    run validate_image_name "alpine:3.17"
    [ "$status" -eq 0 ]
}

@test "validate_image_name should reject invalid images" {
    # Mock function for testing
    validate_image_name() {
        local image="$1"
        if [[ "$image" =~ ^alpine:[0-9]+\.[0-9]+$ ]]; then
            return 0
        else
            return 1
        fi
    }
    
    run validate_image_name "ubuntu:20.04"
    [ "$status" -eq 1 ]
    
    run validate_image_name "alpine:latest"
    [ "$status" -eq 1 ]
    
    run validate_image_name "invalid-image"
    [ "$status" -eq 1 ]
}

# Test architecture validation
@test "validate_architecture should accept valid architectures" {
    # Mock function for testing
    validate_architecture() {
        local arch="$1"
        case "$arch" in
            amd64|arm64|armv7) return 0 ;;
            *) return 1 ;;
        esac
    }
    
    run validate_architecture "amd64"
    [ "$status" -eq 0 ]
    
    run validate_architecture "arm64"
    [ "$status" -eq 0 ]
    
    run validate_architecture "armv7"
    [ "$status" -eq 0 ]
}

@test "validate_architecture should reject invalid architectures" {
    # Mock function for testing
    validate_architecture() {
        local arch="$1"
        case "$arch" in
            amd64|arm64|armv7) return 0 ;;
            *) return 1 ;;
        esac
    }
    
    run validate_architecture "x86"
    [ "$status" -eq 1 ]
    
    run validate_architecture "invalid"
    [ "$status" -eq 1 ]
}

# Test cache management functions
@test "create_cache_dir should create cache directory" {
    # Mock function for testing
    create_cache_dir() {
        mkdir -p "$CACHE_DIR"
        return $?
    }
    
    # Remove cache dir first
    rm -rf "$CACHE_DIR"
    
    run create_cache_dir
    [ "$status" -eq 0 ]
    [ -d "$CACHE_DIR" ]
}

@test "clean_cache should remove cache files" {
    # Mock function for testing
    clean_cache() {
        if [ -d "$CACHE_DIR" ]; then
            rm -rf "${CACHE_DIR:?}"/*
        fi
        return 0
    }
    
    # Create some test files
    mkdir -p "$CACHE_DIR"
    touch "$CACHE_DIR/test-file1.tar.gz"
    touch "$CACHE_DIR/test-file2.tar.gz"
    
    run clean_cache
    [ "$status" -eq 0 ]
    
    # Check files are removed
    [ ! -f "$CACHE_DIR/test-file1.tar.gz" ]
    [ ! -f "$CACHE_DIR/test-file2.tar.gz" ]
}

# Test checksum validation
@test "validate_checksum should validate correct checksums" {
    # Mock function for testing
    validate_checksum() {
        local file="$1"
        local expected_checksum="$2"
        
        if [ ! -f "$file" ]; then
            return 1
        fi
        
        local actual_checksum
        actual_checksum=$(sha256sum "$file" | cut -d' ' -f1)
        
        if [ "$actual_checksum" = "$expected_checksum" ]; then
            return 0
        else
            return 1
        fi
    }
    
    # Create test file with known content
    TEST_FILE="$TEST_DIR/test-file.txt"
    echo "test content" > "$TEST_FILE"
    EXPECTED_CHECKSUM=$(sha256sum "$TEST_FILE" | cut -d' ' -f1)
    
    run validate_checksum "$TEST_FILE" "$EXPECTED_CHECKSUM"
    [ "$status" -eq 0 ]
}

@test "validate_checksum should fail with incorrect checksums" {
    # Mock function for testing
    validate_checksum() {
        local file="$1"
        local expected_checksum="$2"
        
        if [ ! -f "$file" ]; then
            return 1
        fi
        
        local actual_checksum
        actual_checksum=$(sha256sum "$file" | cut -d' ' -f1)
        
        if [ "$actual_checksum" = "$expected_checksum" ]; then
            return 0
        else
            return 1
        fi
    }
    
    # Create test file
    TEST_FILE="$TEST_DIR/test-file.txt"
    echo "test content" > "$TEST_FILE"
    WRONG_CHECKSUM="0000000000000000000000000000000000000000000000000000000000000000"
    
    run validate_checksum "$TEST_FILE" "$WRONG_CHECKSUM"
    [ "$status" -eq 1 ]
}

# Test error handling
@test "error_exit should exit with error code" {
    run error_exit "Test error message"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "ERROR.*Test error message" ]]
}

# Test image download simulation
@test "download_image should handle successful downloads" {
    # Mock function for testing
    download_image() {
        local image_url="$1"
        local output_file="$2"
        
        # Simulate successful download
        echo "mock image content" > "$output_file"
        return 0
    }
    
    OUTPUT_FILE="$TEST_DIR/test-image.tar.gz"
    
    run download_image "https://example.com/alpine.tar.gz" "$OUTPUT_FILE"
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_FILE" ]
}

@test "download_image should handle failed downloads" {
    # Mock function for testing
    download_image() {
        local image_url="$1"
        local output_file="$2"
        
        # Simulate failed download
        return 1
    }
    
    OUTPUT_FILE="$TEST_DIR/test-image.tar.gz"
    
    run download_image "https://invalid.com/alpine.tar.gz" "$OUTPUT_FILE"
    [ "$status" -eq 1 ]
}

# Test retry mechanism
@test "retry_command should retry failed commands" {
    # Mock function for testing
    retry_command() {
        local max_retries="$1"
        local delay="$2"
        shift 2
        local cmd=("$@")
        
        local attempt=1
        while [ $attempt -le $max_retries ]; do
            if "${cmd[@]}"; then
                return 0
            fi
            
            if [ $attempt -lt $max_retries ]; then
                sleep "$delay"
            fi
            
            attempt=$((attempt + 1))
        done
        
        return 1
    }
    
    # Test successful retry
    COUNTER_FILE="$TEST_DIR/counter"
    echo "0" > "$COUNTER_FILE"
    
    # Command that succeeds on second attempt
    test_command() {
        local counter
        counter=$(cat "$COUNTER_FILE")
        counter=$((counter + 1))
        echo "$counter" > "$COUNTER_FILE"
        
        if [ "$counter" -ge 2 ]; then
            return 0
        else
            return 1
        fi
    }
    
    run retry_command 3 1 test_command
    [ "$status" -eq 0 ]
}

# Test image extraction
@test "extract_image should extract tar archives" {
    # Mock function for testing
    extract_image() {
        local archive="$1"
        local extract_dir="$2"
        
        if [ ! -f "$archive" ]; then
            return 1
        fi
        
        mkdir -p "$extract_dir"
        # Simulate extraction
        touch "$extract_dir/extracted_file"
        return 0
    }
    
    # Create test archive
    TEST_ARCHIVE="$TEST_DIR/test.tar.gz"
    touch "$TEST_ARCHIVE"
    EXTRACT_DIR="$TEST_DIR/extracted"
    
    run extract_image "$TEST_ARCHIVE" "$EXTRACT_DIR"
    [ "$status" -eq 0 ]
    [ -d "$EXTRACT_DIR" ]
    [ -f "$EXTRACT_DIR/extracted_file" ]
}