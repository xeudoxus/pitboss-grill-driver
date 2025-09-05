--[[
  Configuration Module for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  Centralized configuration management for:
  - CONSTANTS: timing, ranges, thresholds, cache, discovery, display, etc.
  - APPROVED_SETPOINTS: Pit Boss-supported target temps
  - ERROR_MESSAGES: user-facing strings for grill error bits
  - POWER_CONSTANTS: estimated consumption for UI power meter
  - VIRTUAL_DEVICES: declarative child-device definitions
  - COMPONENTS: canonical SmartThings component IDs

  Why COMPONENTS exists:
  SmartThings component IDs are fixed by the device profile (e.g., "main",
  "Standard_Grill"). Centralizing the strings avoids drift

  This module provides a single source of truth for all configuration
  values used throughout the driver, making maintenance easier.
--]]

local config = {}

---@class Constants
-- Health monitoring and performance optimization
---@field INITIAL_HEALTH_CHECK_DELAY number Initial delay before starting health checks
---@field MIN_HEALTH_CHECK_INTERVAL number Minimum interval between health checks (seconds)
---@field MAX_HEALTH_CHECK_INTERVAL number Maximum interval for inactive grills (seconds)
---@field ACTIVE_GRILL_MULTIPLIER number Multiplier for active grill check frequency
---@field PREHEATING_GRILL_MULTIPLIER number Multiplier for preheating grill (50% faster updates)
---@field INACTIVE_GRILL_MULTIPLIER number Multiplier for inactive grill check frequency
---@field PANIC_RECOVERY_MULTIPLIER number Multiplier for panic state (fast reconnection attempts)
-- Network and discovery settings
---@field REDISCOVERY_COOLDOWN number Minimum time between rediscovery attempts
---@field STATUS_UPDATE_TIMEOUT number Timeout for status updates during initialization
---@field PERIODIC_REDISCOVERY_INTERVAL number 24 hours between periodic rediscovery
---@field DEFAULT_IP_ADDRESS string Default IP address to ignore in preference changes
---@field DEBUG_IP_ADDRESS string Debug IP address
-- Network scanning and discovery configuration
---@field DEFAULT_SCAN_START_IP number Start of IP range for network scanning
---@field DEFAULT_SCAN_END_IP number End of IP range for network scanning
---@field HEALTH_CHECK_TIMEOUT number Timeout for health check operations (seconds)
---@field COMMAND_RETRY_COUNT number Number of retries for failed commands
---@field DISCOVERY_THREAD_LIMIT number Maximum concurrent discovery threads
---@field SUBNET_CACHE_TIMEOUT number Subnet cache validity period (seconds)
---@field CONNECTION_POOL_SIZE number Maximum cached connections per device
-- IP Management Cache Settings
---@field IP_CACHE_VALIDATION_MINUTES number IP validation cache TTL (minutes)
---@field IP_METADATA_CACHE_SIZE number Maximum metadata cache entries
---@field IP_CACHE_CLEANUP_INTERVAL number IP cache cleanup interval (seconds)
-- Discovery configuration and performance tuning
---@field DISCOVERY_TIMEOUT number Maximum time for discovery process (seconds)
---@field MIN_SCAN_RANGE number Minimum IP range to scan
---@field MAX_SCAN_RANGE number Maximum IP range to scan
---@field DISCOVERY_RETRY_DELAY number Delay before retrying failed discovery
---@field PERFORMANCE_LOG_THRESHOLD number Log performance if discovery takes longer than this
-- API and protocol timeouts
---@field REQUEST_TIMEOUT number HTTP request timeout (seconds)
---@field AUTH_CACHE_TIMEOUT number Authentication cache timeout (seconds)
-- Network connection and scanning constants
---@field MAX_CONCURRENT_CONNECTIONS number Maximum concurrent network connections for scanning
---@field SCAN_CONTINUE boolean Continue scanning after finding first grill (false = cancel remaining scans)
---@field REDISCOVERY_TIMEOUT number Timeout for rediscovery operations (seconds)
---@field MAX_HEALTH_INTERVAL_HOURS number Maximum health check interval (1 hour in seconds)
---@field PITBOSS_APP_IDENTIFIER string Application identifier for device validation
---@field MINIMUM_FIRMWARE_VERSION string Minimum supported firmware version
---@field DEVICE_PROFILE_NAME string Device profile name
-- Temperature and caching settings
---@field REFRESH_DELAY number Delay in seconds before refreshing after commands
---@field DEFAULT_OFFSET number Default temperature offset when no preference set
---@field DEFAULT_UNIT string Default temperature unit (Fahrenheit)
---@field DEFAULT_REFRESH_INTERVAL number Default refresh interval in seconds
---@field CACHE_MULTIPLIER number Cache timeout = refresh_interval * this value
-- Steinhart-Hart calibration constants
---@field REFERENCE_TEMP_F number Reference temperature for calibration in Fahrenheit (ice water)
---@field REFERENCE_TEMP_C number Reference temperature for calibration in Celsius (ice water)
---@field THERMISTOR_BETA number Beta value for NTC thermistors in cooking applications
---@field THERMISTOR_R0 number Resistance at reference temperature (ohms)
---@field TEMP_SCALING_FACTOR number Scaling factor for temperature-dependent offset adjustment
-- Temperature ranges and validation
---@field MIN_TEMP_F number Minimum valid setpoint temperature in Fahrenheit
---@field MAX_TEMP_F number Maximum valid setpoint temperature in Fahrenheit
---@field MIN_TEMP_C number Minimum valid setpoint temperature in Celsius
---@field MAX_TEMP_C number Maximum valid setpoint temperature in Celsius
---@field MIN_SENSOR_TEMP_F number Minimum valid sensor reading in Fahrenheit
---@field MAX_SENSOR_TEMP_F number Maximum valid sensor reading in Fahrenheit
---@field MIN_SENSOR_TEMP_C number Minimum valid sensor reading in Celsius
---@field MAX_SENSOR_TEMP_C number Maximum valid sensor reading in Celsius
-- Operational thresholds
---@field TEMP_TOLERANCE_PERCENT number 95% tolerance for temperature target matching
---@field TARGET_TEMP_RESET_THRESHOLD_F number Reset session if target changes by 50°F or more
---@field TARGET_TEMP_RESET_THRESHOLD_C number Reset session if target changes by 28°C or more
---@field STARTUP_GRACE_PERIOD number Grace period in seconds for sensor initialization
-- Control timeouts and panic settings
---@field PANIC_TIMEOUT number Time in seconds (5 minutes) for "recently active"
---@field PRIME_TIMEOUT number Prime auto-off timeout in seconds
-- Display constants
---@field DISCONNECT_VALUE string Legacy disconnection indicator
---@field DISCONNECT_DISPLAY string Display value for disconnected probes
---@field OFF_DISPLAY_TEMP number Temperature to display when grill is off

