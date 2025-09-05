# SmartThings Edge Driver Test Suite

This directory contains the comprehensive Python-based test suite for the Pit Boss Grill SmartThings Edge driver. The test suite uses a modern infrastructure built around `LuaTestBase` to provide reliable, maintainable testing of Lua modules from Python.

## 🏗️ Test Infrastructure Overview

### LuaTestBase Architecture

All tests inherit from `LuaTestBase` which provides:

- **Standardized Lua Runtime**: Consistent lupa Lua runtime setup with tuple handling
- **Dependency Management**: Automated loading of mocks and real modules in correct order
- **Timer Mocking**: Automatic thread mock injection to prevent real timers and test timeouts
- **Module Loading**: Robust Lua module loading with fallback handling for modules that return tuples

### Key Components

- **`base_test_classes.py`**: Core `LuaTestBase` class and specialized test bases
- **`mock_device.py`**: Mock SmartThings device implementations
- **`device_situations.py`**: Predefined device states for testing
- **`tests/mocks/`**: Lua mock modules for platform dependencies

## 📁 Test File Structure

### Naming Convention

- `test_*.py`: Individual test files for specific modules
- `test_*_service.py`: Tests for service modules
- `test_*_manager.py`: Tests for manager modules

### Test Class Structure

```python
from base_test_classes import LuaTestBase

class TestModuleName(LuaTestBase):
    """Test description for module_name module."""

    @classmethod
    def _load_modules(cls):
        # Load dependencies in topological order
        dependencies = [
            'package.loaded["cosock"] = dofile("tests/mocks/cosock.lua")',
            'package.loaded["config"] = dofile("src/config.lua")',
            # ... more dependencies
        ]
        for dep in dependencies:
            cls.lua.execute(dep)

        # Load target module
        result = cls.lua.eval('require("module_name")')
        if isinstance(result, tuple):
            cls.module_name = result[0]
        else:
            cls.module_name = result

    def test_feature_name(self):
        """Test that feature works correctly."""
        # Test implementation
        pass
```

## 🔧 Module Loading & Dependencies

### Dependency Order

Modules must be loaded in topological order to satisfy dependencies:

1. **Core Mocks**: `cosock`, `dkjson`, `st.*` modules
2. **Configuration**: `config`, `custom_capabilities`
3. **Utilities**: `temperature_calibration`, `network_utils`
4. **Services**: `temperature_service`, `device_status_service`
5. **Managers**: `device_manager`, `virtual_device_manager`
6. **Main Modules**: `capability_handlers`, `command_service`

### Tuple Handling

Some Lua modules return multiple values as tuples. The infrastructure handles this automatically:

```python
# This pattern is used throughout the codebase
result = cls.lua.eval('require("module_name")')
if isinstance(result, tuple):
    cls.module_name = result[0]  # Take first element
else:
    cls.module_name = result
```

## 🎭 Mock Infrastructure

### Available Mocks

- **`tests/mocks/cosock.lua`**: Deterministic socket behavior
- **`tests/mocks/dkjson.lua`**: JSON encode/decode for testing
- **`tests/mocks/st/*.lua`**: SmartThings platform mocks
- **`tests/mocks/log.lua`**: Logging mock
- **`tests/mocks/bit32.lua`**: Bit operations mock

### Timer Mocking

All tests automatically inject thread mocks to prevent real timers:

```python
# This happens automatically in LuaTestBase.setUpClass()
def mock_thread_function(*args, **kwargs):
    return None  # Prevent real timer execution
```

## 🧪 Writing Tests

### Test Method Naming

```python
def test_descriptive_name(self):
    """Test that specific functionality works correctly."""
    # Arrange
    # Act
    # Assert
    pass

def test_edge_case_handling(self):
    """Test how the module handles edge cases."""
    pass
```

### Device Mocking

Use the mock device infrastructure for tests requiring device interaction:

```python
def setUp(self):
    self.device = self.lua.eval('require("tests.mocks.st.driver")()')
    self.device.preferences = self.lua.table_from({'key': 'value'})
    self.device.profile = self.lua.table_from({'components': {}})
```

### Event Tracking

For tests that need to verify events are emitted:

```python
def setUp(self):
    self.emitted_events = []
    def emit_event(dev, event):
        self.emitted_events.append(event)
    self.device.emit_event = emit_event
```

## 📊 Coverage Reporting

### Coverage Types

This test suite supports **dual coverage measurement**:

#### Python Coverage (Test Infrastructure)

- ✅ **Measured**: Python test files, base classes, and test utilities in `tests/`
- 🛠️ **Tool**: coverage.py
- 📊 **Purpose**: Measures test quality and infrastructure coverage

#### Lua Coverage (Source Code)

- ✅ **Measured**: Lua modules in `src/` executed via lupa runtime
- 🛠️ **Tool**: Custom Lua coverage module (`lua_coverage.lua`)
- 📊 **Purpose**: Measures actual application code execution
- ⚙️ **Enable**: Set `LUA_COVERAGE=1` environment variable or use `-LuaCoverage` flag

### Generating Coverage

#### Python Coverage Only

```bash
# Run tests with Python coverage
coverage run -m pytest tests/ -v
coverage report --show-missing
coverage html  # Optional: generate HTML report
```

#### Lua Coverage Only

```bash
# Run tests with Lua coverage
LUA_COVERAGE=1 python -m pytest tests/ -v
# Lua coverage data saved to lua_coverage.json
```

#### Both Python and Lua Coverage

```bash
# Using PowerShell script (recommended)
.\test.ps1 -LuaCoverage

# Or manually
LUA_COVERAGE=1 coverage run -m pytest tests/ -v
coverage report --show-missing
# Check lua_coverage.json for Lua coverage data
```

