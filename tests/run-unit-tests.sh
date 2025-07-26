#!/bin/bash
# Unit test runner for PVE LXC K3s Template project
# This script runs all unit tests using the bats testing framework

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_RESULTS_DIR="${PROJECT_ROOT}/logs/test-results"
COVERAGE_DIR="${PROJECT_ROOT}/logs/coverage"

# Test configuration
BATS_PARALLEL_JOBS="${BATS_PARALLEL_JOBS:-4}"
VERBOSE="${VERBOSE:-false}"
COVERAGE="${COVERAGE:-false}"
FILTER="${FILTER:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log_info "Checking test dependencies..."
    
    local missing_deps=()
    
    # Check for bats
    if ! command -v bats >/dev/null 2>&1; then
        missing_deps+=("bats-core")
    fi
    
    # Check for required tools
    local required_tools=("jq" "yq" "tar" "gzip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_warning "Optional tool not found: $tool (some tests may be skipped)"
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies:"
        log_info "  Ubuntu/Debian: sudo apt-get install bats"
        log_info "  macOS: brew install bats-core"
        log_info "  Alpine: apk add bats"
        return 1
    fi
    
    log_success "All required dependencies are available"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test result directories
    mkdir -p "$TEST_RESULTS_DIR" "$COVERAGE_DIR"
    
    # Set test environment variables
    export BATS_TEST_TIMEOUT=300
    export BATS_TEST_RETRIES=1
    
    # Create temporary directory for tests
    export TEST_TMPDIR="$(mktemp -d)"
    
    log_success "Test environment setup complete"
}

# Cleanup test environment
cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    
    # Remove temporary directories
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
    
    # Clean up any leftover test processes
    pkill -f "bats.*test-.*\.bats" 2>/dev/null || true
    
    log_success "Test environment cleanup complete"
}

