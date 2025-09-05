--[[
  Temperature Service for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module handles all temperature-related operations including conversion, validation, caching,
  and display formatting. It provides a centralized service for temperature management across the
  entire driver, ensuring consistent temperature handling and optimal user experience.

  Key Features:
  - Bidirectional temperature conversion between Fahrenheit and Celsius
  - Comprehensive temperature validation with unit-specific ranges
  - Intelligent caching system with timeout management and refresh intervals
  - Approved setpoint snapping to Pit Boss compatible temperatures
  - Session-based heating state tracking with automatic reset logic
  - Disconnected sensor handling with appropriate display values
  - Consistent disconnected/cached value handling for all temperature sensors
  - Unit-aware temperature validation (0°F invalid, 0°C valid)
  - Cache management with automatic cleanup and persistence

  Temperature Operations:
  - Conversion: F ↔ C with precise calculations
  - Validation: Range checking with unit-specific limits
  - Setpoint validation and snapping: Ensures setpoints are within allowed values and aligned to Pit Boss increments
  - Caching: Temporary storage, retrieval, and timeout-based invalidation of temperature values
  - Cache management: Automatic cleanup, persistence, and manual clearing
  - Session tracking: Tracks preheating/heating state and target temperature achievement
  - Disconnected handling: Provides display values and logic for disconnected sensors
  - Display formatting: Formatted output with unit indicators, disconnect handling, and numeric/string conversion

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local log = require("log")
local config = require("config")

local temperature_service = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get current timestamp for cache management
-- @return number Current Unix timestamp
local function get_current_time()
	return os.time()
end

--- Helper: get device display unit with fallback to default
-- @param device SmartThings device object
-- @return string "F" or "C"
function temperature_service.get_device_unit(device)
	local unit = device and device.get_field and device:get_field("unit")
	return (unit == "C") and "C" or config.CONSTANTS.DEFAULT_UNIT
end

--- Extract refresh interval from device preferences
-- @param device SmartThings device object
-- @return number Refresh interval in seconds
local function get_refresh_interval(device)
	return config.get_refresh_interval(device)
end

-- ============================================================================
-- TEMPERATURE CONVERSION
-- ============================================================================

--- Convert Celsius temperature to Fahrenheit with ceiling rounding
-- @param celsius_temp number Temperature in Celsius
-- @return number Temperature in Fahrenheit (rounded up)
function temperature_service.celsius_to_fahrenheit(celsius_temp)
	return math.ceil((celsius_temp * 9 / 5) + 32)
end

--- Convert Fahrenheit temperature to Celsius with ceiling rounding
-- @param fahrenheit_temp number Temperature in Fahrenheit
-- @return number Temperature in Celsius (rounded up)
function temperature_service.fahrenheit_to_celsius(fahrenheit_temp)
	return math.ceil((fahrenheit_temp - 32) * 5 / 9)
end

-- ============================================================================
-- TEMPERATURE VALIDATION
-- ============================================================================

--- Check if probe temperature reading is valid based on unit and value
-- @param probe_temp number|string|nil Probe temperature reading
-- @param unit string Temperature unit ("F" or "C")
-- @return boolean True if temperature reading is valid
function temperature_service.is_valid_temperature(probe_temp, unit)
	-- nil is never valid
	if probe_temp == nil then
		return false
	end

	-- "Disconnected" string is never valid
	if probe_temp == config.CONSTANTS.DISCONNECT_VALUE then
		return false
	end

	-- Must be a number to be potentially valid
	if type(probe_temp) ~= "number" then
		return false
	end

	-- Unit-specific validation
	local sensor_range = config.get_sensor_range(unit)
	return probe_temp >= sensor_range.min and probe_temp <= sensor_range.max
end

--- Validate temperature setpoint is within acceptable range
-- @param temp number Temperature to validate
-- @param unit string Temperature unit ("F" or "C")
-- @return boolean True if temperature is within valid setpoint range
function temperature_service.is_valid_setpoint(temp, unit)
	local temp_range = config.get_temperature_range(unit)
	return temp >= temp_range.min and temp <= temp_range.max
end

-- ============================================================================
-- APPROVED SETPOINT SNAPPING
-- ============================================================================

--- Snap requested temperature to closest approved setpoint for grill compatibility
-- @param target_temp number Requested temperature
-- @param unit string Temperature unit ("F" or "C")
-- @return number Closest approved temperature setpoint
function temperature_service.snap_to_approved_setpoint(target_temp, unit)
	local approved_list = config.get_approved_setpoints(unit)

	if not approved_list or #approved_list == 0 then
		log.warn(string.format("snap_to_approved_setpoint called with empty setpoint list for unit: %s", unit))
		return target_temp
	end

	local closest_setpoint = approved_list[1]
	local min_diff = math.abs(target_temp - closest_setpoint)

	for i = 2, #approved_list do
		local current_setpoint = approved_list[i]
		local diff = math.abs(target_temp - current_setpoint)
		if diff < min_diff then
			min_diff = diff
			closest_setpoint = current_setpoint
		end
	end

	return closest_setpoint
end

-- ============================================================================
-- TEMPERATURE CACHING
-- ============================================================================

--- Determine if cached temperature value should be used based on age and timeout
-- @param device SmartThings device object
-- @param field_name string Name of the temperature field
-- @return boolean True if cached value is still valid
local function should_use_cached_value(device, field_name)
	if not device then
		log.debug("should_use_cached_value called with nil device")
		return false
	end

	local last_update_time = device:get_field("last_update_" .. field_name)
	if not last_update_time then
		return false
	end

	local refresh_interval = get_refresh_interval(device)
	local cache_timeout = refresh_interval * config.CONSTANTS.CACHE_MULTIPLIER
	local current_time = get_current_time()

	local time_since_update = current_time - last_update_time

	-- Check for negative time differences (clock issues or overflow)
	if time_since_update < 0 then
		log.warn(
			string.format(
				"Negative time difference detected for %s cache (current=%d, last_update=%d), invalidating cache",
				field_name,
				current_time,
				last_update_time
			)
		)
		-- Clear the invalid timestamp
		device:set_field("last_update_" .. field_name, nil)
		return false
	end

	local should_cache = time_since_update <= cache_timeout

	if should_cache then
		log.debug(
			string.format(
				"Using cached value for %s (age: %ds, timeout: %ds)",
				field_name,
				time_since_update,
				cache_timeout
			)
		)
	else
		log.debug(
			string.format("Cache expired for %s (age: %ds, timeout: %ds)", field_name, time_since_update, cache_timeout)
		)
	end

	return should_cache
end

--- Store temperature value with current timestamp for caching
-- @param device SmartThings device object
-- @param field_name string Name of the temperature field
-- @param value number|string Temperature value to cache
function temperature_service.store_temperature_value(device, field_name, value)
	device:set_field("cached_" .. field_name, value, { persist = true })
	device:set_field("last_update_" .. field_name, get_current_time(), { persist = true })
	log.debug(string.format("Stored cached value for %s: %s (real data received)", field_name, tostring(value)))
end

--- Retrieve cached temperature value if valid, otherwise return default
-- @param device SmartThings device object
-- @param field_name string Name of the temperature field
-- @param default_value number|string|nil Default value if cache is invalid
-- @return number|string Temperature value (cached or default)
function temperature_service.get_cached_temperature_value(device, field_name, default_value)
	if not device then
		log.debug(
			string.format(
				"get_cached_temperature_value called with nil device for field '%s' - returning default",
				tostring(field_name)
			)
		)
		return default_value or config.CONSTANTS.OFF_DISPLAY_TEMP
	end

	if should_use_cached_value(device, field_name) then
		local cached_value = device:get_field("cached_" .. field_name)
		if cached_value ~= nil then
			log.debug(string.format("Retrieved cached value for %s: %s", field_name, tostring(cached_value)))
			return cached_value
		end
	end
	return default_value or config.CONSTANTS.OFF_DISPLAY_TEMP
end

-- Helper: Nicely format display string for disconnected values
function temperature_service.display_for_disconnect()
	return config.CONSTANTS.DISCONNECT_DISPLAY
end

--- Clear all cached temperature values
-- @param device SmartThings device object
function temperature_service.clear_temperature_cache(device)
	local cache_fields = { "grill_temp", "set_temp", "p1_temp", "p2_temp", "p1_temp", "p2_temp" }
	for _, field in ipairs(cache_fields) do
		device:set_field("cached_" .. field, nil)
		device:set_field("last_update_" .. field, nil)
	end
	log.debug(string.format("Cleared temperature cache for device: %s", device.id))
end

-- ============================================================================
-- SESSION TRACKING
-- ============================================================================

--- Track if grill has reached target temperature in this session
-- @param device SmartThings device object
-- @param current_temp number Current grill temperature
-- @param target_temp number Target grill temperature
-- @return boolean True if grill has reached target temperature in this session
function temperature_service.track_session_temp_reached(device, current_temp, target_temp)
	if not device then
		log.debug("track_session_temp_reached called with nil device")
		return false
	end

	-- Coerce to numbers for safe arithmetic (handles strings coming from external sources)
	local new_target = tonumber(target_temp)
	if not new_target or new_target <= config.CONSTANTS.OFF_DISPLAY_TEMP then
		return false
	end

	-- Check if target temperature has changed significantly TODO: Not sure if I want this
	--[[
  local last_target_raw = device:get_field("last_target_temp")
  local last_target_temp = tonumber(last_target_raw)
  if last_target_temp and last_target_temp ~= new_target then
    local unit = device:get_field("unit") or config.CONSTANTS.DEFAULT_UNIT
    local threshold = config.get_temp_reset_threshold(unit)

    local temp_change = math.abs(new_target - last_target_temp)
    log.debug(string.format("Session target change detected: last=%s, new=%s, delta=%.1f, threshold=%s",
      tostring(last_target_raw), tostring(new_target), temp_change, tostring(threshold)))

    if temp_change >= threshold then
      device:set_field("session_reached_temp", false, {persist = true})
      log.info(string.format("Target temperature changed significantly (%.1f°%s -> %.1f°%s) - resetting session",
        last_target_temp, unit, new_target, unit))
    end
  end
  ]]
	--

	-- Store current target temperature (as number)
	device:set_field("last_target_temp", new_target, { persist = true })

	local temp_threshold = new_target * config.CONSTANTS.TEMP_TOLERANCE_PERCENT
	local current_num = tonumber(current_temp)
	local currently_at_temp = (current_num and (current_num >= temp_threshold)) or false
	local session_reached_temp = device:get_field("session_reached_temp") or false

	if currently_at_temp and not session_reached_temp then
		device:set_field("session_reached_temp", true, { persist = true })
		-- RULE: Once grill reaches temp in a session, track that it ever reached temp
		device:set_field("session_ever_reached_temp", true, { persist = true })
		log.debug(string.format("Session temperature reached: current=%.1f, target=%.1f", current_num, new_target))
	end

	log.debug(
		string.format("Session reached target temp: current=%.1f >= threshold=%.1f", current_num or 0, temp_threshold)
	)
	return true
end

--- Determine if grill is in preheating state
-- @param device SmartThings device object
-- @param runtime number Grill runtime in seconds
-- @param current_temp number Current grill temperature
-- @param target_temp number Target grill temperature
-- @return boolean True if grill is preheating
function temperature_service.is_grill_preheating(device, runtime, current_temp, target_temp)
	-- If there's no meaningful target, we're not preheating
	if not target_temp or target_temp <= config.CONSTANTS.OFF_DISPLAY_TEMP then
		return false
	end

	-- Freshly turned on (runtime == 0) should be considered preheating
	local temp_threshold = target_temp * config.CONSTANTS.TEMP_TOLERANCE_PERCENT
	if runtime == 0 then
		-- RULE: If grill has EVER reached temp in this session, NEVER go back to preheating
		local session_ever_reached_raw = device and device.get_field and device:get_field("session_ever_reached_temp")
		local session_ever_reached_temp = (session_ever_reached_raw == true)
		if session_ever_reached_temp then
			log.debug("Preheating check: runtime==0 but session ever reached before => not preheating")
			return false
		end

		-- Only treat immediate on as preheating if current temperature is below threshold
		if type(current_temp) == "number" and current_temp < temp_threshold then
			log.debug("Preheating check: runtime==0 and current below threshold => preheating")
			return true
		else
			log.debug("Preheating check: runtime==0 but current at/above threshold => not preheating")
			return false
		end
	end

	-- Otherwise, preheating means we haven't reached the session target yet
	local session_reached_raw = device and device.get_field and device:get_field("session_reached_temp")
	local session_reached_temp = (session_reached_raw == true) -- normalize to boolean
	local is_preheating = not session_reached_temp
		and (type(current_temp) == "number" and current_temp < temp_threshold)

	log.debug(
		string.format(
			"Preheating check: current=%s, target=%s, threshold=%.1f, session_reached=%s, preheating=%s",
			tostring(current_temp),
			tostring(target_temp),
			temp_threshold,
			tostring(session_reached_temp),
			tostring(is_preheating)
		)
	)

	return is_preheating
end

--- Determine if grill is in heating state
-- @param device SmartThings device object
-- @param current_temp number Current grill temperature
-- @param target_temp number Target grill temperature
-- @return boolean True if grill is heating
function temperature_service.is_grill_heating(device, current_temp, target_temp)
	if not target_temp or target_temp <= config.CONSTANTS.OFF_DISPLAY_TEMP then
		return false
	end

	if type(current_temp) ~= "number" then
		return false
	end

	local temp_threshold = target_temp * config.CONSTANTS.TEMP_TOLERANCE_PERCENT
	local is_heating = current_temp < temp_threshold

	local session_reached_raw = device and device.get_field and device:get_field("session_reached_temp")
	local session_reached_temp = (session_reached_raw == true)
	-- RULE: For heating state, check if session has EVER reached temp (not just current target)
	local session_ever_reached_raw = device and device.get_field and device:get_field("session_ever_reached_temp")
	local session_ever_reached_temp = (session_ever_reached_raw == true)
	log.debug(
		string.format(
			"Heating check: current=%s, target=%s, threshold=%.1f, session_reached=%s, session_ever_reached=%s, heating=%s",
			tostring(current_temp),
			tostring(target_temp),
			temp_threshold,
			tostring(session_reached_temp),
			tostring(session_ever_reached_temp),
			tostring(is_heating)
		)
	)

	-- Only consider this a 'heating' event if the session has previously reached the target
	return is_heating and session_ever_reached_temp
end

--- Clear session tracking data
-- @param device SmartThings device object
function temperature_service.clear_session_tracking(device)
	device:set_field("session_reached_temp", false, { persist = true })
	-- NOTE: session_ever_reached_temp is preserved across power cycles within a session
	-- It only gets cleared on complete session shutdown (no last_target_temp)
	device:set_field("last_target_temp", nil)
	log.debug("Cleared temperature session tracking")
end

-- ============================================================================
-- TEMPERATURE DISPLAY FORMATTING
-- ============================================================================

--- Format temperature for display with disconnected sensor handling
-- @param temp_value number|string Temperature value or disconnected indicator
-- @param is_valid boolean True if temperature reading is valid
-- @param cached_value number|string|nil Cached temperature value
-- @return string Formatted temperature display value
-- @return number Numeric temperature value for capabilities
function temperature_service.format_temperature_display(temp_value, is_valid, cached_value)
	local display_value
	local numeric_value

	if is_valid then
		display_value = string.format("%.0f", temp_value)
		numeric_value = temp_value
	else
		if cached_value ~= nil and cached_value > config.CONSTANTS.OFF_DISPLAY_TEMP then
			display_value = string.format("%.0f", cached_value)
			numeric_value = cached_value
		else
			display_value = config.CONSTANTS.DISCONNECT_DISPLAY
			numeric_value = config.CONSTANTS.OFF_DISPLAY_TEMP
		end
	end

	return display_value, numeric_value
end

return temperature_service