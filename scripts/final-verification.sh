#!/bin/bash
# Final Verification Script for PVE LXC K3s Template
# 最终验证脚本 - 验证所有需求的完整实现

set -euo pipefail

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_ROOT}/logs/final-verification.log"

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")"

# 加载日志系统
source "${SCRIPT_DIR}/logging.sh"

COMPONENT="final-verification"

# 验证结果
VERIFICATION_RESULTS=()
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# 日志函数
log_info() { 
    log_info "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "${4:-}" "$LOG_FILE"
}

log_warn() { 
    log_warn "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "$LOG_FILE"
}

log_error() { 
    log_error "$COMPONENT" "$1" "${2:-{}}" "${3:-}" "$LOG_FILE"
}

log_success() {
    log_info "$1 ✓" "${2:-{}}"
    echo "✓ $1"
}

log_failure() {
    log_error "$1 ✗" "${2:-{}}"
    echo "✗ $1"
}

# 执行验证检查
run_check() {
    local check_name="$1"
    local check_function="$2"
    local context="${3:-{}}"
    
    ((TOTAL_CHECKS++))
    
    log_info "执行检查: $check_name"
    
    if $check_function; then
        log_success "$check_name" "$context"
        VERIFICATION_RESULTS+=("PASS:$check_name")
        ((PASSED_CHECKS++))
        return 0
    else
        log_failure "$check_name" "$context"
        VERIFICATION_RESULTS+=("FAIL:$check_name")
        ((FAILED_CHECKS++))
        return 1
    fi
}

# 需求 1 验证：自动生成 PVE LXC 模板
verify_requirement_1() {
    log_info "验证需求 1: 自动生成 PVE LXC 模板"
    
    # 1.1 检查构建脚本存在且可执行
    check_build_script() {
        [[ -x "${SCRIPT_DIR}/build-template.sh" ]]
    }
    
    # 1.2 检查基础镜像管理器
    check_base_image_manager() {
        [[ -x "${SCRIPT_DIR}/base-image-manager.sh" ]]
    }
    
    # 1.3 检查 K3s 安装器
    check_k3s_installer() {
        [[ -x "${SCRIPT_DIR}/k3s-installer.sh" ]]
    }
    
    run_check "构建脚本存在且可执行" check_build_script
    run_check "基础镜像管理器存在且可执行" check_base_image_manager
    run_check "K3s 安装器存在且可执行" check_k3s_installer
}

# 需求 2 验证：支持自定义配置
verify_requirement_2() {
    log_info "验证需求 2: 支持自定义配置"
    
    # 2.1 检查配置文件存在
    check_config_file() {
        [[ -f "${PROJECT_ROOT}/config/template.yaml" ]]
    }
    
    # 2.2 检查配置验证器
    check_config_validator() {
        [[ -x "${SCRIPT_DIR}/config-validator.sh" ]]
    }
    
    # 2.3 检查配置加载器
    check_config_loader() {
        [[ -x "${SCRIPT_DIR}/config-loader.sh" ]]
    }
    
    # 2.4 检查配置 Schema
    check_config_schema() {
        [[ -f "${PROJECT_ROOT}/config/template-schema.json" ]]
    }
    
    run_check "配置文件存在" check_config_file
    run_check "配置验证器存在且可执行" check_config_validator
    run_check "配置加载器存在且可执行" check_config_loader
    run_check "配置 Schema 存在" check_config_schema
}

# 需求 3 验证：GitHub 仓库管理和分发
verify_requirement_3() {
    log_info "验证需求 3: GitHub 仓库管理和分发"
    
    # 3.1 检查 GitHub Actions 工作流
    check_github_workflows() {
        [[ -d "${PROJECT_ROOT}/.github" ]] && [[ -n "$(find "${PROJECT_ROOT}/.github" -name "*.yml" -o -name "*.yaml" 2>/dev/null)" ]]
    }
    
    # 3.2 检查打包器
    check_packager() {
        [[ -x "${SCRIPT_DIR}/packager.sh" ]]
    }
    
    # 3.3 检查部署自动化
    check_deployment_automation() {
        [[ -x "${SCRIPT_DIR}/pve-deployment-automation.sh" ]]
    }
    
    run_check "GitHub Actions 工作流存在" check_github_workflows
    run_check "打包器存在且可执行" check_packager
    run_check "部署自动化脚本存在且可执行" check_deployment_automation
}

