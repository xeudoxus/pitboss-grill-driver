--[[
  Custom Capabilities for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module defines and manages all custom SmartThings capabilities required for
  comprehensive Pit Boss grill functionality. These capabilities extend beyond standard
  SmartThings capabilities to provide grill-specific features and controls.

  Custom Capabilities Overview:
  - grillTemp: Temperature display and target setting with precision control
  - temperatureProbes: Unified display for all 4 temperature probes with intelligent formatting
  - pelletStatus: Pellet level monitoring and feed system status reporting
  - lightControl: Grill light control with status feedback
  - temperatureUnit: Fahrenheit/Celsius unit selection and conversion
  - grillStatus: Comprehensive status messaging and error reporting

  Implementation Notes:
  - All capabilities use the "{{NAMESPACE}}" namespace for consistency
  - Capabilities are designed for optimal SmartThings app integration
  - Each capability supports both command and status reporting functionality
  - Error handling and validation are built into capability implementations

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local capabilities = require("st.capabilities")

-- ============================================================================
-- CUSTOM CAPABILITY DEFINITIONS
-- ============================================================================

--- Custom capabilities container for Pit Boss Grill functionality
-- All capabilities use consistent namespace and provide comprehensive grill control
local customCapabilities = {}

-- Temperature control and display capability
-- Provides precise temperature setting with approved setpoint snapping and
-- comprehensive temperature display with offset support
customCapabilities.grillTemp = capabilities["{{NAMESPACE}}.grillTemp"]

-- Unified probe temperature monitoring capability
-- Enables monitoring of all 4 food probes with unified display formatting,
-- individual components for probes 1&2, and automatic layout detection
customCapabilities.temperatureProbes = capabilities["{{NAMESPACE}}.temperatureProbes"]

-- Pellet system status and monitoring capability
-- Provides pellet level indication, feed system status, and pellet-related
-- error reporting for optimal grill operation
customCapabilities.pelletStatus = capabilities["{{NAMESPACE}}.pelletStatus"]

-- Grill light control capability
-- Enables on/off control of grill lighting with status feedback and
-- integration with grill power state management
customCapabilities.lightControl = capabilities["{{NAMESPACE}}.lightControl"]

-- Grill prime control capability
-- Enables on/off control of grill priming system with status feedback and
-- integration with grill power state management
customCapabilities.primeControl = capabilities["{{NAMESPACE}}.primeControl"]

-- Temperature unit selection capability
-- Allows switching between Fahrenheit and Celsius with automatic conversion
-- of all temperature displays and settings
customCapabilities.temperatureUnit = capabilities["{{NAMESPACE}}.temperatureUnit"]

-- Comprehensive grill status reporting capability
-- Provides detailed status messages, error reporting, communication status,
-- and operational state information for user awareness
customCapabilities.grillStatus = capabilities["{{NAMESPACE}}.grillStatus"]

-- ============================================================================
-- CAPABILITY VALIDATION AND EXPORT
-- ============================================================================

-- Validate that all required capabilities are properly loaded
local function validate_capabilities()
	local required_capabilities = {
		"grillTemp",
		"temperatureProbes",
		"pelletStatus",
		"lightControl",
		"primeControl",
		"temperatureUnit",
		"grillStatus",
	}

	for _, cap_name in ipairs(required_capabilities) do
		if not customCapabilities[cap_name] then
			error(string.format("Failed to load required custom capability: %s", cap_name))
		end
	end

	return true
end

-- Perform validation on module load
validate_capabilities()

return customCapabilities