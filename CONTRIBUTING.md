# Contributing to Pit Boss Grill SmartThings Edge Driver

Thank you for your interest in contributing! This project welcomes contributions from the community.

## 🚀 Quick Start

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/pitboss-grill-driver.git`
3. **Create** a feature branch: `git checkout -b feature/your-feature-name`
4. **Test** your changes: `.\test.ps1`
5. **Submit** a pull request

## 🧪 Development Setup

### Prerequisites
- Python 3.11+ with pip
- PowerShell 5.1+ (for build scripts)
- SmartThings CLI (for deployment)
- Access to a compatible Pit Boss grill (for testing)

### Local Development
```powershell
# Clone and setup
git clone https://github.com/xeudoxus/pitboss-grill-driver.git
cd pitboss-grill-driver

# Setup virtual environment
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Copy example config
cp local-config.example.json local-config.json
# Edit local-config.json with your personal IDs

# Run tests (choose one method)
.\test.ps1                    # Command line with coverage
# OR use VS Code Test Explorer (recommended for development)
# 1. Open Command Palette (Ctrl+Shift+P)
# 2. "Python: Configure Tests" → select unittest
# 3. Use Test Explorer panel for interactive testing

# Build package
.\build.ps1 -PackageOnly
```

## 📝 Contribution Guidelines

### Code Standards
- **Lua Code**: Follow SmartThings Edge driver conventions
- **Python Tests**: Use pytest with clear test names
- **Documentation**: Update wiki for user-facing changes
- **Commit Messages**: Use conventional commits format

### Testing Requirements
- All new features must include tests
- Tests must pass: `.\test.ps1` or use VS Code's built-in Test Explorer (Python testing with unittest/pytest)
- Lua code coverage should be maintained
- Manual testing on actual hardware when possible

### Pull Request Process
1. **Update documentation** for user-facing changes
2. **Add tests** for new functionality
3. **Ensure CI passes** (all GitHub Actions workflows)
4. **Link issues** if fixing bugs
5. **Request review** from maintainers

## 🐛 Bug Reports

Use the [GitHub Issues](https://github.com/xeudoxus/pitboss-grill-driver/issues) template:

**For Driver Issues:**
- Grill model and firmware version
- SmartThings hub details
- Error logs from SmartThings CLI
- Steps to reproduce

**For Documentation Issues:**
- Page or section with problem
- Expected vs actual content
- Suggested improvements

## 💡 Feature Requests

Before submitting:
1. **Search existing issues** for similar requests
2. **Check compatibility** with SmartThings Edge platform
3. **Consider scope** - focus on Pit Boss grill functionality

## 🏗️ Architecture Overview

### Core Components
- **`src/init.lua`**: Main driver entry point
- **`src/pitboss_api.lua`**: Grill communication protocol
- **`src/custom_capabilities.lua`**: SmartThings capability definitions
- **`tests/`**: Comprehensive Python-based test suite

### Build System
- **`build.ps1`**: Build and deployment automation
- **`test.ps1`**: Test runner with coverage
- **`.github/workflows/`**: CI/CD automation

## 🤝 Community

- **Be respectful** and inclusive
- **Help others** in issues and discussions
- **Share knowledge** about compatible models
- **Test thoroughly** before submitting changes

## 📄 License

By contributing, you agree that your contributions will be licensed under the same [Apache License 2.0](LICENSE) as the project.

## 🙏 Recognition

Contributors will be acknowledged in:
- Release notes for significant contributions
- README credits section
- GitHub contributor graphs

Thank you for helping make this driver better for the community!