---@class Config
---@field CONSTANTS Constants
---@field APPROVED_SETPOINTS table
---@field COMPONENTS table
---@field ERROR_MESSAGES table
---@field STATUS_MESSAGES table
---@field TEMPERATURE_MESSAGES table
---@field POWER_CONSTANTS table
---@field VIRTUAL_DEVICES table
---@field get_temperature_range fun(unit: string): table
---@field get_sensor_range fun(unit: string): table
---@field get_approved_setpoints fun(unit: string): table
---@field get_temp_reset_threshold fun(unit: string): number
---@field get_refresh_interval fun(device: any): number

-- ============================================================================
-- SYSTEM CONSTANTS
-- ============================================================================

local CONSTANTS = {
	-- Health monitoring and performance optimization
	INITIAL_HEALTH_CHECK_DELAY = 5, -- Initial delay before starting health checks
	MIN_HEALTH_CHECK_INTERVAL = 15, -- Minimum interval between health checks (seconds)
	MAX_HEALTH_CHECK_INTERVAL = 300, -- Maximum interval for inactive grills (seconds)
	ACTIVE_GRILL_MULTIPLIER = 1, -- Multiplier for active grill check frequency
	PREHEATING_GRILL_MULTIPLIER = 0.5, -- Multiplier for preheating grill (50% faster updates)
	INACTIVE_GRILL_MULTIPLIER = 6, -- Multiplier for inactive grill check frequency
	PANIC_RECOVERY_MULTIPLIER = 0.3, -- Multiplier for panic state (fast reconnection attempts)

	-- Network and discovery settings
	REDISCOVERY_COOLDOWN = 60, -- Minimum time between rediscovery attempts
	STATUS_UPDATE_TIMEOUT = 10, -- Timeout for status updates during initialization
	PERIODIC_REDISCOVERY_INTERVAL = 24 * 60 * 60, -- 24 hours between periodic rediscovery
	DEFAULT_IP_ADDRESS = "192.168.4.1", -- Default IP address to ignore in preference changes
	DEBUG_IP_ADDRESS = "DEBUG", -- Debug IP address

	-- Network scanning and discovery configuration
	DEFAULT_SCAN_START_IP = 2, -- Start of IP range for network scanning
	DEFAULT_SCAN_END_IP = 253, -- End of IP range for network scanning
	HEALTH_CHECK_TIMEOUT = 5, -- Timeout for health check operations (seconds)
	COMMAND_RETRY_COUNT = 2, -- Number of retries for failed commands
	DISCOVERY_THREAD_LIMIT = 50, -- Maximum concurrent discovery threads
	SUBNET_CACHE_TIMEOUT = 300, -- Subnet cache validity period (seconds)
	CONNECTION_POOL_SIZE = 7, -- Maximum cached connections per device

	-- IP Management Cache Settings
	IP_CACHE_VALIDATION_MINUTES = 5, -- IP validation cache TTL (minutes)
	IP_METADATA_CACHE_SIZE = 50, -- Maximum metadata cache entries
	IP_CACHE_CLEANUP_INTERVAL = 300, -- IP cache cleanup interval (seconds)

	-- Discovery configuration and performance tuning
	DISCOVERY_TIMEOUT = 60, -- Maximum time for discovery process (seconds)
	MIN_SCAN_RANGE = 10, -- Minimum IP range to scan
	MAX_SCAN_RANGE = 240, -- Maximum IP range to scan
	DISCOVERY_RETRY_DELAY = 5, -- Delay before retrying failed discovery
	PERFORMANCE_LOG_THRESHOLD = 30, -- Log performance if discovery takes longer than this

	-- API and protocol timeouts
	REQUEST_TIMEOUT = 10, -- HTTP request timeout (seconds)
	AUTH_CACHE_TIMEOUT = 4, -- Authentication cache timeout (seconds)

	-- Network connection and scanning constants
	MAX_CONCURRENT_CONNECTIONS = 10, -- Maximum concurrent network connections for scanning
	SCAN_CONTINUE = true, -- Continue scanning after finding first grill (false = cancel remaining scans)
	REDISCOVERY_TIMEOUT = 30, -- Timeout for rediscovery operations (seconds)
	MAX_HEALTH_INTERVAL_HOURS = 3600, -- Maximum health check interval (1 hour in seconds)
	PITBOSS_APP_IDENTIFIER = "PitBoss", -- Application identifier for device validation
	MINIMUM_FIRMWARE_VERSION = "0.5.7", -- Minimum supported firmware version
	DEVICE_PROFILE_NAME = "pitboss-grill-profile", -- Primary physical grill profile name

	-- Temperature and caching settings
	REFRESH_DELAY = 3, -- Delay in seconds before refreshing after commands
	DEFAULT_OFFSET = 0, -- Default temperature offset when no preference set
	DEFAULT_UNIT = "F", -- Default temperature unit (Fahrenheit)
	DEFAULT_REFRESH_INTERVAL = 30, -- Default refresh interval in seconds
	CACHE_MULTIPLIER = 2, -- Cache timeout = refresh_interval * this value

	-- Steinhart-Hart calibration constants
	REFERENCE_TEMP_F = 32, -- Reference temperature for calibration (ice water)
	REFERENCE_TEMP_C = 0, -- Reference temperature in Celsius
	THERMISTOR_BETA = 3950, -- Beta value (typical for NTC thermistors in cooking applications)
	THERMISTOR_R0 = 100000, -- Resistance at reference temperature (100k ohm is common)
	TEMP_SCALING_FACTOR = 0.1, -- 10% additional offset per 100°C difference from reference

	-- Temperature ranges and validation
	MIN_TEMP_F = 160, -- Minimum valid setpoint temperature in Fahrenheit
	MAX_TEMP_F = 500, -- Maximum valid setpoint temperature in Fahrenheit
	MIN_TEMP_C = 71, -- Minimum valid setpoint temperature in Celsius
	MAX_TEMP_C = 260, -- Maximum valid setpoint temperature in Celsius
	MIN_SENSOR_TEMP_F = 32, -- Minimum valid sensor reading in Fahrenheit
	MAX_SENSOR_TEMP_F = 600, -- Maximum valid sensor reading in Fahrenheit
	MIN_SENSOR_TEMP_C = 0, -- Minimum valid sensor reading in Celsius
	MAX_SENSOR_TEMP_C = 315, -- Maximum valid sensor reading in Celsius

	-- Operational thresholds
	TEMP_TOLERANCE_PERCENT = 0.95, -- 95% tolerance for temperature target matching
	TARGET_TEMP_RESET_THRESHOLD_F = 50, -- Reset session if target changes by 50°F or more
	TARGET_TEMP_RESET_THRESHOLD_C = 28, -- Reset session if target changes by 28°C or more
	STARTUP_GRACE_PERIOD = 120, -- Grace period in seconds for sensor initialization

	-- Control timeouts and panic settings
	PANIC_TIMEOUT = 300, -- Time in seconds (5 minutes) for "recently active"
	PRIME_TIMEOUT = 30, -- Prime auto-off timeout in seconds

	-- Display constants
	DISCONNECT_VALUE = "Disconnected", -- Legacy disconnection indicator
	DISCONNECT_DISPLAY = "--", -- Display value for disconnected probes
	OFF_DISPLAY_TEMP = 0, -- Temperature to display when grill is off
}

