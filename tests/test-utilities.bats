#!/usr/bin/env bats
# Unit tests for utility functions and helper scripts

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Create mock utility functions
    create_mock_utilities
}

# Cleanup test environment
teardown() {
    rm -rf "$TEST_DIR"
}

# Create mock utility functions for testing
create_mock_utilities() {
    # Create a mock utilities script
    cat > "$TEST_DIR/utilities.sh" << 'EOF'
#!/bin/bash
# Mock utility functions for testing

# Logging utilities
log_with_timestamp() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# File utilities
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "Created directory: $dir"
    else
        echo "Directory already exists: $dir"
    fi
}

backup_file() {
    local file="$1"
    local backup_suffix="${2:-.bak}"
    
    if [ -f "$file" ]; then
        cp "$file" "${file}${backup_suffix}"
        echo "Backed up $file to ${file}${backup_suffix}"
        return 0
    else
        echo "File not found: $file"
        return 1
    fi
}

# Network utilities
check_connectivity() {
    local host="${1:-8.8.8.8}"
    local timeout="${2:-5}"
    
    if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
        echo "Connectivity to $host: OK"
        return 0
    else
        echo "Connectivity to $host: FAILED"
        return 1
    fi
}

# System utilities
get_system_info() {
    cat << SYSINFO
System Information:
- OS: $(uname -s)
- Kernel: $(uname -r)
- Architecture: $(uname -m)
- Hostname: $(hostname)
- Uptime: $(uptime | cut -d',' -f1 | cut -d' ' -f4-)
SYSINFO
}

# Process utilities
wait_for_process() {
    local process_name="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if pgrep "$process_name" >/dev/null 2>&1; then
            echo "Process $process_name found after ${elapsed}s"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    echo "Process $process_name not found after ${timeout}s"
    return 1
}

# String utilities
trim_whitespace() {
    local string="$1"
    # Remove leading and trailing whitespace
    echo "$string" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

to_lowercase() {
    local string="$1"
    echo "$string" | tr '[:upper:]' '[:lower:]'
}

to_uppercase() {
    local string="$1"
    echo "$string" | tr '[:lower:]' '[:upper:]'
}

# Validation utilities
validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ "$ip" =~ $regex ]]; then
        # Check each octet is <= 255
        local IFS='.'
        local octets=($ip)
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                echo "Invalid IP address: $ip"
                return 1
            fi
        done
        echo "Valid IP address: $ip"
        return 0
    else
        echo "Invalid IP address format: $ip"
        return 1
    fi
}

validate_port() {
    local port="$1"
    
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        echo "Valid port: $port"
        return 0
    else
        echo "Invalid port: $port"
        return 1
    fi
}

# Array utilities
array_contains() {
    local element="$1"
    shift
    local array=("$@")
    
    for item in "${array[@]}"; do
        if [ "$item" = "$element" ]; then
            echo "Array contains: $element"
            return 0
        fi
    done
    
    echo "Array does not contain: $element"
    return 1
}

join_array() {
    local delimiter="$1"
    shift
    local array=("$@")
    
    local result=""
    for item in "${array[@]}"; do
        if [ -z "$result" ]; then
            result="$item"
        else
            result="$result$delimiter$item"
        fi
    done
    
    echo "$result"
}

# Configuration utilities
parse_key_value() {
    local file="$1"
    local key="$2"
    
    if [ -f "$file" ]; then
        grep "^$key=" "$file" | cut -d'=' -f2- | tr -d '"'
    else
        echo "Configuration file not found: $file"
        return 1
    fi
}

set_key_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    if [ -f "$file" ]; then
        if grep -q "^$key=" "$file"; then
            sed -i "s/^$key=.*/$key=\"$value\"/" "$file"
            echo "Updated $key in $file"
        else
            echo "$key=\"$value\"" >> "$file"
            echo "Added $key to $file"
        fi
    else
        echo "$key=\"$value\"" > "$file"
        echo "Created $file with $key"
    fi
}

# Error handling utilities
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            echo "Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo "Command failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "Command failed after $max_attempts attempts"
    return 1
}

