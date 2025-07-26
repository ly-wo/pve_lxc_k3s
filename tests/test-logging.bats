#!/usr/bin/env bats
# Unit tests for logging system functionality

# Setup test environment
setup() {
    # Get the project root directory
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Source the script
    source "$PROJECT_ROOT/scripts/logging.sh"
    
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    
    # Override log directory for testing
    LOG_DIR="$TEST_DIR/logs"
    LOG_MAX_SIZE=1024  # Small size for testing rotation
    LOG_MAX_FILES=3
    LOG_FORMAT="structured"
    LOG_LEVEL="DEBUG"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
}

# Cleanup test environment
teardown() {
    rm -rf "$TEST_DIR"
}

# Test log level functions
@test "get_log_level_num should return correct numeric values" {
    result=$(get_log_level_num "DEBUG")
    [ "$result" -eq 0 ]
    
    result=$(get_log_level_num "INFO")
    [ "$result" -eq 1 ]
    
    result=$(get_log_level_num "WARN")
    [ "$result" -eq 2 ]
    
    result=$(get_log_level_num "ERROR")
    [ "$result" -eq 3 ]
    
    result=$(get_log_level_num "FATAL")
    [ "$result" -eq 4 ]
    
    # Test unknown level defaults to INFO
    result=$(get_log_level_num "UNKNOWN")
    [ "$result" -eq 1 ]
}

@test "should_log should respect log level filtering" {
    LOG_LEVEL="WARN"
    
    # Should log WARN and above
    run should_log "WARN"
    [ "$status" -eq 0 ]
    
    run should_log "ERROR"
    [ "$status" -eq 0 ]
    
    run should_log "FATAL"
    [ "$status" -eq 0 ]
    
    # Should not log below WARN
    run should_log "INFO"
    [ "$status" -eq 1 ]
    
    run should_log "DEBUG"
    [ "$status" -eq 1 ]
}

# Test caller information
@test "get_caller_info should return caller details" {
    test_function() {
        get_caller_info 1
    }
    
    result=$(test_function)
    [[ "$result" =~ test-logging.bats:[0-9]+:test_function ]]
}

# Test structured logging
@test "log_structured should create valid JSON output" {
    result=$(log_structured "INFO" "test-component" "Test message" '{"key": "value"}' "TEST_001" '["suggestion1", "suggestion2"]')
    
    # Check if output is valid JSON
    echo "$result" | jq . >/dev/null
    [ $? -eq 0 ]
    
    # Check required fields
    [[ "$result" =~ "\"level\": \"INFO\"" ]]
    [[ "$result" =~ "\"component\": \"test-component\"" ]]
    [[ "$result" =~ "\"message\": \"Test message\"" ]]
    [[ "$result" =~ "\"error_code\": \"TEST_001\"" ]]
    [[ "$result" =~ "\"timestamp\":" ]]
    [[ "$result" =~ "\"caller\":" ]]
}

# Test simple logging
@test "log_simple should create formatted output" {
    result=$(log_simple "INFO" "test-component" "Test message")
    
    [[ "$result" =~ \[.*\]\ \[INFO\]\ \[test-component\]\ Test\ message ]]
}

# Test log writing
@test "write_log should write to file and output" {
    run write_log "INFO" "test-component" "Test message" '{}' "" '[]' "test.log"
    [ "$status" -eq 0 ]
    
    # Check log file was created
    [ -f "$LOG_DIR/test.log" ]
    
    # Check log content
    grep -q "Test message" "$LOG_DIR/test.log"
}

@test "write_log should respect log level filtering" {
    LOG_LEVEL="ERROR"
    
    # Should not write DEBUG message
    run write_log "DEBUG" "test-component" "Debug message" '{}' "" '[]' "test.log"
    [ "$status" -eq 0 ]
    
    # Log file should not exist or be empty
    if [ -f "$LOG_DIR/test.log" ]; then
        [ ! -s "$LOG_DIR/test.log" ]
    fi
    
    # Should write ERROR message
    run write_log "ERROR" "test-component" "Error message" '{}' "" '[]' "test.log"
    [ "$status" -eq 0 ]
    
    # Check log file contains error message
    [ -f "$LOG_DIR/test.log" ]
    grep -q "Error message" "$LOG_DIR/test.log"
}