-- Assign CONSTANTS to config table
---@type Constants
config.CONSTANTS = CONSTANTS

-- ============================================================================
-- TEMPERATURE SETPOINTS
-- ============================================================================

-- Pit Boss approved temperature setpoints for precise grill control
config.APPROVED_SETPOINTS = {
	fahrenheit = { 180, 200, 225, 250, 275, 300, 325, 350, 375, 400, 425, 450, 475, 500 },
	celsius = { 82, 93, 107, 121, 135, 148, 162, 176, 190, 204, 218, 232, 260 },
}

-- ============================================================================
-- ERROR MESSAGES
-- ============================================================================

-- Lookup table for grill error conditions and their user-friendly messages
config.ERROR_MESSAGES = {
	high_temp_error = "High Temperature",
	fan_error = "Fan Error",
	hot_error = "Hot Error",
	motor_error = "Motor Error",
	no_pellets = "No Pellets",
	erl_error = "ERL Error",
	error_1 = "Error 1",
	error_2 = "Error 2",
	error_3 = "Error 3",
}

-- ============================================================================
-- LOCALIZED STATUS MESSAGES
-- ============================================================================

-- User-facing status messages and strings for the driver
config.STATUS_MESSAGES = {
	-- Connection and connectivity status messages
	connected = "Connected",
	connected_rediscovered = "Connected (Rediscovered)",
	connected_periodic_rediscovery = "Connected (Periodic Rediscovery)",
	disconnected = "Disconnected",

	-- Operational states
	connected_cooling = "Connected (Cooling)",
	connected_preheating = "Connected (Preheating)",
	connected_heating = "Connected (Heating)",
	connected_at_temp = "Connected (At Temp)",
	connected_grill_off = "Connected (Grill Off)",
	connected_grill_priming = "Connected (Grill Priming)",
	connected_prime_off = "Connected (Grill Prime Off)",

	-- Error states
	error_prefix = "Error: ",
	error_failed_update_ip = "Error: Failed to update IP address",

	-- Warning states
	warning_device_not_reachable = "Warning: Device not reachable at %s",

	-- Failure messages
	failed_power_state = "Failed to change power state",
	failed_set_temp = "Failed to set temp",
	failed_control_light = "Failed to control light",
	failed_control_prime = "Failed to control prime",
	failed_change_temp_unit = "Failed to change temp unit",

	-- Validation errors
	invalid_input_temperature = "Invalid input temperature",
	invalid_temperature_range_after_snapping = "Invalid temperature range after snapping",
	invalid_light_command = "Invalid light command",
	invalid_prime_command = "Invalid prime command",
	invalid_unit_command = "Invalid unit command",

	-- Grill off errors
	grill_off_suffix = " failed (Grill Off)",

	-- Panic messages
	panic_lost_connection_grill_on = "PANIC: Lost Connection (Grill Was On!)",

	-- Authentication messages
	authentication_issue_grill_on = "Auth Issue (Grill On)",
	authentication_issue_grill_off = "Auth Issue (Grill Off)",

	-- Message delay
	message_delay_last_known = "Msg Delay: Last Known",

	-- Main temp error
	error_main_temp = "Error with Main Temp",
}