# Cleanup utilities
cleanup_temp_files() {
    local pattern="${1:-tmp.*}"
    local directory="${2:-/tmp}"
    local max_age="${3:-1}"  # days
    
    local count=0
    while IFS= read -r -d '' file; do
        rm -f "$file"
        count=$((count + 1))
    done < <(find "$directory" -name "$pattern" -type f -mtime +$max_age -print0 2>/dev/null)
    
    echo "Cleaned up $count temporary files"
}

# Export functions for testing
export -f log_with_timestamp ensure_directory backup_file check_connectivity
export -f get_system_info wait_for_process trim_whitespace to_lowercase to_uppercase
export -f validate_ip validate_port array_contains join_array
export -f parse_key_value set_key_value retry_command cleanup_temp_files
EOF
    
    chmod +x "$TEST_DIR/utilities.sh"
    source "$TEST_DIR/utilities.sh"
}

# Test logging utilities
@test "log_with_timestamp should format messages with timestamp" {
    run log_with_timestamp "INFO" "Test message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\]\ \[INFO\]\ Test\ message ]]
}

# Test file utilities
@test "ensure_directory should create missing directories" {
    local test_dir="$TEST_DIR/new/nested/directory"
    
    run ensure_directory "$test_dir"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Created directory: $test_dir" ]]
    [ -d "$test_dir" ]
}

@test "ensure_directory should handle existing directories" {
    local test_dir="$TEST_DIR/existing"
    mkdir -p "$test_dir"
    
    run ensure_directory "$test_dir"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Directory already exists: $test_dir" ]]
}

@test "backup_file should create backup of existing file" {
    local test_file="$TEST_DIR/test.txt"
    echo "test content" > "$test_file"
    
    run backup_file "$test_file"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Backed up $test_file to ${test_file}.bak" ]]
    [ -f "${test_file}.bak" ]
    [ "$(cat "${test_file}.bak")" = "test content" ]
}

@test "backup_file should handle missing files" {
    local test_file="$TEST_DIR/nonexistent.txt"
    
    run backup_file "$test_file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "File not found: $test_file" ]]
}

@test "backup_file should use custom suffix" {
    local test_file="$TEST_DIR/test.txt"
    echo "test content" > "$test_file"
    
    run backup_file "$test_file" ".backup"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Backed up $test_file to ${test_file}.backup" ]]
    [ -f "${test_file}.backup" ]
}

# Test network utilities (mocked)
@test "check_connectivity should handle successful ping" {
    # Mock ping command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/ping" << 'EOF'
#!/bin/bash
# Mock successful ping
exit 0
EOF
    chmod +x "$TEST_DIR/bin/ping"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run check_connectivity "8.8.8.8"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Connectivity to 8.8.8.8: OK" ]]
}

@test "check_connectivity should handle failed ping" {
    # Mock ping command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/ping" << 'EOF'
#!/bin/bash
# Mock failed ping
exit 1
EOF
    chmod +x "$TEST_DIR/bin/ping"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run check_connectivity "192.0.2.1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Connectivity to 192.0.2.1: FAILED" ]]
}

# Test system utilities
@test "get_system_info should return system information" {
    run get_system_info
    [ "$status" -eq 0 ]
    [[ "$output" =~ "System Information:" ]]
    [[ "$output" =~ "OS:" ]]
    [[ "$output" =~ "Kernel:" ]]
    [[ "$output" =~ "Architecture:" ]]
    [[ "$output" =~ "Hostname:" ]]
}

# Test process utilities (mocked)
@test "wait_for_process should find existing process" {
    # Mock pgrep command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/pgrep" << 'EOF'
#!/bin/bash
# Mock process found
exit 0
EOF
    chmod +x "$TEST_DIR/bin/pgrep"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run wait_for_process "test-process" 5 1
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Process test-process found after 0s" ]]
}

@test "wait_for_process should timeout when process not found" {
    # Mock pgrep command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/pgrep" << 'EOF'
#!/bin/bash
# Mock process not found
exit 1
EOF
    chmod +x "$TEST_DIR/bin/pgrep"
    
    # Mock sleep to speed up test
    cat > "$TEST_DIR/bin/sleep" << 'EOF'
#!/bin/bash
# Mock sleep - do nothing for speed
exit 0
EOF
    chmod +x "$TEST_DIR/bin/sleep"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run wait_for_process "nonexistent-process" 2 1
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Process nonexistent-process not found after 2s" ]]
}