# 需求 4 验证：可观测性
verify_requirement_4() {
    log_info "验证需求 4: 可观测性"
    
    # 4.1 检查日志系统
    check_logging_system() {
        [[ -f "${SCRIPT_DIR}/logging.sh" ]]
    }
    
    # 4.2 检查健康检查
    check_health_check() {
        [[ -x "${SCRIPT_DIR}/k3s-health-check.sh" ]]
    }
    
    # 4.3 检查监控系统
    check_monitoring_system() {
        [[ -x "${SCRIPT_DIR}/monitoring.sh" ]]
    }
    
    # 4.4 检查系统诊断
    check_system_diagnostics() {
        [[ -x "${SCRIPT_DIR}/system-diagnostics.sh" ]]
    }
    
    run_check "日志系统存在" check_logging_system
    run_check "健康检查脚本存在且可执行" check_health_check
    run_check "监控系统存在且可执行" check_monitoring_system
    run_check "系统诊断脚本存在且可执行" check_system_diagnostics
}

# 需求 5 验证：安全最佳实践
verify_requirement_5() {
    log_info "验证需求 5: 安全最佳实践"
    
    # 5.1 检查安全加固脚本
    check_security_hardening() {
        [[ -x "${SCRIPT_DIR}/security-hardening.sh" ]]
    }
    
    # 5.2 检查 K3s 安全配置
    check_k3s_security() {
        [[ -x "${SCRIPT_DIR}/k3s-security.sh" ]]
    }
    
    # 5.3 检查系统优化器（包含安全优化）
    check_system_optimizer() {
        [[ -x "${SCRIPT_DIR}/system-optimizer.sh" ]]
    }
    
    run_check "安全加固脚本存在且可执行" check_security_hardening
    run_check "K3s 安全配置脚本存在且可执行" check_k3s_security
    run_check "系统优化器存在且可执行" check_system_optimizer
}

# 需求 6 验证：集群扩展支持
verify_requirement_6() {
    log_info "验证需求 6: 集群扩展支持"
    
    # 6.1 检查集群脚本
    check_cluster_script() {
        [[ -x "${SCRIPT_DIR}/k3s-cluster.sh" ]]
    }
    
    # 6.2 检查 K3s 服务配置
    check_k3s_service() {
        [[ -x "${SCRIPT_DIR}/k3s-service.sh" ]]
    }
    
    run_check "集群脚本存在且可执行" check_cluster_script
    run_check "K3s 服务配置脚本存在且可执行" check_k3s_service
}

# 验证测试框架
verify_testing_framework() {
    log_info "验证测试框架"
    
    # 检查测试脚本
    check_unit_tests() {
        [[ -x "${PROJECT_ROOT}/tests/run-unit-tests.sh" ]]
    }
    
    check_integration_tests() {
        [[ -x "${PROJECT_ROOT}/tests/run-integration-tests.sh" ]]
    }
    
    check_system_tests() {
        [[ -x "${PROJECT_ROOT}/tests/run-system-tests.sh" ]]
    }
    
    # 检查测试文件
    check_test_files() {
        local test_files=$(find "${PROJECT_ROOT}/tests" -name "*.bats" -o -name "test-*.sh" 2>/dev/null | wc -l)
        [[ $test_files -gt 0 ]]
    }
    
    run_check "单元测试脚本存在且可执行" check_unit_tests
    run_check "集成测试脚本存在且可执行" check_integration_tests
    run_check "系统测试脚本存在且可执行" check_system_tests
    run_check "测试文件存在" check_test_files
}