-- ============================================================================
-- TEMPERATURE AND SENSOR VALUES
-- ============================================================================

config.TEMPERATURE_MESSAGES = {
	disconnected_value = "Disconnected",
	disconnected_display = "--",
}

-- ============================================================================
-- POWER CONSUMPTION CONSTANTS
-- ============================================================================

-- Base power consumption constants derived from real-world measurements
config.POWER_CONSTANTS = {
	BASE_CONTROLLER = 1.7, -- Base ESP32/controller power when everything off
	FAN_LOW_OPERATION = 26.0, -- Fan power during normal grill operation (low speed)
	FAN_HIGH_COOLING = 33.0, -- Fan power during cooling mode (high speed)
	AUGER_MOTOR = 22.0, -- Auger motor power when feeding pellets
	IGNITOR_HOT = 220.0, -- Ignitor power when heating (hot state)
	LIGHT_ON = 50.0, -- Light power consumption
	PRIME_ON = 20.0, -- Prime mode additional power
}

-- ============================================================================
-- VIRTUAL DEVICE CONFIGURATION
-- ============================================================================

-- Virtual device configuration table
config.VIRTUAL_DEVICES = {
	{
		key = "virtual-main",
		preference = "enableVirtualGrillMain",
		label = "Virtual Grill Main",
		profile = "virtual-main",
		model = "VirtualGrillMain",
	},
	{
		key = "virtual-probe-1",
		preference = "enableVirtualProbe1",
		label = "Virtual Grill Probe 1",
		profile = "virtual-probe-1",
		model = "VirtualProbe1",
	},
	{
		key = "virtual-probe-2",
		preference = "enableVirtualProbe2",
		label = "Virtual Grill Probe 2",
		profile = "virtual-probe-2",
		model = "VirtualProbe2",
	},
	{
		key = "virtual-probe-3",
		preference = "enableVirtualProbe3",
		label = "Virtual Grill Probe 3",
		profile = "virtual-probe-3",
		model = "VirtualProbe3",
	},
	{
		key = "virtual-probe-4",
		preference = "enableVirtualProbe4",
		label = "Virtual Grill Probe 4",
		profile = "virtual-probe-4",
		model = "VirtualProbe4",
	},
	{
		key = "virtual-light",
		preference = "enableVirtualGrillLight",
		label = "Virtual Grill Light",
		profile = "virtual-light",
		model = "VirtualGrillLight",
	},
	{
		key = "virtual-prime",
		preference = "enableVirtualGrillPrime",
		label = "Virtual Grill Prime",
		profile = "virtual-prime",
		model = "VirtualGrillPrime",
	},
	{
		key = "virtual-at-temp",
		preference = "enableVirtualAtTemp",
		label = "Virtual Grill At-Temp",
		profile = "virtual-at-temp",
		model = "VirtualAtTemp",
	},
	{
		key = "virtual-error",
		preference = "enableVirtualError",
		label = "Virtual Grill Error",
		profile = "virtual-error",
		model = "VirtualError",
	},
}