# Test string utilities
@test "trim_whitespace should remove leading and trailing spaces" {
    result=$(trim_whitespace "  hello world  ")
    [ "$result" = "hello world" ]
    
    result=$(trim_whitespace "	tabbed	")
    [ "$result" = "tabbed" ]
    
    result=$(trim_whitespace "no-spaces")
    [ "$result" = "no-spaces" ]
}

@test "to_lowercase should convert strings to lowercase" {
    result=$(to_lowercase "HELLO WORLD")
    [ "$result" = "hello world" ]
    
    result=$(to_lowercase "MiXeD cAsE")
    [ "$result" = "mixed case" ]
    
    result=$(to_lowercase "already lowercase")
    [ "$result" = "already lowercase" ]
}

@test "to_uppercase should convert strings to uppercase" {
    result=$(to_uppercase "hello world")
    [ "$result" = "HELLO WORLD" ]
    
    result=$(to_uppercase "MiXeD cAsE")
    [ "$result" = "MIXED CASE" ]
    
    result=$(to_uppercase "ALREADY UPPERCASE")
    [ "$result" = "ALREADY UPPERCASE" ]
}

# Test validation utilities
@test "validate_ip should accept valid IP addresses" {
    run validate_ip "192.168.1.1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid IP address: 192.168.1.1" ]]
    
    run validate_ip "10.0.0.1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid IP address: 10.0.0.1" ]]
    
    run validate_ip "255.255.255.255"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid IP address: 255.255.255.255" ]]
}

@test "validate_ip should reject invalid IP addresses" {
    run validate_ip "256.1.1.1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid IP address: 256.1.1.1" ]]
    
    run validate_ip "192.168.1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid IP address format: 192.168.1" ]]
    
    run validate_ip "not.an.ip.address"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid IP address format: not.an.ip.address" ]]
}

@test "validate_port should accept valid port numbers" {
    run validate_port "80"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid port: 80" ]]
    
    run validate_port "443"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid port: 443" ]]
    
    run validate_port "65535"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid port: 65535" ]]
}

@test "validate_port should reject invalid port numbers" {
    run validate_port "0"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid port: 0" ]]
    
    run validate_port "65536"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid port: 65536" ]]
    
    run validate_port "not-a-port"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid port: not-a-port" ]]
}

# Test array utilities
@test "array_contains should find existing elements" {
    local test_array=("apple" "banana" "cherry")
    
    run array_contains "banana" "${test_array[@]}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Array contains: banana" ]]
}

@test "array_contains should not find missing elements" {
    local test_array=("apple" "banana" "cherry")
    
    run array_contains "orange" "${test_array[@]}"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Array does not contain: orange" ]]
}

@test "join_array should join elements with delimiter" {
    local test_array=("one" "two" "three")
    
    result=$(join_array "," "${test_array[@]}")
    [ "$result" = "one,two,three" ]
    
    result=$(join_array " | " "${test_array[@]}")
    [ "$result" = "one | two | three" ]
}

@test "join_array should handle single element" {
    local test_array=("single")
    
    result=$(join_array "," "${test_array[@]}")
    [ "$result" = "single" ]
}

@test "join_array should handle empty array" {
    local test_array=()
    
    result=$(join_array "," "${test_array[@]}")
    [ "$result" = "" ]
}

# Test configuration utilities
@test "parse_key_value should extract values from config file" {
    local config_file="$TEST_DIR/test.conf"
    cat > "$config_file" << 'EOF'
key1=value1
key2="quoted value"
key3=value with spaces
EOF
    
    result=$(parse_key_value "$config_file" "key1")
    [ "$result" = "value1" ]
    
    result=$(parse_key_value "$config_file" "key2")
    [ "$result" = "quoted value" ]
    
    result=$(parse_key_value "$config_file" "key3")
    [ "$result" = "value with spaces" ]
}