# Run individual test file
run_test_file() {
    local test_file="$1"
    local test_name="$(basename "$test_file" .bats)"
    local output_file="$TEST_RESULTS_DIR/${test_name}.tap"
    local timing_file="$TEST_RESULTS_DIR/${test_name}.timing"
    
    log_info "Running test: $test_name"
    
    local start_time=$(date +%s)
    local exit_code=0
    
    # Run bats with appropriate options
    local bats_args=()
    
    if [ "$VERBOSE" = "true" ]; then
        bats_args+=("--verbose-run")
    fi
    
    if [ -n "$FILTER" ]; then
        bats_args+=("--filter" "$FILTER")
    fi
    
    # Run the test
    if [[ ${#bats_args[@]} -gt 0 ]]; then
        if bats "${bats_args[@]}" --tap "$test_file" > "$output_file" 2>&1; then
            log_success "✓ $test_name passed"
        else
            exit_code=$?
            log_error "✗ $test_name failed (exit code: $exit_code)"
        fi
    else
        if bats --tap "$test_file" > "$output_file" 2>&1; then
            log_success "✓ $test_name passed"
        else
            exit_code=$?
            log_error "✗ $test_name failed (exit code: $exit_code)"
        fi
    fi
        
    # Show test output on failure
    if [ "$VERBOSE" = "true" ]; then
        echo "--- Test output for $test_name ---"
        cat "$output_file"
        echo "--- End test output ---"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "$duration" > "$timing_file"
    
    return $exit_code
}

# Run all tests
run_all_tests() {
    log_info "Running all unit tests..."
    
    local test_files=()
    local failed_tests=()
    local passed_tests=()
    local total_duration=0
    
    # Find all test files
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$SCRIPT_DIR" -name "test-*.bats" -print0 | sort -z)
    
    if [ ${#test_files[@]} -eq 0 ]; then
        log_warning "No test files found in $SCRIPT_DIR"
        return 0
    fi
    
    log_info "Found ${#test_files[@]} test files"
    
    # Run tests
    local start_time=$(date +%s)
    
    for test_file in "${test_files[@]}"; do
        local test_name="$(basename "$test_file" .bats)"
        
        if run_test_file "$test_file"; then
            passed_tests+=("$test_name")
        else
            failed_tests+=("$test_name")
        fi
        
        # Add timing
        local timing_file="$TEST_RESULTS_DIR/${test_name}.timing"
        if [ -f "$timing_file" ]; then
            local test_duration=$(cat "$timing_file")
            total_duration=$((total_duration + test_duration))
        fi
    done
    
    local end_time=$(date +%s)
    local wall_time=$((end_time - start_time))
    
    # Generate summary
    generate_test_summary "${passed_tests[@]}" "${failed_tests[@]}" "$total_duration" "$wall_time"
    
    # Return appropriate exit code
    if [ ${#failed_tests[@]} -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Generate test summary
generate_test_summary() {
    local passed_tests=("${@:1:$((($# - 2) / 2))}")
    local failed_tests=("${@:$(((($# - 2) / 2) + 1)):$((($# - 2) / 2))}")
    local total_duration="${@: -2:1}"
    local wall_time="${@: -1:1}"
    
    local total_tests=$((${#passed_tests[@]} + ${#failed_tests[@]}))
    local success_rate=0
    
    if [ $total_tests -gt 0 ]; then
        success_rate=$(( ${#passed_tests[@]} * 100 / total_tests ))
    fi
    
    # Create summary report
    local summary_file="$TEST_RESULTS_DIR/summary.txt"
    
    cat > "$summary_file" << EOF
# Unit Test Summary Report

## Test Execution Summary
- **Total Tests**: $total_tests
- **Passed**: ${#passed_tests[@]}
- **Failed**: ${#failed_tests[@]}
- **Success Rate**: ${success_rate}%
- **Total Duration**: ${total_duration}s
- **Wall Clock Time**: ${wall_time}s

## Passed Tests
$(printf '%s\n' "${passed_tests[@]}" | sed 's/^/- /')

## Failed Tests
$(printf '%s\n' "${failed_tests[@]}" | sed 's/^/- /')

## Test Results Location
- **Results Directory**: $TEST_RESULTS_DIR
- **Individual Results**: $TEST_RESULTS_DIR/*.tap
- **Timing Information**: $TEST_RESULTS_DIR/*.timing

## Generated
- **Date**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- **Host**: $(hostname)
- **User**: $(whoami)
- **Bats Version**: $(bats --version 2>/dev/null || echo "Unknown")

EOF
    
    # Display summary
    echo
    log_info "=========================================="
    log_info "Unit Test Summary"
    log_info "=========================================="
    log_info "Total Tests: $total_tests"
    
    if [ ${#passed_tests[@]} -gt 0 ]; then
        log_success "Passed: ${#passed_tests[@]}"
    fi
    
    if [ ${#failed_tests[@]} -gt 0 ]; then
        log_error "Failed: ${#failed_tests[@]}"
        log_info "Failed tests:"
        for test in "${failed_tests[@]}"; do
            log_error "  - $test"
        done
    fi
    
    log_info "Success Rate: ${success_rate}%"
    log_info "Total Duration: ${total_duration}s"
    log_info "Wall Clock Time: ${wall_time}s"
    log_info "Summary Report: $summary_file"
    
    if [ ${#failed_tests[@]} -eq 0 ]; then
        log_success "All tests passed! 🎉"
    else
        log_error "Some tests failed. Check individual test outputs for details."
    fi
}

# Generate coverage report (if enabled)
generate_coverage_report() {
    if [ "$COVERAGE" != "true" ]; then
        return 0
    fi
    
    log_info "Generating coverage report..."
    
    # This is a placeholder for coverage reporting
    # In a real implementation, you might use tools like:
    # - bashcov for bash script coverage
    # - kcov for general coverage
    # - Custom coverage analysis
    
    local coverage_file="$COVERAGE_DIR/coverage.txt"
    
    cat > "$coverage_file" << EOF
# Code Coverage Report

## Coverage Summary
Coverage reporting is not yet implemented for shell scripts.

## Recommendations
To implement coverage reporting, consider:
1. Using bashcov for bash script coverage
2. Using kcov for general coverage analysis
3. Implementing custom coverage tracking

## Test Files Analyzed
$(find "$SCRIPT_DIR" -name "test-*.bats" -exec basename {} \; | sort)

## Source Files
$(find "$PROJECT_ROOT/scripts" -name "*.sh" -exec basename {} \; | sort)

Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF
    
    log_info "Coverage report placeholder created: $coverage_file"
}

# Show help
show_help() {
    cat << EOF
Unit Test Runner for PVE LXC K3s Template

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    run                 Run all unit tests (default)
    list                List available test files
    clean               Clean test results and temporary files
    help                Show this help message

Options:
    --verbose           Enable verbose output
    --coverage          Generate coverage report (placeholder)
    --filter PATTERN    Run only tests matching pattern
    --jobs N            Number of parallel jobs (default: 4)
    --timeout N         Test timeout in seconds (default: 300)

Environment Variables:
    VERBOSE=true        Enable verbose output
    COVERAGE=true       Generate coverage report
    FILTER=pattern      Filter tests by pattern
    BATS_PARALLEL_JOBS  Number of parallel jobs

Examples:
    # Run all tests
    $0

    # Run tests with verbose output
    $0 --verbose

    # Run only config-related tests
    $0 --filter config

    # Run with coverage
    $0 --coverage

    # List available tests
    $0 list

    # Clean test results
    $0 clean

EOF
}

# List available tests
list_tests() {
    log_info "Available test files:"
    
    find "$SCRIPT_DIR" -name "test-*.bats" | sort | while read -r test_file; do
        local test_name="$(basename "$test_file" .bats)"
        local test_count
        test_count=$(grep -c "^@test" "$test_file" 2>/dev/null || echo "0")
        echo "  - $test_name ($test_count tests)"
    done
}

# Clean test results
clean_tests() {
    log_info "Cleaning test results and temporary files..."
    
    # Remove test results
    if [ -d "$TEST_RESULTS_DIR" ]; then
        rm -rf "$TEST_RESULTS_DIR"
        log_info "Removed test results directory"
    fi
    
    # Remove coverage results
    if [ -d "$COVERAGE_DIR" ]; then
        rm -rf "$COVERAGE_DIR"
        log_info "Removed coverage directory"
    fi
    
    # Remove temporary files
    find /tmp -name "tmp.*" -path "*/bats-*" -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true
    
    log_success "Cleanup complete"
}

# Parse command line arguments
parse_arguments() {
    local command="run"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            run|list|clean|help)
                command="$1"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --coverage)
                COVERAGE=true
                shift
                ;;
            --filter)
                FILTER="$2"
                shift 2
                ;;
            --jobs)
                BATS_PARALLEL_JOBS="$2"
                shift 2
                ;;
            --timeout)
                export BATS_TEST_TIMEOUT="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execute command
    case $command in
        run)
            main
            ;;
        list)
            list_tests
            ;;
        clean)
            clean_tests
            ;;
        help)
            show_help
            ;;
    esac
}

# Main function
main() {
    local start_time=$(date +%s)
    
    log_info "Starting unit test execution..."
    log_info "Project: PVE LXC K3s Template"
    log_info "Test Directory: $SCRIPT_DIR"
    log_info "Results Directory: $TEST_RESULTS_DIR"
    
    # Setup
    if ! check_dependencies; then
        exit 1
    fi
    
    setup_test_environment
    
    # Ensure cleanup on exit
    trap cleanup_test_environment EXIT
    
    # Run tests
    local exit_code=0
    if ! run_all_tests; then
        exit_code=1
    fi
    
    # Generate coverage report if requested
    generate_coverage_report
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    log_info "Test execution completed in ${total_time}s"
    
    return $exit_code
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
fi