-- ============================================================================
-- COMPONENT IDS (centralized)
-- ============================================================================

-- Centralized component identifiers to ensure consistency across modules
config.COMPONENTS = {
	MAIN = "main",
	GRILL = "Standard_Grill",
	PROBE1 = "probe1",
	PROBE2 = "probe2",
	ERROR = "Grill_Error",
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get temperature range for specified unit
-- @param unit string Temperature unit ("F" or "C")
-- @return table Table with min and max temperature values
function config.get_temperature_range(unit)
	if unit == "F" then
		return {
			min = CONSTANTS.MIN_TEMP_F,
			max = CONSTANTS.MAX_TEMP_F,
		}
	else
		return {
			min = CONSTANTS.MIN_TEMP_C,
			max = CONSTANTS.MAX_TEMP_C,
		}
	end
end

--- Get sensor temperature range for specified unit
-- @param unit string Temperature unit ("F" or "C")
-- @return table Table with min and max sensor values
function config.get_sensor_range(unit)
	if unit == "F" then
		return {
			min = CONSTANTS.MIN_SENSOR_TEMP_F,
			max = CONSTANTS.MAX_SENSOR_TEMP_F,
		}
	else
		return {
			min = CONSTANTS.MIN_SENSOR_TEMP_C,
			max = CONSTANTS.MAX_SENSOR_TEMP_C,
		}
	end
end

--- Get approved setpoints for specified unit
-- @param unit string Temperature unit ("F" or "C")
-- @return table Array of approved temperature setpoints
function config.get_approved_setpoints(unit)
	return unit == "F" and config.APPROVED_SETPOINTS.fahrenheit or config.APPROVED_SETPOINTS.celsius
end

--- Get target temperature reset threshold for specified unit
-- @param unit string Temperature unit ("F" or "C")
-- @return number Temperature change threshold for session reset
function config.get_temp_reset_threshold(unit)
	return unit == "F" and CONSTANTS.TARGET_TEMP_RESET_THRESHOLD_F or CONSTANTS.TARGET_TEMP_RESET_THRESHOLD_C
end

--- Get refresh interval from device preferences with default fallback
-- @param device SmartThings device object
-- @return number Refresh interval in seconds
function config.get_refresh_interval(device)
	return (device and device.preferences and device.preferences.refreshInterval) or CONSTANTS.DEFAULT_REFRESH_INTERVAL
end

---@type Config
return config