### Coverage Goals

- **Test Infrastructure**: Ensure test setup code is properly covered
- **Application Code**: Measure execution of Lua source modules
- **Test Quality**: High coverage indicates well-structured tests
- **Maintenance**: Identify unused code and dead paths

### Interpreting Coverage

#### Python Coverage

- **tests/ files**: Python test infrastructure coverage
- \***\*init**.py\*\*: Often 0% coverage (only executed when package imported)
- **Focus**: Use to improve test quality and catch dead test code

#### Lua Coverage

- **src/ files**: Lua application code execution coverage
- **Format**: JSON output with file-by-file line execution counts
- **Focus**: Measures which parts of your Lua application are actually tested
- **Note**: Only tracks files in `src/` directory containing executable code

## 🚀 Running Tests

### Quick Test Run

```bash
# Run all tests
python -m pytest tests/ -v

# Run specific test file
python -m pytest tests/test_temperature_calibration.py -v

# Run with coverage
coverage run -m pytest tests/ -v
coverage report
```

### PowerShell Runner

```powershell
# Using the bundled PowerShell script
.\test.ps1

# Or explicitly
pwsh -NoProfile -Command ".\test.ps1"
```

#### PowerShell Script Options

```powershell
# Run all tests with coverage (default)
.\test.ps1

# Run specific test file
.\test.ps1 -TestPath tests/test_temperature_calibration.py

# Run with detailed output
.\test.ps1 -DetailedOutput

# Run fast without coverage
.\test.ps1 -NoCoverage

# Generate HTML coverage report
.\test.ps1 -HtmlReport

# Generate XML report for CI/CD
.\test.ps1 -XmlReport

# Show help
.\test.ps1 -?
```

### IDE Integration

Most Python IDEs (VS Code, PyCharm) can run pytest directly:

- Right-click on test file or directory
- Select "Run Tests" or "Debug Tests"
- Coverage can be integrated with IDE extensions

## 🔄 Migration from Old Tests

### Old vs New Approach

| Aspect          | Old (unittest.TestCase)     | New (LuaTestBase)                |
| --------------- | --------------------------- | -------------------------------- |
| Setup           | Manual LuaRuntime creation  | Automatic via LuaTestBase        |
| Dependencies    | Manual loading in each test | Centralized \_load_modules()     |
| Timer Handling  | Real timers caused timeouts | Automatic thread mocking         |
| Mock Management | Inconsistent approaches     | Standardized mock infrastructure |
| Maintenance     | High duplication            | DRY with inheritance             |

### Migration Steps

1. ✅ **Completed**: Convert class definition to inherit from LuaTestBase
2. ✅ **Completed**: Replace manual LuaRuntime setup with \_load_modules()
3. ✅ **Completed**: Add timer mocking infrastructure
4. ✅ **Completed**: Standardize module loading patterns
5. ✅ **Completed**: Update import statements and test structure

## 📋 Best Practices

### Test Organization

- Keep test methods focused on single functionality
- Use descriptive names that explain what is being tested
- Group related tests in the same class
- Use setUp() for common test initialization

### Mock Usage

- Only mock external dependencies, not core driver code
- Document why a mock is necessary
- Keep mocks minimal and focused
- Prefer real implementations over mocks when possible

### Assertions

- Use specific assertions (`assertEqual`, `assertTrue`, etc.)
- Provide descriptive failure messages
- Test both positive and negative cases
- Verify edge cases and error conditions

### Performance

- Tests should run quickly (< 100ms per test)
- Avoid unnecessary setup in individual test methods
- Use class-level setup for expensive operations
- Clean up resources in tearDown() if needed

## 🐛 Debugging Tests

### Common Issues

- **Import Errors**: Check module loading order in \_load_modules()
- **Timer Timeouts**: Verify thread mocking is active
- **Lua Errors**: Check Lua stack traces in test output
- **Mock Issues**: Ensure mocks are loaded before modules that use them

### Debugging Tools

```python
# Add debug prints in Lua
cls.lua.execute('print("Debug message")')

# Inspect Lua tables
result = cls.lua.eval('module_name')
print(f"Module type: {type(result)}")

# Check package.loaded
loaded = cls.lua.eval('package.loaded')
print(f"Loaded modules: {loaded.keys()}")
```

## 🤝 Contributing

### Adding New Tests

1. Create `test_new_module.py` following the established pattern
2. Inherit from `LuaTestBase` or appropriate specialized base
3. Implement `_load_modules()` with proper dependency order
4. Add comprehensive test methods
5. Run tests with coverage to ensure adequate coverage

### Adding New Mocks

1. Place mock in `tests/mocks/` directory
2. Document the mock's purpose and usage
3. Update this README if it's a commonly used mock
4. Ensure mock doesn't break existing tests

### Code Review Checklist

- [ ] Tests inherit from appropriate base class
- [ ] Module dependencies loaded in correct order
- [ ] Timer mocking implemented
- [ ] Test methods have descriptive names and docstrings
- [ ] Edge cases and error conditions tested
- [ ] Coverage maintained or improved
- [ ] No unnecessary mocking of core modules

---

## 📚 Additional Resources

- [pytest Documentation](https://docs.pytest.org/)
- [lupa Lua-Python Bridge](https://lupa.readthedocs.io/)
- [Coverage.py Documentation](https://coverage.readthedocs.io/)
- [SmartThings Edge Driver Documentation](https://developer.smartthings.com/docs/edge-device-drivers/)

---

## Test Infrastructure

Test infrastructure maintained by the development team. Last updated: August 27, 2025