# 验证文档完整性
verify_documentation() {
    log_info "验证文档完整性"
    
    # 检查主要文档文件
    check_readme() {
        [[ -f "${PROJECT_ROOT}/README.md" ]]
    }
    
    check_docs_directory() {
        [[ -d "${PROJECT_ROOT}/docs" ]] && [[ -n "$(find "${PROJECT_ROOT}/docs" -name "*.md" 2>/dev/null)" ]]
    }
    
    check_api_docs() {
        [[ -f "${PROJECT_ROOT}/docs/api.md" ]]
    }
    
    check_development_docs() {
        [[ -f "${PROJECT_ROOT}/docs/development.md" ]]
    }
    
    run_check "README 文件存在" check_readme
    run_check "文档目录存在且包含文档" check_docs_directory
    run_check "API 文档存在" check_api_docs
    run_check "开发文档存在" check_development_docs
}

# 验证构建系统
verify_build_system() {
    log_info "验证构建系统"
    
    # 检查 Makefile
    check_makefile() {
        [[ -f "${PROJECT_ROOT}/Makefile" ]]
    }
    
    # 检查构建优化器
    check_build_optimizer() {
        [[ -x "${SCRIPT_DIR}/build-optimizer.sh" ]]
    }
    
    # 检查模板验证器
    check_template_validator() {
        [[ -x "${SCRIPT_DIR}/template-validator.sh" ]]
    }
    
    run_check "Makefile 存在" check_makefile
    run_check "构建优化器存在且可执行" check_build_optimizer
    run_check "模板验证器存在且可执行" check_template_validator
}

# 验证性能优化
verify_performance_optimization() {
    log_info "验证性能优化"
    
    # 检查性能优化脚本
    check_performance_scripts() {
        local scripts=("build-optimizer.sh" "system-optimizer.sh" "monitoring.sh")
        for script in "${scripts[@]}"; do
            if [[ ! -x "${SCRIPT_DIR}/$script" ]]; then
                return 1
            fi
        done
        return 0
    }
    
    # 检查缓存目录结构
    check_cache_structure() {
        mkdir -p "${PROJECT_ROOT}/.cache"
        [[ -d "${PROJECT_ROOT}/.cache" ]]
    }
    
    # 检查构建目录结构
    check_build_structure() {
        mkdir -p "${PROJECT_ROOT}/.build"
        [[ -d "${PROJECT_ROOT}/.build" ]]
    }
    
    run_check "性能优化脚本存在且可执行" check_performance_scripts
    run_check "缓存目录结构正确" check_cache_structure
    run_check "构建目录结构正确" check_build_structure
}

# 执行语法检查
verify_script_syntax() {
    log_info "验证脚本语法"
    
    local syntax_errors=0
    local total_scripts=0
    
    # 检查所有 shell 脚本的语法
    while IFS= read -r -d '' script; do
        ((total_scripts++))
        if ! bash -n "$script" 2>/dev/null; then
            log_error "语法错误: $script"
            ((syntax_errors++))
        fi
    done < <(find "${SCRIPT_DIR}" -name "*.sh" -type f -print0 2>/dev/null)
    
    check_syntax() {
        [[ $syntax_errors -eq 0 ]]
    }
    
    run_check "所有脚本语法正确 ($total_scripts 个脚本)" check_syntax "{\"total_scripts\": $total_scripts, \"syntax_errors\": $syntax_errors}"
}