# Test convenience logging functions
@test "log_info should write info messages" {
    run log_info "test-component" "Info message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Info message" ]]
    
    # Check log file
    [ -f "$LOG_DIR/test-component.log" ]
    grep -q "Info message" "$LOG_DIR/test-component.log"
}

@test "log_warn should write warning messages" {
    run log_warn "test-component" "Warning message" '{"context": "test"}' '["Check configuration"]'
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning message" ]]
    
    # Check log file
    [ -f "$LOG_DIR/test-component.log" ]
    grep -q "Warning message" "$LOG_DIR/test-component.log"
}

@test "log_error should write error messages" {
    run log_error "test-component" "Error message" '{"error": "test"}' "ERR_001" '["Check logs"]'
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Error message" ]]
    
    # Check log file
    [ -f "$LOG_DIR/test-component.log" ]
    grep -q "Error message" "$LOG_DIR/test-component.log"
}

@test "log_debug should write debug messages when debug enabled" {
    LOG_LEVEL="DEBUG"
    
    run log_debug "test-component" "Debug message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Debug message" ]]
}

@test "log_debug should not write when debug disabled" {
    LOG_LEVEL="INFO"
    
    run log_debug "test-component" "Debug message"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "Debug message" ]]
}

@test "log_fatal should write fatal message and exit" {
    run log_fatal "test-component" "Fatal error"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Fatal error" ]]
}

# Test log rotation
@test "rotate_log_if_needed should rotate when file exceeds max size" {
    LOG_MAX_SIZE=10  # Very small for testing
    
    # Create a log file that exceeds max size
    TEST_LOG="$LOG_DIR/test.log"
    echo "This is a test log entry that exceeds the maximum size limit" > "$TEST_LOG"
    
    run rotate_log_if_needed "$TEST_LOG"
    [ "$status" -eq 0 ]
    
    # Original file should be moved to .1
    [ -f "$LOG_DIR/test.log.1" ]
    
    # New log file should not exist yet
    [ ! -f "$TEST_LOG" ]
}

@test "rotate_log should manage multiple rotation files" {
    LOG_MAX_FILES=3
    
    # Create test log files
    TEST_LOG="$LOG_DIR/test.log"
    echo "current" > "$TEST_LOG"
    echo "rotation1" > "$LOG_DIR/test.log.1"
    echo "rotation2" > "$LOG_DIR/test.log.2"
    
    run rotate_log "$TEST_LOG"
    [ "$status" -eq 0 ]
    
    # Check rotation
    [ -f "$LOG_DIR/test.log.1" ]
    [ -f "$LOG_DIR/test.log.2" ]
    [ -f "$LOG_DIR/test.log.3" ]
    [ ! -f "$TEST_LOG" ]
    
    # Check content moved correctly
    [ "$(cat "$LOG_DIR/test.log.1")" = "current" ]
    [ "$(cat "$LOG_DIR/test.log.2")" = "rotation1" ]
    [ "$(cat "$LOG_DIR/test.log.3")" = "rotation2" ]
}

@test "rotate_log should remove oldest files when exceeding max files" {
    LOG_MAX_FILES=2
    
    # Create test log files
    TEST_LOG="$LOG_DIR/test.log"
    echo "current" > "$TEST_LOG"
    echo "rotation1" > "$LOG_DIR/test.log.1"
    echo "rotation2" > "$LOG_DIR/test.log.2"  # This should be removed
    
    run rotate_log "$TEST_LOG"
    [ "$status" -eq 0 ]
    
    # Check oldest file is removed
    [ ! -f "$LOG_DIR/test.log.2" ]
    
    # Check remaining files
    [ -f "$LOG_DIR/test.log.1" ]
    [ "$(cat "$LOG_DIR/test.log.1")" = "current" ]
}

