# Pull Request

## Description

<!-- Provide a brief description of the changes in this PR -->

## Type of Change

<!-- Mark the relevant option with an "x" -->

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring
- [ ] Security enhancement
- [ ] Dependency update
- [ ] CI/CD improvement

## Related Issues

<!-- Link to related issues using "Fixes #123" or "Closes #123" -->

- Fixes #
- Related to #

## Changes Made

<!-- Describe the specific changes made in this PR -->

### Configuration Changes
- [ ] Updated template configuration
- [ ] Modified K3s settings
- [ ] Changed security settings
- [ ] Updated build parameters

### Script Changes
- [ ] Modified build scripts
- [ ] Updated installation scripts
- [ ] Changed security hardening
- [ ] Updated validation scripts

### Documentation Changes
- [ ] Updated README
- [ ] Modified documentation files
- [ ] Added/updated comments
- [ ] Updated changelog

## Testing

<!-- Describe the testing performed -->

### Test Environment
- **Proxmox VE Version**: 
- **Host OS**: 
- **Test Container Config**: 

### Tests Performed
- [ ] Template builds successfully
- [ ] Container creates from template
- [ ] K3s starts automatically
- [ ] K3s API is accessible
- [ ] Basic pod deployment works
- [ ] Network connectivity verified
- [ ] Security settings applied
- [ ] Multi-node cluster (if applicable)

### Test Results
<!-- Provide details about test results -->

```bash
# Example test commands and output
pct create 999 local:vztmpl/test-template.tar.gz --memory 2048 --cores 2
pct start 999
pct exec 999 -- k3s kubectl get nodes
```

## Security Considerations

<!-- Address any security implications -->

- [ ] No new security vulnerabilities introduced
- [ ] Security hardening maintained
- [ ] Firewall rules updated if needed
- [ ] User permissions reviewed
- [ ] Dependencies scanned for vulnerabilities

## Performance Impact

<!-- Describe any performance implications -->

- [ ] No performance degradation
- [ ] Template size impact: 
- [ ] Build time impact: 
- [ ] Runtime performance: 

## Breaking Changes

<!-- List any breaking changes and migration steps -->

- [ ] No breaking changes
- [ ] Configuration format changes
- [ ] API changes
- [ ] Behavior changes

### Migration Steps
<!-- If there are breaking changes, provide migration steps -->

1. 
2. 
3. 

## Checklist

<!-- Ensure all items are completed before submitting -->

### Code Quality
- [ ] Code follows project style guidelines
- [ ] Self-review of code completed
- [ ] Code is properly commented
- [ ] No debugging code left in
- [ ] Error handling is appropriate

### Testing
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Manual testing completed
- [ ] Edge cases considered and tested

### Documentation
- [ ] Documentation updated for changes
- [ ] README updated if needed
- [ ] Changelog updated
- [ ] Comments added for complex logic

### Security
- [ ] Security implications reviewed
- [ ] No sensitive information exposed
- [ ] Dependencies are secure
- [ ] Permissions are appropriate

### Compatibility
- [ ] Backward compatibility maintained
- [ ] Proxmox VE compatibility verified
- [ ] K3s version compatibility checked
- [ ] Alpine Linux compatibility verified

## Additional Notes

<!-- Any additional information for reviewers -->

### Review Focus Areas
<!-- Highlight specific areas that need careful review -->

- 
- 
- 

### Known Issues
<!-- List any known issues or limitations -->

- 
- 
- 

### Future Improvements
<!-- Suggest future improvements or follow-up work -->

- 
- 
- 

---

## For Maintainers

### Review Checklist
- [ ] Code review completed
- [ ] Security review completed
- [ ] Performance impact assessed
- [ ] Documentation review completed
- [ ] Test coverage adequate
- [ ] CI/CD pipeline passes

### Deployment Notes
- [ ] Safe to deploy immediately
- [ ] Requires staged deployment
- [ ] Requires announcement
- [ ] Requires documentation update

<!-- 
Thank you for contributing to the PVE LXC K3s Template project!
Please ensure all sections are completed before submitting your PR.
-->