@test "parse_key_value should handle missing file" {
    run parse_key_value "/nonexistent/file.conf" "key1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Configuration file not found" ]]
}

@test "set_key_value should update existing keys" {
    local config_file="$TEST_DIR/test.conf"
    echo 'key1="old value"' > "$config_file"
    
    run set_key_value "$config_file" "key1" "new value"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Updated key1 in $config_file" ]]
    
    result=$(parse_key_value "$config_file" "key1")
    [ "$result" = "new value" ]
}

@test "set_key_value should add new keys" {
    local config_file="$TEST_DIR/test.conf"
    echo 'existing_key="existing value"' > "$config_file"
    
    run set_key_value "$config_file" "new_key" "new value"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Added new_key to $config_file" ]]
    
    result=$(parse_key_value "$config_file" "new_key")
    [ "$result" = "new value" ]
}

@test "set_key_value should create new file" {
    local config_file="$TEST_DIR/new.conf"
    
    run set_key_value "$config_file" "key1" "value1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Created $config_file with key1" ]]
    
    [ -f "$config_file" ]
    result=$(parse_key_value "$config_file" "key1")
    [ "$result" = "value1" ]
}

# Test error handling utilities
@test "retry_command should succeed on first attempt" {
    # Mock successful command
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/test-command" << 'EOF'
#!/bin/bash
echo "Command executed successfully"
exit 0
EOF
    chmod +x "$TEST_DIR/bin/test-command"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run retry_command 3 1 test-command
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Attempt 1/3: test-command" ]]
    [[ "$output" =~ "Command succeeded on attempt 1" ]]
}

@test "retry_command should retry on failure and eventually succeed" {
    # Mock command that fails twice then succeeds
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/test-command" << 'EOF'
#!/bin/bash
COUNTER_FILE="/tmp/retry_counter"
if [ ! -f "$COUNTER_FILE" ]; then
    echo "1" > "$COUNTER_FILE"
    echo "Command failed (attempt 1)"
    exit 1
elif [ "$(cat "$COUNTER_FILE")" = "1" ]; then
    echo "2" > "$COUNTER_FILE"
    echo "Command failed (attempt 2)"
    exit 1
else
    rm -f "$COUNTER_FILE"
    echo "Command succeeded (attempt 3)"
    exit 0
fi
EOF
    chmod +x "$TEST_DIR/bin/test-command"
    
    # Mock sleep to speed up test
    cat > "$TEST_DIR/bin/sleep" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$TEST_DIR/bin/sleep"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run retry_command 3 1 test-command
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Command succeeded on attempt 3" ]]
}

@test "retry_command should fail after max attempts" {
    # Mock command that always fails
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/test-command" << 'EOF'
#!/bin/bash
echo "Command always fails"
exit 1
EOF
    chmod +x "$TEST_DIR/bin/test-command"
    
    cat > "$TEST_DIR/bin/sleep" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$TEST_DIR/bin/sleep"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run retry_command 2 1 test-command
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Command failed after 2 attempts" ]]
}

# Test cleanup utilities
@test "cleanup_temp_files should remove matching files" {
    # Create test temporary files
    local temp_dir="$TEST_DIR/temp"
    mkdir -p "$temp_dir"
    touch "$temp_dir/tmp.file1"
    touch "$temp_dir/tmp.file2"
    touch "$temp_dir/keep.file"
    
    # Mock find command to simulate old files
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/find" << 'EOF'
#!/bin/bash
if [[ "$*" =~ "tmp.*" ]] && [[ "$*" =~ "-mtime +0" ]]; then
    printf '%s\0' "$TEST_DIR/temp/tmp.file1" "$TEST_DIR/temp/tmp.file2"
fi
EOF
    chmod +x "$TEST_DIR/bin/find"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run cleanup_temp_files "tmp.*" "$temp_dir" 0
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Cleaned up 2 temporary files" ]]
    
    # Check files were removed
    [ ! -f "$temp_dir/tmp.file1" ]
    [ ! -f "$temp_dir/tmp.file2" ]
    [ -f "$temp_dir/keep.file" ]  # Should still exist
}