# Test error classification
@test "classify_error should classify network errors" {
    result=$(classify_error "curl: (7) Failed to connect")
    [ "$result" = "NETWORK_ERROR" ]
    
    result=$(classify_error "wget: unable to download")
    [ "$result" = "NETWORK_ERROR" ]
    
    result=$(classify_error "download failed")
    [ "$result" = "NETWORK_ERROR" ]
}

@test "classify_error should classify permission errors" {
    result=$(classify_error "permission denied")
    [ "$result" = "PERMISSION_ERROR" ]
    
    result=$(classify_error "access denied")
    [ "$result" = "PERMISSION_ERROR" ]
}

@test "classify_error should classify storage errors" {
    result=$(classify_error "no space left on device")
    [ "$result" = "STORAGE_ERROR" ]
    
    result=$(classify_error "disk full")
    [ "$result" = "STORAGE_ERROR" ]
}

@test "classify_error should classify timeout errors" {
    result=$(classify_error "connection timeout")
    [ "$result" = "TIMEOUT_ERROR" ]
    
    result=$(classify_error "operation timed out")
    [ "$result" = "TIMEOUT_ERROR" ]
}

@test "classify_error should classify not found errors" {
    result=$(classify_error "file not found")
    [ "$result" = "NOT_FOUND_ERROR" ]
    
    result=$(classify_error "HTTP 404 error")
    [ "$result" = "NOT_FOUND_ERROR" ]
}

@test "classify_error should default to general error" {
    result=$(classify_error "unknown error occurred")
    [ "$result" = "GENERAL_ERROR" ]
}

# Test error suggestions
@test "get_error_suggestions should provide network error suggestions" {
    result=$(get_error_suggestions "NETWORK_ERROR")
    [[ "$result" =~ "检查网络连接" ]]
    [[ "$result" =~ "验证 DNS 解析" ]]
    [[ "$result" =~ "尝试使用代理或镜像源" ]]
}

@test "get_error_suggestions should provide permission error suggestions" {
    result=$(get_error_suggestions "PERMISSION_ERROR")
    [[ "$result" =~ "检查文件权限" ]]
    [[ "$result" =~ "确认用户权限" ]]
    [[ "$result" =~ "使用 sudo 或切换用户" ]]
}

@test "get_error_suggestions should provide storage error suggestions" {
    result=$(get_error_suggestions "STORAGE_ERROR")
    [[ "$result" =~ "检查磁盘空间" ]]
    [[ "$result" =~ "清理临时文件" ]]
    [[ "$result" =~ "检查磁盘权限" ]]
}

@test "get_error_suggestions should provide general suggestions for unknown types" {
    result=$(get_error_suggestions "UNKNOWN_ERROR")
    [[ "$result" =~ "查看详细错误信息" ]]
    [[ "$result" =~ "检查系统日志" ]]
    [[ "$result" =~ "联系技术支持" ]]
}

# Test error handling wrapper
@test "handle_error should classify and log errors" {
    run handle_error "curl: connection failed" "test-component" 1 '{"url": "https://example.com"}'
    [ "$status" -eq 1 ]
    
    # Check log file was created
    [ -f "$LOG_DIR/test-component.log" ]
    
    # Check error was logged with classification
    grep -q "curl: connection failed" "$LOG_DIR/test-component.log"
    grep -q "NETWORK_ERROR" "$LOG_DIR/test-component.log"
}

# Test performance logging
@test "log_performance should log performance metrics" {
    run log_performance "test-component" "test-operation" "1.5s" '{"size": "1MB"}'
    [ "$status" -eq 0 ]
    [[ "$output" =~ "性能监控" ]]
    
    # Check log file
    [ -f "$LOG_DIR/test-component.log" ]
    grep -q "test-operation" "$LOG_DIR/test-component.log"
    grep -q "1.5s" "$LOG_DIR/test-component.log"
}

