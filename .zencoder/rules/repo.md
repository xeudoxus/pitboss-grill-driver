---
description: Repository Information Overview
alwaysApply: true
---

# Pit Boss Grill Driver Information

## Summary
SmartThings Edge driver for Pit Boss WiFi Grills that uses reverse-engineered direct API communication without cloud dependency. Created by xeudoxus (version 1.0), this driver enables comprehensive control and monitoring of Pit Boss grills through the SmartThings platform.

## Structure
- **src/**: Core Lua driver implementation files
- **capabilities/**: Custom capability definitions for grill-specific features
- **profiles/**: Device profile configuration for SmartThings integration
- **.vscode/**: Editor configuration for development
- **.zencoder/**: Documentation and rules for the project

## Language & Runtime
**Language**: Lua
**Version**: Compatible with SmartThings Edge runtime
**Build System**: SmartThings Edge driver packaging
**Package Manager**: None (SmartThings Edge driver)

## Dependencies
**SmartThings Framework Dependencies**:
- st.capabilities
- st.driver
- st.json
- log

## Main Components
- **init.lua**: Main entry point with device lifecycle management
- **discovery.lua**: Network discovery implementation for finding grills
- **pitboss_api.lua**: API implementation for communicating with grills
- **device_manager.lua**: Device management and state handling
- **capability_handlers.lua**: Handlers for SmartThings capabilities
- **network_utils.lua**: Network communication utilities
- **custom_capabilities.lua**: Custom capability definitions

## Configuration
**Main Configuration**: config.yml
```yaml
name: 'Pit Boss Grill Driver'
packageKey: pitboss-grill-driver
version: "1.0.0"
```

**Device Profile**: profiles/pitboss-grill-profile.yml
```yaml
id: ed3e53a1-ef5e-4d7f-86fa-cd30da196025
name: pitboss-grill-profile
```

**Discovery Configuration**: discovery.json
```json
{
  "protocols": ["LAN"],
  "id": "pitboss-lan-discovery",
  "deviceLabel": "Pit Boss Grill"
}
```

## Features
- Power control and temperature monitoring
- Target temperature setting with thermostat control
- Up to 4 temperature probes (configurable)
- Pellet system status monitoring
- Interior light control
- Temperature unit switching (°F/°C)
- Calibration offsets for all temperature sensors

## Custom Capabilities
- **grillTemp**: Grill temperature monitoring
- **grillStatus**: Operational status information
- **temperatureProbes**: Multiple temperature probe readings
- **pelletStatus**: Pellet system monitoring
- **lightControl**: Interior light control
- **temperatureUnit**: Temperature unit selection (°F/°C)

## Device Integration
**Discovery Method**: LAN discovery using network scanning
**Communication**: Direct API communication over local network
**Connectivity**: Requires grill to be on same network as SmartThings hub
**Configuration Options**:
- Device IP address (manual or auto-discovery)
- Status update interval
- Temperature calibration offsets

## User Preferences
- IP Address configuration
- Status update interval (5-300 seconds)
- Temperature calibration offsets for grill and probes