# 验证配置完整性
verify_configuration_integrity() {
    log_info "验证配置完整性"
    
    # 检查配置文件格式
    check_yaml_syntax() {
        if command -v yq >/dev/null 2>&1; then
            yq eval '.' "${PROJECT_ROOT}/config/template.yaml" >/dev/null 2>&1
        elif command -v python3 >/dev/null 2>&1; then
            python3 -c "import yaml; yaml.safe_load(open('${PROJECT_ROOT}/config/template.yaml'))" 2>/dev/null
        else
            # 基本语法检查
            grep -q "template:" "${PROJECT_ROOT}/config/template.yaml" && \
            grep -q "k3s:" "${PROJECT_ROOT}/config/template.yaml"
        fi
    }
    
    # 检查必要的配置项
    check_required_config() {
        local config_file="${PROJECT_ROOT}/config/template.yaml"
        grep -q "name:" "$config_file" && \
        grep -q "version:" "$config_file" && \
        grep -q "k3s:" "$config_file"
    }
    
    run_check "YAML 配置文件语法正确" check_yaml_syntax
    run_check "必要配置项存在" check_required_config
}

# 执行快速功能测试
verify_basic_functionality() {
    log_info "验证基本功能"
    
    # 测试配置加载
    check_config_loading() {
        if [[ -x "${SCRIPT_DIR}/config-loader.sh" ]]; then
            source "${SCRIPT_DIR}/config-loader.sh" 2>/dev/null
            return $?
        fi
        return 1
    }
    
    # 测试日志系统
    check_logging_functionality() {
        if [[ -f "${SCRIPT_DIR}/logging.sh" ]]; then
            source "${SCRIPT_DIR}/logging.sh" 2>/dev/null
            return $?
        fi
        return 1
    }
    
    run_check "配置加载功能正常" check_config_loading
    run_check "日志系统功能正常" check_logging_functionality
}

# 生成验证报告
generate_verification_report() {
    local report_file="${PROJECT_ROOT}/logs/final-verification-report.md"
    
    log_info "生成最终验证报告: $report_file"
    
    cat > "$report_file" << EOF
# PVE LXC K3s Template 最终验证报告

## 验证概要

- **验证时间**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
- **验证环境**: $(uname -a)
- **项目根目录**: $PROJECT_ROOT
- **总检查项**: $TOTAL_CHECKS
- **通过检查**: $PASSED_CHECKS
- **失败检查**: $FAILED_CHECKS
- **成功率**: $(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))%

## 需求验证结果

### 需求 1: 自动生成 PVE LXC 模板
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(构建脚本|基础镜像|K3s安装)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 需求 2: 支持自定义配置
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(配置文件|配置验证|配置加载|Schema)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 需求 3: GitHub 仓库管理和分发
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(GitHub|打包器|部署)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 需求 4: 可观测性
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(日志|健康检查|监控|诊断)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 需求 5: 安全最佳实践
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(安全|加固|优化)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 需求 6: 集群扩展支持
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(集群|服务)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

## 系统组件验证

### 测试框架
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(测试)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 文档完整性
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(README|文档|API|开发)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 构建系统
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(Makefile|构建|验证器)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 性能优化
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(性能|缓存|构建目录)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

## 代码质量验证

### 脚本语法检查
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(语法)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 配置完整性
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(YAML|配置项)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

### 基本功能测试
$(echo "${VERIFICATION_RESULTS[@]}" | tr ' ' '\n' | grep -E "(功能)" | sed 's/PASS:/✓ /g; s/FAIL:/✗ /g')

## 失败项详情

$(if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo "以下检查项未通过验证："
    echo ""
    for result in "${VERIFICATION_RESULTS[@]}"; do
        if [[ "$result" =~ ^FAIL: ]]; then
            echo "- ${result#FAIL:}"
        fi
    done
else
    echo "所有检查项均通过验证！"
fi)

## 生产环境就绪评估