# Test log cleanup
@test "cleanup_old_logs should remove old log files" {
    # Create old log files
    touch "$LOG_DIR/old.log.1"
    touch "$LOG_DIR/old.log.2"
    touch "$LOG_DIR/current.log"
    
    # Make files appear old (this is a mock test)
    # In real scenario, we'd use find with -mtime
    
    # Mock find command to simulate old files
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/find" << 'EOF'
#!/bin/bash
if [[ "$*" =~ "-mtime +7" ]]; then
    echo "$LOG_DIR/old.log.1"
    echo "$LOG_DIR/old.log.2"
fi
EOF
    chmod +x "$TEST_DIR/bin/find"
    export PATH="$TEST_DIR/bin:$PATH"
    
    run cleanup_old_logs 7
    [ "$status" -eq 0 ]
    [[ "$output" =~ "清理 7 天前的日志文件" ]]
    [[ "$output" =~ "日志清理完成" ]]
}

# Test log statistics
@test "get_log_stats should show file statistics" {
    # Create test log file
    TEST_LOG="$LOG_DIR/test.log"
    echo -e "line1\nline2\nline3" > "$TEST_LOG"
    
    run get_log_stats "test.log"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "日志统计信息" ]]
    [[ "$output" =~ "文件大小:" ]]
    [[ "$output" =~ "行数: 3" ]]
    [[ "$output" =~ "最后修改:" ]]
}

@test "get_log_stats should show directory statistics when no file specified" {
    # Create multiple test log files
    echo "test1" > "$LOG_DIR/test1.log"
    echo "test2" > "$LOG_DIR/test2.log"
    touch "$LOG_DIR/test3.log.1"
    
    run get_log_stats
    [ "$status" -eq 0 ]
    [[ "$output" =~ "日志统计信息" ]]
    [[ "$output" =~ "总大小:" ]]
    [[ "$output" =~ "文件数量:" ]]
    [[ "$output" =~ "文件列表:" ]]
}

# Test format switching
@test "logging should work with simple format" {
    LOG_FORMAT="simple"
    
    run log_info "test-component" "Simple format test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[.*\]\ \[INFO\]\ \[test-component\]\ Simple\ format\ test ]]
}

@test "logging should work with structured format" {
    LOG_FORMAT="structured"
    
    run log_info "test-component" "Structured format test"
    [ "$status" -eq 0 ]
    
    # Output should be valid JSON
    echo "$output" | jq . >/dev/null
    [ $? -eq 0 ]
}

# Test concurrent logging (basic test)
@test "logging should handle concurrent writes" {
    # Create multiple log entries simultaneously
    (log_info "component1" "Message 1" &)
    (log_info "component2" "Message 2" &)
    (log_info "component3" "Message 3" &)
    wait
    
    # Check all messages were logged
    [ -f "$LOG_DIR/component1.log" ]
    [ -f "$LOG_DIR/component2.log" ]
    [ -f "$LOG_DIR/component3.log" ]
    
    grep -q "Message 1" "$LOG_DIR/component1.log"
    grep -q "Message 2" "$LOG_DIR/component2.log"
    grep -q "Message 3" "$LOG_DIR/component3.log"
}

# Test edge cases
@test "logging should handle empty messages" {
    run log_info "test-component" ""
    [ "$status" -eq 0 ]
    
    # Should still create log entry
    [ -f "$LOG_DIR/test-component.log" ]
}

@test "logging should handle special characters in messages" {
    run log_info "test-component" "Message with special chars: !@#$%^&*(){}[]|\\:;\"'<>?,./"
    [ "$status" -eq 0 ]
    
    # Check message was logged
    [ -f "$LOG_DIR/test-component.log" ]
    grep -q "special chars" "$LOG_DIR/test-component.log"
}

@test "logging should handle very long messages" {
    LONG_MESSAGE=$(printf 'A%.0s' {1..1000})
    
    run log_info "test-component" "$LONG_MESSAGE"
    [ "$status" -eq 0 ]
    
    # Check message was logged
    [ -f "$LOG_DIR/test-component.log" ]
    grep -q "AAAA" "$LOG_DIR/test-component.log"
}