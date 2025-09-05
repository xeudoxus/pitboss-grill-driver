# Pit Boss Grill SmartThings Edge Driver

![CI][ci]
[![GitHub Release][releases-shield]][releases]
[![License][license-shield]](LICENSE)
[![Luacheck][luacheck-shield]][luacheck]
[![GitHub Activity][commits-shield]][commits]
[![Issues][issues-shield]][issues]
[![Wiki][wiki-shield]][wiki]
[![SmartThings Edge][smartthings-shield]][smartthings-edge]
[![Model Compatibility][compatibility-shield]][compatibility]
![Project Maintenance][maintenance-shield]

A comprehensive SmartThings Edge driver for Pit Boss WiFi Grills that provides direct local network communication without cloud dependency. It implements time‑based authenticated encrypted RPC calls to the grill's controller, adaptive polling, safety panic detection, and an optional virtual device layer primarily for Google Home.

## 📚 Documentation

For detailed guides and troubleshooting, visit our [**Wiki**](https://github.com/xeudoxus/pitboss-grill-driver/wiki):

- 🚀 [**Installation Guide**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Installation-Guide) - Complete setup process
- 🏠 [**Google Home Setup**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Google-Home-Setup) - Voice control configuration
- 🔊 [**Alexa Setup**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Alexa-Setup) - Amazon Alexa integration guide
- ⚙️ [**Configuration Guide**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Configuration-Guide) - Advanced settings
- 🔧 [**Troubleshooting**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Troubleshooting) - Common issues and solutions
- 📋 [**Model Compatibility**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Model-Compatibility) - Supported grill models
- 🔬 [**Advanced Features**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Advanced-Features) - Technical details

## 🔥 Features

### Core Functionality

- **Direct Local Communication**: Communicates directly with your Pit Boss grill over your local network (no cloud dependency)
- **Approved Temperature Control**: Full thermostat functionality with automatic snapping to Pit Boss approved setpoints
- **Multi-Probe Support**: Monitor all 4 temperature probes in a unified display, with individual probe components for probes 1 & 2 (compatible with standard SmartThings automations)
- **Intelligent Status Tracking**: Rich states (Disconnected, PANIC, Connected (Preheating / Heating / At Temp / Cooling / Grill Off))
- **Dual Unit Support**: Fahrenheit / Celsius with automatic SmartThings locale handling
- **Pellet / Component Monitoring**: Pellet / auger / fan / ignitor state insight (used internally for power simulation)
- **Interior Light Control**: Remote control of grill interior lighting
- **Prime Function**: Pellet system priming with enforced 30s auto-off safety timeout
- **Power Monitoring**: Real-time simulated power estimation using measured component wattage
- **Safety Panic Detection**: Alerts if connection is lost shortly after active operation

### Smart Features

- **Automatic Discovery**: Network-based discovery & validation of Pit Boss grills
- **Optional Auto IP Rediscovery**: Controlled, rate-limited subnet scanning only when IP preference left at default (192.168.4.1) and feature enabled
- **Adaptive Health Monitoring**: Interval scales (preheating faster; off state 6× slower) + retry logic
- **Temperature Caching**: Maintains last-known values during transient packet loss (within cache timeout)
- **Steinhart-Hart Calibration**: Advanced non-linear temperature calibration using 32°F ice water reference
- **Virtual Device Layer**: Google Home compatible child devices for voice & granular automations
- **Error & Panic Detection**: Hardware error aggregation plus panic safety state
- **Continuous Passive Monitoring**: Low-frequency polling when grill off for rapid wake detection

### Virtual Devices (Optional)

_Note: Example voice commands assume you've renamed the virtual devices in Google Home for optimal recognition_
Create separate SmartThings devices primarily for **Google Home/Voice Assistant integration**:

- **Virtual Grill Main**: Core grill controls and temperature - _"Hey Google, turn off the grill"_ or _"Hey Google, what's the grill temp?"_
- **Virtual Grill Probe 1 & 2**: Individual temperature probe devices - _"Hey Google, what's the probe 1 temp?"_
- **Virtual Grill Probe 3 & 4**: Additional probe devices (if hardware supports) - _"Hey Google, what's the probe 3 temp?"_
- **Virtual Grill Light**: Dedicated light control device - _"Hey Google, turn on the Grill Light"_
- **Virtual Grill Prime**: Pellet priming control device - _"Hey Google, turn on the Grill Prime"_
- **Virtual Grill At-Temp**: Temperature target status indicator - _"Hey Google, is the grill At Temp on?"_
- **Virtual Grill Error**: Dedicated error and status reporting - _"Hey Google, is the grill error on?"_

> **💡 Pro Tip**: Some voice commands can be awkward. Create Google Home routines to make them more natural:
> **For example, you can create a routine so that instead of saying...**
>
> - _"Hey Google, turn on the Grill Prime switch"_
>
> **...you can just say:**
>
> - _"Hey Google, prime the grill."_
>
> **Here are other examples of simplified commands using routines:**
>
> - _"Hey Google, is the grill ready?"_
> - _"Hey Google, any grill errors?"_

**Important Google Home Notes:**

- Google Home **does not import** the main driver device due to its composite/custom capability set
- Virtual devices provide simplified, compatible capability sets
- Each device exposes a small set of "starter" capabilities Google accepts
- Without virtual devices Google Home voice control is not possible
- Virtual "At-Temp" switch turns on at ≥95% of target (session threshold)
- **⚠️ Safety Warning**: Do NOT configure virtual grill devices as general home thermostat devices. General thermostat commands (like "set thermostat to 72°") could accidentally trigger grill temperature changes, leading to dangerous situations.
- Other options for voice temperature control are being explored

Virtual devices also enable more granular SmartThings automations and dashboard organization. The main driver includes a unified probe display showing all 4 probes and provides standard SmartThings capabilities (like temperature sensors for grill temp and probes 1 & 2) which are available for automations and provide historical data through the SmartThings "history" dropdown with temperature graphs. Virtual devices duplicate some of these capabilities to provide dedicated Google Home voice control for the same sensors.

## 🚀 Quick Install

**Click this link to install the Pit Boss Grill Driver:**

[![Install Driver](https://img.shields.io/badge/SmartThings-Install%20Driver-blue?style=for-the-badge&logo=samsung)](https://bestow-regional.api.smartthings.com/invite/pbMv9qO9BGjO)

### Quick Setup Steps

1. Click the install link above
2. Sign in to your Samsung account if prompted
3. Select your SmartThings Hub
4. The driver will be installed automatically
5. Start device discovery in the SmartThings app to add your Pit Boss grill

## 🚀 Installation

> 📖 **For detailed step-by-step instructions, see the [Installation Guide](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Installation-Guide)**

### Installation Prerequisites

- SmartThings Hub with Edge driver support
- Pit Boss WiFi-enabled grill on the same LAN as your SmartThings Hub
- SmartThings mobile app or web interface
- **Firmware**: Grill firmware ≥ 0.5.7 (earlier versions untested / may fail auth)
- **Initial Setup Required**: For new/unconfigured grills, use official "Pit Boss Grills" app (Bluetooth provisioning) to set grill name/password + WiFi

### Installation Steps

1. **Initial Grill Configuration** (New Grills Only):
   - Download and use the official "Pit Boss Grills" mobile app
   - Connect your phone via Bluetooth to configure:
     - Grill name and password
     - WiFi network connection
   - Once connected to WiFi, the official app is no longer needed

2. **Install the Edge Driver**:
   - Add the driver channel to your SmartThings Hub
   - Install the "Pit Boss Grill Driver" from the channel

3. **Device Discovery**:
   - Start SmartThings device scan after grill joins WiFi
   - Driver performs targeted subnet scan & validation
   - If discovery fails, set IP manually (reserve DHCP in router recommended)

4. **Configuration**:
   - Set your preferred refresh interval (5-300 seconds)
   - Configure Steinhart-Hart temperature calibration using 32°F ice water reference method
   - **Enable virtual devices for Google Home integration** (highly recommended)
   - Rename virtual devices with "Grill" prefix for better voice recognition

## 🔧 Development & Building

### For Developers

This project uses a templating system to keep personal SmartThings identifiers out of version control while enabling easy building and deployment.

#### Development Prerequisites

- **SmartThings CLI**: Install and configure the SmartThings CLI (tested with @smartthings/cli/1.10.5)
- **Node.js**: Required for SmartThings CLI (tested with node-v18.5.0)
- **PowerShell**: Windows PowerShell 5.1 or PowerShell 7+ for cross-platform build script support

#### Developer Scripts

- **`test.ps1`** - Run test suite with filtering options and detailed output (supports both Python test infrastructure and Lua source code coverage)
- **`build.ps1`** - Build and deploy driver with templating system for personal configurations

### Initial Setup

1. **Copy the example configuration**:

   ```powershell
   Copy-Item "local-config.example.json" "local-config.json"
   ```

2. **Update your personal configuration** in `local-config.json`:
   ```json
   {
     "namespace": "your-namespace-here",
     "profileId": "your-profile-id-here",
     "presentationId": "your-presentation-id-here",
     "smartthings": {
       "channelId": "your-channel-id-here",
       "hubId": "your-hub-id-here"
     }
   }
   ```

### Build Script (build.ps1)

The `build.ps1` script handles the entire build and deployment process for the SmartThings Edge driver. It manages placeholder replacement, capability registration, packaging, deployment, and cleanup.

#### Command-Line Parameters

| Parameter             | Alias                                   | Description                                                                                   |
| --------------------- | --------------------------------------- | --------------------------------------------------------------------------------------------- |
| `-ConfigFile`         | `-c`                                    | Path to the configuration JSON file (default: "local-config.json")                            |
| `-PackageOnly`        | `-p`                                    | Only package the driver, skip deployment                                                      |
| `-UpdateCapabilities` | `-u`                                    | Create or update SmartThings capabilities and presentation (only needed once)                 |
| `-RemoveDriver`       | `-r`                                    | Remove driver from hub, unassign from channel, and delete all capabilities (complete cleanup) |
| `-ManualWork`         | `-m`                                    | Replace placeholders with real values, pause for manual work, then restore placeholders       |
| `-AutoRestore`        | `-a`, `-y`, `-NonInteractive`, `-Force` | Automatically restore dirty files to placeholder versions without prompting (CI-friendly)     |
| `-SmartVersion`       | `-s`                                    | Intelligently update versions for modified files based on Git changes                         |
| `-BumpAllVersions`    | `-b`                                    | Update all project files to today's version (major release)                                   |
| `-VersionOnly`        | `-o`                                    | Used with SmartVersion to only update versions without building or deploying                  |
| `-CheckVersions`      | `-k`                                    | Validate version consistency and readiness for release before building                        |
| `-Help`               | `-h`                                    | Show detailed help message                                                                    |
| `-Verbose`            | `-v`                                    | Show detailed output for placeholder/capability file changes                                  |

#### Common Usage Examples

```powershell
# Build and deploy with your personal config
.\build.ps1

# Smart build: update versions for modified files + build + deploy
.\build.ps1 -SmartVersion

# Build only (skip deployment)
.\build.ps1 -PackageOnly

# Check versions before building and packaging
.\build.ps1 -CheckVersions -PackageOnly

# Major release: bump all versions + build + deploy
.\build.ps1 -BumpAllVersions

# Test with example config (won't deploy due to placeholder IDs)
.\build.ps1 -ConfigFile "local-config.example.json"

# Create/update custom capabilities in SmartThings
.\build.ps1 -UpdateCapabilities

# Non-interactive CI-friendly build (auto-restore placeholders)
.\build.ps1 -PackageOnly -y

# Replace placeholders for manual editing, then restore when done
.\build.ps1 -ManualWork

# Complete driver removal and cleanup
.\build.ps1 -RemoveDriver

# Show detailed help
.\build.ps1 -Help
```

#### Build Process Phases

The script executes in several phases:

1. **Version Management** (optional): Updates file versions based on Git changes or user selection
2. **Placeholder Replacement**: Replaces `{{NAMESPACE}}`, `{{PROFILE_ID}}`, and `{{PRESENTATION_ID}}` with your personal values
3. **Capability File Renaming**: Renames capability files from placeholder format to your namespace
4. **Capability Registration** (optional): Creates or updates custom capabilities in SmartThings
5. **Driver Packaging**: Builds the SmartThings Edge driver package
6. **Deployment** (optional): Assigns the driver to your channel and installs it on your hub
7. **Restoration**: Restores all files to placeholder versions for clean version control

#### Safety Features

- **Dirty File Detection**: Identifies files with real values instead of placeholders
- **Auto-Restore**: Option to automatically clean up files from interrupted builds
- **Error Handling**: Graceful error recovery with file restoration
- **Backup**: Creates backups of all modified files before making changes

#### How It Works

- **Repository files** use placeholder values like `{{NAMESPACE}}` and `{{PROFILE_ID}}`
- **Build script** temporarily replaces placeholders with your real values
- **Packages and deploys** the driver to your SmartThings channel and hub
- **Restores placeholders** automatically for clean version control
- **Personal config** (`local-config.json`) is gitignored to protect your identifiers

This system ensures the repository stays clean while enabling personalized builds for each developer.

### Version Management

The project uses a smart version management system with CalVer (Calendar Versioning) format: `YYYY.M.D`

#### Version Management Quick Start

```powershell
# Smart version update (recommended) - detects modified files
.\build.ps1 -SmartVersion -VersionOnly

# Check versions before release
.\build.ps1 -CheckVersions

# Major release - bump all files to today's version
.\build.ps1 -BumpAllVersions
```

**VS Code Integration:** The project includes VS Code tasks for all version management and build operations. Access via `Ctrl+Shift+P` → "Tasks: Run Task":

- **PBG: Smart Version Update** - Intelligent version detection
- **PBG: Smart Build and Deploy** - Version management + build + deploy
- **PBG: Check Versions** - Validate before release

#### Integrated Build Commands

```powershell
# Smart build: update versions + build + deploy
.\build.ps1 -SmartVersion

# Safe build: check versions before building
.\build.ps1 -CheckVersions

# Major release build
.\build.ps1 -BumpAllVersions
```

#### How Version Management Works

- **`version.json`** - Master version file tracking all components
- **File-specific versioning** - Each file tracks its own last-modified version
- **Git integration** - Uses Git to detect modified files since last commit
- **Smart detection** - Only updates versions for files that actually changed
- **Safety checks** - Warns before releasing "today" versions

#### Version Workflow Examples

**Daily Development:**

```powershell
# 1. Make code changes and commit
git add -A && git commit -m "Fix temperature calibration"

# 2. Smart version update (only modified files get today's date)
.\build.ps1 -SmartVersion -VersionOnly

# 3. Test build
.\build.ps1 -PackageOnly

# 4. Check before release
.\build.ps1 -CheckVersions
```

**Major Release:**

```powershell
# 1. Bump all files to today's version
.\build.ps1 -BumpAllVersions

# 2. Build and deploy
.\build.ps1

# 3. Tag release
git tag "2025.9.2" && git push origin main --tags
```

#### Version Format

**CalVer: `YYYY.M.D`**

- `2025.9.2` = September 2, 2025
- `2025.9.2.1` = Second release on September 2, 2025 (if needed)

**Benefits:**

- ✅ Immediately shows release date
- ✅ No semantic versioning decisions needed
- ✅ Compatible with SmartThings platform
- ✅ Works with GitHub releases

#### Files Managed

- **Source files:** All `.lua` files in `src/`, all `.yml` files in `profiles/`
- **Config files:** `config.yml`, `package.json`, `build.ps1`, `README.md`
- **Special handling:** `init.lua` log message, profile version headers, README sync date

## 🧪 Testing

The project includes a comprehensive Python-based test suite that validates the Lua SmartThings Edge driver functionality.

### Test Infrastructure

- **Framework**: Python pytest with LuaTestBase for Lua module testing
- **Coverage**: Both Python test infrastructure and Lua source code coverage
- **Mocking**: Comprehensive mock system for SmartThings platform dependencies
- **Timer Safety**: Automatic thread mocking prevents test timeouts

### Running Tests

#### Testing Quick Start

```powershell
# Run all tests with coverage
.\test.ps1

# Run specific test file
.\test.ps1 -TestPath tests/test_temperature_calibration.py

# Run with Lua source code coverage
.\test.ps1 -LuaCoverage

# Run with both Python and Lua coverage
.\test.ps1 -LuaCoverage -HtmlReport
```

#### PowerShell Script Options

```powershell
# Run with detailed output
.\test.ps1 -DetailedOutput

# Generate HTML coverage report
.\test.ps1 -HtmlReport

# Generate XML report for CI/CD
.\test.ps1 -XmlReport

# Show help
.\test.ps1 -?
```

### Coverage Reporting

This test suite supports **dual coverage measurement**:

#### Python Coverage (Test Infrastructure)

- **Measured**: Python test files, base classes, and test utilities
- **Tool**: coverage.py
- **Purpose**: Validates test quality and infrastructure completeness

#### Lua Coverage (Source Code)

- **Measured**: Lua modules in `src/` executed via lupa runtime
- **Tool**: Custom Lua coverage module
- **Enable**: Use `-LuaCoverage` flag or set `LUA_COVERAGE=1`
- **Output**: JSON format saved to `lua_coverage.json`
- **Purpose**: Measures actual application code execution coverage

**Note**: Lua coverage requires the `LUA_COVERAGE=1` environment variable to be set or using the `-LuaCoverage` PowerShell flag.

### Test Structure

- **`tests/`**: Test files and infrastructure
- **`base_test_classes.py`**: Core LuaTestBase for Lua module testing
- **`mock_device.py`**: SmartThings device mock implementations
- **`device_situations.py`**: Predefined device states for testing
- **`tests/README.md`**: Detailed test development documentation

> 📖 **For detailed test development information, see [tests/README.md](tests/README.md)**

### Writing Tests

Tests use the `LuaTestBase` infrastructure:

```python
from base_test_classes import LuaTestBase

class TestModuleName(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        # Load Lua modules in dependency order
        dependencies = [
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

    def test_feature(self):
        """Test specific functionality."""
        # Test implementation
        pass
```

## ⚙️ Configuration

> 📖 **For comprehensive configuration details, see the [Configuration Guide](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Configuration-Guide)**

### Device Preferences

- **IP Address**: Manual IP configuration (auto-discovered by default if enabled)
- **Refresh Interval**: Status update frequency (5-300 seconds, default: 30)
- **Auto IP Rediscovery**: Optional / disabled by default. Only active when IP preference left at default (192.168.4.1). Performs an immediate scan when offline + 24h periodic scan. Use DHCP reservation instead when possible.
- **Temperature Calibration**: Steinhart-Hart calibration using 32°F ice water reference point
- **Virtual Device Options**: Enable/disable individual virtual devices (required for voice assistants)

### Voice Assistant Setup

> 📖 **For complete voice assistant integration instructions:**
>
> - [**Google Home Setup Guide**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Google-Home-Setup) - Recommended for best experience
> - [**Alexa Setup Guide**](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Alexa-Setup) - Limited functionality, see guide for details

**Quick Setup Steps:**

1. **Enable Virtual Devices**: Turn on desired virtual devices in driver preferences
2. **Sync Devices**: Google: _"Hey Google, sync devices"_ | Alexa: _"Alexa, discover devices"_
3. **Device Naming**: Rename devices with "Grill" prefix for better voice recognition
4. **Voice Commands**: Use natural language with device names (_"Hey Google/Alexa, turn on the Grill Light"_)

### Supported Temperature Setpoints

Pit Boss approved discrete setpoints (driver snaps requests to nearest valid value):

- **Fahrenheit**: 180, 200, 225, 250, 275, 300, 325, 350, 375, 400, 425, 450, 475, 500
- **Celsius**: 82, 93, 107, 121, 135, 148, 162, 176, 190, 204, 218, 232, 260

**Important**: When setting a target temperature, the driver will automatically snap to the closest approved temperature setpoint. For example, setting 240°F will snap to 250°F, and setting 235°F will snap to 225°F.

**Note**: SmartThings imposes a limitation where the temperature units (F/C) for standard capabilities are automatically dictated by your account's location. This overrides any unit selections made through the device's own interface, though the actual grill and any custom capabilities will still display the correct values.

## 🎯 Usage

### Basic Operations

- **Power Control**: Turn grill off via SmartThings
- **Temperature Setting**: Set target temperature using thermostat controls
- **Temperature Monitoring**: Real-time monitoring of grill and probe temperatures
- **Status Tracking**: Monitor grill status (Off, Preheating, Heating, Connected, Cooling)
- **Power Consumption**: View simulated power usage based on real-world measurements

### Advanced Features

- **Session Tracking**: Distinguishes preheating vs heating vs at‑temp vs cooling
- **Automatic Session Reset**: Triggered on ≥50°F / 28°C target change or power cycle
- **Panic Safety State**: Immediate high-priority status if connectivity lost while recently active (≤5 min)
- **Error Monitoring**: Aggregated hardware error flags + message priority system
- **Adaptive Connectivity**: Reconnect logic with cached auth & fallback tokens
- **Continuous Monitoring**: Reduced interval polling when grill off for rapid wake detection

### Voice Assistant Integration

- **Google Home**: _"Hey Google, turn off the grill"_, _"What's the grill temperature?"_, _"Turn on the Grill Light"_
- **Amazon Alexa**: _"Alexa, turn on the grill light"_, _"Alexa, turn off the grill"_ (tested - see [Alexa Setup Guide](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Alexa-Setup))
- **Bixby**: Full Samsung ecosystem integration (untested - by assumption)
- **Enhanced Control**: Virtual devices provide granular voice commands for individual components

**Voice Assistant Compatibility:**

- **Main device won't import** into Google Home or Alexa → rely on virtual devices
- **Virtual devices work** in both Google Home and Alexa with limitations
- **Google Home**: Full temperature monitoring support, full switch control
- **Alexa**: Full probe temperature monitoring (visual + voice), main grill temp unavailable (switch only), no routine triggers
- Use consistent "Grill" prefix for better voice recognition

### SmartThings Integration

- **Automations**: Use grill status in SmartThings routines and automations
- **Notifications**: Get alerts for temperature targets, errors, or status changes
- **Dashboard**: Monitor all grill functions from SmartThings dashboard

## 🔧 Technical Details

> 📖 **For in-depth technical information, see the [Advanced Features Guide](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Advanced-Features)**

### Architecture

- **Language**: Lua (SmartThings Edge runtime)
- **Communication**: Direct HTTP API communication with grill
- **Discovery**: Network scanning with automatic IP detection and updates
- **Caching**: Intelligent temperature caching with 2x refresh interval timeout
- **Error Handling**: Comprehensive retry logic and graceful degradation
- **Power Simulation**: Based on real watt meter measurements from PB1285KC model

### Network Requirements

- Grill & Hub must share same Layer 2 network / VLAN
- Standard HTTP (port 80) – no port forwarding required
- Optional controlled rediscovery (when enabled & default IP configured)
- Best practice: DHCP reservation instead of relying on rediscovery

### Performance Optimizations

- **Efficient Status Calls**: Single network request updates all virtual devices
- **Adaptive Monitoring**: Adjusts polling frequency based on grill state (50% faster during preheating, 6x slower when off)
- **Smart Caching**: Reduces network traffic during brief connectivity issues
- **Batch Updates**: Centralized device state management

## 🛠️ Troubleshooting

> 📖 **For comprehensive troubleshooting steps, see the [Troubleshooting Guide](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Troubleshooting)**

### Common Issues (Selected)

1. **Device Not Discovered**:
   - Ensure grill is WiFi-connected (use Pit Boss Grills app for initial setup)
   - Verify grill and hub are on same network
   - Manually configure IP address in device preferences
   - Check grill WiFi connection status:
     - 🔁 **Flashing "iT" icon** → Trying to connect to WiFi
     - ⚫ **Off "iT" icon** → Could not connect; will retry later
     - 🟢 **Solid "iT" icon** → Connected to WiFi

2. **Connection Issues**:
   - Verify grill compatibility & firmware (≥0.5.7)
   - Confirm IP reachable (ping / HTTP Sys.GetInfo)
   - Reserve IP in router
   - Enable Auto IP Rediscovery only if necessary (and IP pref left default)
   - Review hub logs for repeated auth failures (may indicate outdated firmware)

3. **Temperature Reading Issues**:
   - Calibrate using Steinhart-Hart method with 32°F ice water reference (see Configuration Guide)
   - Ensure probe connections are secure
   - Check for "Disconnected" probe status
   - Remember that SmartThings forces temperature units based on location settings

### Debug Information

- Enable debug logging in SmartThings IDE
- Check device field values for troubleshooting
- Monitor network connectivity status

## 📋 Supported Models

> 📖 **For detailed compatibility information, see the [Model Compatibility Guide](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Model-Compatibility)**

This driver is designed for Pit Boss WiFi-enabled grills and has been **developed and tested on**:

- **Pit Boss PB1285KC (KC Combo) Grill/Smoker** - _Fully tested and confirmed_

**Potentially Compatible Models (Unconfirmed / User Reports Wanted):**
The following models are expected to work based on similar control panel designs and WiFi capabilities, but have not been tested:

- **PB440 Series**: PB440D3, PB440D, PB440T
- **PB450 Series**: PB450D, PB450T, PB450D3, PB456D3
- **PB500 Series**: PB500T
- **PB550 Series**: PB550G
- **PB700 Series**: PB700D, PB700T, PB700D3, PB700
- **PB750 Series**: PB750G, PB750T
- **PB820 Series**: PB820FB, PB820FBC, PB820D3, PB820D, PB820T, PB820, PB820SC, PB820PS
- **PB850 Series**: PB850G, PB850T, PB850CS, PB850CS3
- **PB1000 Series**: PB1000T3, PB1000SC3, PB1000, PB1000T, PB1000D, PB1000SP, PB1000D3, PB1000T2, PB1000T1, PB1000FBC, PB1000SCS, PB1000SC
- **PB1150 Series**: PB1150GS
- **PB1230 Series**: PB1230CSP, PB1230CS
- **PB1250 Series**: PB1250
- **PB1270 Series**: PB1270
- **PB1285 Series**: PB1285CS
- **PBV Series**: PBV2, PBV3

**Compatibility Requirements:**

- WiFi-enabled Pit Boss grill
- Temperature probe support
- Compatible control panel (similar to PB1285KC)
- Network connectivity features

**Compatibility Notes:**

- Models with similar control panels are most likely to be compatible
- Grills must have WiFi capability and network API access
- When additional models are confirmed through user testing, they will be moved to the confirmed list
- **Please report compatibility results** to help expand the confirmed models list

_Note: This is an unofficial third-party driver. See Legal Disclaimer section below for complete trademark and liability information._

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

### Development Setup

1. Clone the repository
2. Review the code structure in the `src/` directory
3. Test changes with a compatible Pit Boss grill
4. Submit pull requests with detailed descriptions

### Model Compatibility Testing

If you successfully test this driver with other Pit Boss models, please submit an issue with:

- Model number and name
- Test results and any issues encountered
- Control panel photos if different from PB1285KC

See the [Model Compatibility Guide](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Model-Compatibility) for current testing status and compatibility requirements.

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## ⚠️ Legal Disclaimer & Trademarks

### Third-Party Software Notice

This is an **unofficial, third-party driver** developed independently and is **not endorsed, sponsored, or affiliated** with Pit Boss, Dansons Inc., or any of their subsidiaries or partners.

### Trademark Acknowledgments

- **Pit Boss®** and the "iT" logo are registered trademarks of Dansons Inc.
- **SmartThings®** and **Samsung®** are registered trademarks of Samsung Electronics Co., Ltd.
- **Google Home®** and **Google Assistant®** are registered trademarks of Google LLC
- All product names, logos, and brands mentioned in this documentation are property of their respective owners

### License Clarification

Released under Apache 2.0 (see LICENSE). No additional usage restrictions are imposed beyond the license; trademarks remain property of their owners. You must not imply endorsement by any trademark holder.

### Warranty Disclaimer

**USE AT YOUR OWN RISK.** This software is provided "AS IS" without warranty of any kind, express or implied. The author disclaims all warranties, including but not limited to:

- Merchantability and fitness for a particular purpose
- Non-infringement of third-party rights
- Compatibility with your specific grill model
- Safety or reliability of operation

### Safety Notice

**Always follow proper grill safety procedures and manufacturer guidelines.** The author is not responsible for any damage, injury, or loss resulting from the use of this software. Users assume all risks associated with operating grilling equipment.

### Reverse Engineering Notice

Developed via lawful interoperability analysis (network traffic + publicly exposed web resources). Implementation is original; no proprietary source was copied.

## 🙏 Acknowledgments

- Created by: xeudoxus
- Version: 2025.9.2 (Documentation last synced: 2025-09-02)
- Developed and tested on: Pit Boss PB1285KC (KC Combo)
- SmartThings Edge platform
- Pit Boss grill reverse engineering community

---

**For support, issues, or feature requests:**

- 📚 Check the [Wiki](https://github.com/xeudoxus/pitboss-grill-driver/wiki/Home) for detailed guides and troubleshooting
- 🐛 Use the GitHub Issues section for bug reports
- 💡 Use GitHub Discussions for questions and feature requests

<!-- Badge Links -->

[smartthings-shield]: https://img.shields.io/badge/SmartThings-Edge%20Driver-blue.svg?style=for-the-badge&logo=samsung
[smartthings-edge]: https://developer.smartthings.com/edge-device-drivers
[maintenance-shield]: https://img.shields.io/badge/maintainer-xeudoxus-blue.svg?style=for-the-badge
[releases-shield]: https://img.shields.io/github/release/xeudoxus/pitboss-grill-driver.svg?style=for-the-badge
[releases]: https://github.com/xeudoxus/pitboss-grill-driver/releases
[commits-shield]: https://img.shields.io/github/commit-activity/y/xeudoxus/pitboss-grill-driver.svg?style=for-the-badge
[commits]: https://github.com/xeudoxus/pitboss-grill-driver/commits/main
[license-shield]: https://img.shields.io/github/license/xeudoxus/pitboss-grill-driver.svg?style=for-the-badge
[luacheck-shield]: https://img.shields.io/github/actions/workflow/status/xeudoxus/pitboss-grill-driver/luacheck.yml?style=for-the-badge
[luacheck]: https://github.com/xeudoxus/pitboss-grill-driver/actions/workflows/luacheck.yml?query=branch%3Amain
[issues-shield]: https://img.shields.io/github/issues/xeudoxus/pitboss-grill-driver.svg?style=for-the-badge
[issues]: https://github.com/xeudoxus/pitboss-grill-driver/issues
[wiki-shield]: https://img.shields.io/badge/documentation-wiki-brightgreen.svg?style=for-the-badge
[wiki]: https://github.com/xeudoxus/pitboss-grill-driver/wiki
[compatibility-shield]: https://img.shields.io/badge/tested-PB1285KC-success.svg?style=for-the-badge
[compatibility]: https://github.com/xeudoxus/pitboss-grill-driver/wiki/Model-Compatibility
[ci]: https://img.shields.io/github/actions/workflow/status/xeudoxus/pitboss-grill-driver/ci.yml?style=for-the-badge