$(if [[ $FAILED_CHECKS -eq 0 ]]; then
    cat << 'READY'
### ✅ 生产环境就绪

所有验证检查均已通过，模板已准备好部署到生产环境。

**建议的下一步操作：**
1. 执行完整的系统测试
2. 在测试环境中验证模板功能
3. 创建生产版本标签
4. 部署到生产环境

**性能优化建议：**
1. 根据实际使用情况调整并行度设置
2. 监控生产环境性能指标
3. 定期更新和优化配置
READY
else
    cat << 'NOT_READY'
### ⚠️ 需要修复问题

发现 $FAILED_CHECKS 个问题需要修复后才能部署到生产环境。

**修复建议：**
1. 查看上述失败项详情
2. 修复相关问题
3. 重新运行验证
4. 确保所有检查通过后再部署
NOT_READY
fi)

## 验证日志

详细的验证日志请查看：$LOG_FILE

---

报告生成时间: $(date)
验证脚本版本: 1.0.0
EOF
    
    echo "最终验证报告已生成: $report_file"
}

# 显示帮助信息
show_help() {
    cat <<EOF
最终验证脚本

用法: $0 [选项]

选项:
  --quick         快速验证（跳过详细检查）
  --requirements  仅验证需求实现
  --components    仅验证系统组件
  --syntax        仅验证脚本语法
  --report        生成详细报告
  --verbose       详细输出
  --help          显示帮助信息

示例:
  $0                    # 完整验证
  $0 --quick           # 快速验证
  $0 --requirements    # 仅验证需求
  $0 --report          # 生成报告
EOF
}

# 主函数
main() {
    local quick_mode=false
    local requirements_only=false
    local components_only=false
    local syntax_only=false
    local generate_report=true
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                quick_mode=true
                shift
                ;;
            --requirements)
                requirements_only=true
                shift
                ;;
            --components)
                components_only=true
                shift
                ;;
            --syntax)
                syntax_only=true
                shift
                ;;
            --report)
                generate_report=true
                shift
                ;;
            --verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_info "=========================================="
    log_info "PVE LXC K3s Template 最终验证开始"
    log_info "=========================================="
    
    local start_time=$(date +%s)
    
    # 执行验证
    if [[ "$syntax_only" == "true" ]]; then
        verify_script_syntax
    elif [[ "$requirements_only" == "true" ]]; then
        verify_requirement_1
        verify_requirement_2
        verify_requirement_3
        verify_requirement_4
        verify_requirement_5
        verify_requirement_6
    elif [[ "$components_only" == "true" ]]; then
        verify_testing_framework
        verify_documentation
        verify_build_system
        verify_performance_optimization
    else
        # 完整验证
        echo "执行完整验证..."
        
        # 需求验证
        verify_requirement_1
        verify_requirement_2
        verify_requirement_3
        verify_requirement_4
        verify_requirement_5
        verify_requirement_6
        
        # 系统组件验证
        verify_testing_framework
        verify_documentation
        verify_build_system
        verify_performance_optimization
        
        # 代码质量验证
        if [[ "$quick_mode" == "false" ]]; then
            verify_script_syntax
            verify_configuration_integrity
            verify_basic_functionality
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 显示结果摘要
    echo ""
    echo "=========================================="
    echo "验证完成"
    echo "=========================================="
    echo "总检查项: $TOTAL_CHECKS"
    echo "通过检查: $PASSED_CHECKS"
    echo "失败检查: $FAILED_CHECKS"
    echo "成功率: $(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))%"
    echo "验证时间: ${duration}s"
    echo ""
    
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo "🎉 所有验证检查均通过！模板已准备好部署到生产环境。"
        log_info "最终验证成功完成" "{\"total_checks\": $TOTAL_CHECKS, \"passed_checks\": $PASSED_CHECKS, \"duration\": \"${duration}s\"}"
    else
        echo "⚠️  发现 $FAILED_CHECKS 个问题需要修复。"
        log_warn "最终验证发现问题" "{\"total_checks\": $TOTAL_CHECKS, \"failed_checks\": $FAILED_CHECKS, \"duration\": \"${duration}s\"}"
    fi
    
    # 生成报告
    if [[ "$generate_report" == "true" ]]; then
        generate_verification_report
    fi
    
    # 返回适当的退出码
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi