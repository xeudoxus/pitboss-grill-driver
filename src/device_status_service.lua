--[[
  Device Status Service for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module manages comprehensive device status updates, error state handling, communication status,
  and power consumption calculations. It serves as the central orchestrator for all device state
  updates, ensuring consistent and accurate representation of grill status across all capabilities.

  Features:
  - Device status orchestration and coordination
  - Error state management with panic handling
  - Power consumption calculation
  - Temperature range updates with validation and caching
  - System component state management (fan, auger, ignitor)
  - Communication status determination
  - Session-based heating state tracking
  - Grill runtime tracking
  - Offline status handling with panic state preservation
  - Unified Probe Display: All 4 probes shown in main display with individual components for probes 1 & 2
  - Temperature sensors (grill, probes) with offset application and consistent disconnected/cached value handling
  - System states (fan, auger, ignitor, light, prime)
  - Error conditions and panic alarm management
  - Power consumption estimation and meter updates
  - Communication status with contextual messages
  - Thermostat mode and heating setpoint management

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local capabilities = require("st.capabilities")
local log = require("log")
local config = require("config")
local custom_caps = require("custom_capabilities")
local temperature_service = require("temperature_service")
local panic_manager = require("panic_manager")
local temperature_calibration = require("temperature_calibration")
local probe_display = require("probe_display")
local language = config.STATUS_MESSAGES

local device_status_service = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get current timestamp for timing operations
-- @return number Current Unix timestamp
local function get_current_time()
	return os.time()
end

--- Track grill start time and calculate runtime
-- @param device SmartThings device object
-- @param is_grill_on boolean Current grill power state
-- @return number Grill runtime in seconds
local function track_grill_runtime(device, is_grill_on)
	local current_time = get_current_time()
	local grill_start_time = device:get_field("grill_start_time")

	if is_grill_on then
		if not grill_start_time then
			device:set_field("grill_start_time", current_time, { persist = true })
			-- RULE: Don't clear session if there's a previous target (continuation of session)
			local last_target = device:get_field("last_target_temp")
			if not last_target then
				temperature_service.clear_session_tracking(device)
				log.debug("Grill turned on - recording start time and clearing session tracking")
			else
				log.debug("Grill turned on - continuing previous session")
			end
			return 0
		else
			local runtime = current_time - grill_start_time
			log.debug(string.format("Grill runtime: %d seconds", runtime))
			return runtime
		end
	else
		if grill_start_time then
			device:set_field("grill_start_time", nil)
			-- RULE: Clear session_ever_reached_temp only on complete shutdown
			local last_target = device:get_field("last_target_temp")
			if not last_target then
				-- Complete shutdown - clear session_ever_reached_temp
				device:set_field("session_ever_reached_temp", false, { persist = true })
				log.debug("Grill turned off - complete shutdown, clearing session history")
			else
				log.debug("Grill turned off - power cycle, preserving session history")
			end
			temperature_service.clear_session_tracking(device)
			log.debug("Grill turned off - clearing start time and session tracking")
		end
		return 0
	end
end

-- ============================================================================
-- GRILL STATE DETECTION
-- ============================================================================

--- Check if grill is currently powered on based on status data
-- @param device SmartThings device object
-- @param status table Current grill status data (optional)
-- @return boolean True if grill is powered on
function device_status_service.is_grill_on(device, status)
	if not status then
		local switch_state =
			device:get_latest_state("Standard_Grill", capabilities.switch.ID, capabilities.switch.switch.NAME)
		log.info(string.format("Grill on check (no status): switch_state=%s", tostring(switch_state)))
		return (switch_state == "on")
	else
		log.info(
			string.format(
				"Grill on check: motor=%s, hot=%s, module=%s",
				tostring(status.motor_state),
				tostring(status.hot_state),
				tostring(status.module_on)
			)
		)

		-- If all three are false, grill is definitely off
		if not status.motor_state and not status.hot_state and not status.module_on then
			log.info("Grill determined to be OFF (all components false)")
			return false
		end
		-- If any is true, grill is on
		if status.motor_state or status.hot_state or status.module_on then
			log.info("Grill determined to be ON (at least one component true)")
			return true
		end
	end
	-- Default fallback
	log.info("Grill on check: using default fallback (false)")
	return false
end

--- Determine if grill is in cooling state
-- @param is_grill_on boolean Current grill power state
-- @param fan_state boolean Current fan state
-- @return boolean True if grill is cooling
local function is_grill_cooling(is_grill_on, fan_state)
	local is_cooling = (not is_grill_on) and fan_state

	log.info(
		string.format(
			"Cooling check: grill_on=%s, fan_on=%s, cooling=%s",
			tostring(is_grill_on),
			tostring(fan_state),
			tostring(is_cooling)
		)
	)

	return is_cooling
end

-- ============================================================================
-- ERROR HANDLING AND STATUS REPORTING
-- ============================================================================

--- Collect and format error messages from grill status data
-- @param status table Current grill status data
-- @return string Comma-separated error messages or "No Errors"
local function collect_errors(status)
	local errors = {}
	local error_count = 0

	for field, message in pairs(config.ERROR_MESSAGES) do
		if status[field] then
			error_count = error_count + 1
			errors[error_count] = message
		end
	end

	return error_count > 0 and table.concat(errors, ", ") or "No Errors"
end

--- Check if any temperature values are using cached data due to disconnection
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @return boolean True if any temperature is using cached data
local function is_using_cached_data(device, status)
	local using_cache = false
	local unit = temperature_service.get_device_unit(device)

	-- Check grill temp
	if not temperature_service.is_valid_temperature(status.grill_temp, unit) then
		local cached_value = temperature_service.get_cached_temperature_value(device, "grill_temp", nil)
		if cached_value ~= nil and cached_value > config.CONSTANTS.OFF_DISPLAY_TEMP then
			using_cache = true
		end
	end

	-- Check probes (only if previously working)
	for _, probe_data in ipairs({
		{ temp = status.p1_temp, field = "p1_temp" },
		{ temp = status.p2_temp, field = "p2_temp" },
		{ temp = status.p3_temp, field = "p3_temp" },
		{ temp = status.p4_temp, field = "p4_temp" },
	}) do
		if not temperature_service.is_valid_temperature(probe_data.temp, unit) then
			local cached_value = temperature_service.get_cached_temperature_value(device, probe_data.field, nil)
			if cached_value ~= nil and cached_value > config.CONSTANTS.OFF_DISPLAY_TEMP then
				using_cache = true
			end
		end
	end

	return using_cache
end

--- Check if main grill temperature sensor has failed
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @return boolean True if main grill temp sensor failed
local function is_main_grill_temp_failed(device, status)
	local unit = temperature_service.get_device_unit(device)

	if temperature_service.is_valid_temperature(status.grill_temp, unit) then
		return false
	end

	-- Check for usable cache
	local cached_value = temperature_service.get_cached_temperature_value(device, "grill_temp", nil)
	if cached_value ~= nil and cached_value > config.CONSTANTS.OFF_DISPLAY_TEMP then
		return false
	end

	-- Check startup grace period
	local grill_start_time = device:get_field("grill_start_time")
	if grill_start_time then
		local current_time = get_current_time()
		local startup_time = current_time - grill_start_time

		if startup_time < config.CONSTANTS.STARTUP_GRACE_PERIOD then
			log.debug(
				string.format(
					"Grill temp invalid but within startup grace period (%ds/%ds)",
					startup_time,
					config.CONSTANTS.STARTUP_GRACE_PERIOD
				)
			)
			return false
		end
	end

	-- If other sensors are working (like probes), be more lenient about main temp
	-- This indicates the grill is communicating fine, just main temp might be disconnected
	if
		status
		and (
			temperature_service.is_valid_temperature(status.p1_temp, unit)
			or temperature_service.is_valid_temperature(status.p2_temp, unit)
			or temperature_service.is_valid_temperature(status.p3_temp, unit)
			or temperature_service.is_valid_temperature(status.p4_temp, unit)
		)
	then
		log.debug("Main grill temp invalid but other sensors working - treating as sensor-specific issue, not failure")
		return false
	end

	-- If device was recently online, give more grace time for temp sensor recovery
	local last_successful_health = device:get_field("last_successful_health_check") or 0
	local current_time = get_current_time()
	if (current_time - last_successful_health) < (config.CONSTANTS.STARTUP_GRACE_PERIOD * 2) then
		log.debug("Main grill temp invalid but device was recently healthy - allowing recovery time")
		return false
	end

	log.debug("Main grill temp sensor failed - disconnected with no cache and past grace period")
	return true
end

--- Determine appropriate communication status message
-- @param device SmartThings device object
-- @param status table Current grill status data (nil if offline)
-- @param is_offline boolean True if grill is offline
-- @param auth_failure_context table Optional context for authentication failures {grill_is_on: boolean}
-- @return string Status message for display
local function get_communication_status(device, status, is_offline, auth_failure_context)
	-- Check for panic state first
	local panic_message = panic_manager.get_panic_status_message(device)
	if panic_message then
		return panic_message
	end

	-- Check for authentication failure
	if auth_failure_context then
		if auth_failure_context.grill_is_on then
			return language.authentication_issue_grill_on
		else
			return language.authentication_issue_grill_off
		end
	end

	-- Check if offline
	if is_offline or status == nil then
		return language.disconnected
	end

	-- Check for hardware errors
	local error_message = collect_errors(status)
	if not string.find(error_message, "No Errors") then
		return error_message
	end

	-- Check for main temp sensor failure
	if is_main_grill_temp_failed(device, status) then
		return language.error_main_temp
	end

	-- Check for cached data usage
	if is_using_cached_data(device, status) then
		return language.message_delay_last_known
	end

	-- Determine operational state
	local grill_on = device_status_service.is_grill_on(device, status)
	local is_cooling = is_grill_cooling(grill_on, status.fan_state)

	if is_cooling then
		device:set_field("is_preheating", false, { persist = true })
		device:set_field("is_heating", false, { persist = true })
		device:set_field("is_cooling", true, { persist = true })
		return language.connected_cooling
	elseif grill_on then
		-- Determine heating state
		local runtime = track_grill_runtime(device, grill_on)
		local unit = temperature_service.get_device_unit(device)

		local current_temp = temperature_service.is_valid_temperature(status.grill_temp, unit) and status.grill_temp
			or temperature_service.get_cached_temperature_value(device, "grill_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)
		local target_temp = temperature_service.is_valid_temperature(status.set_temp, unit) and status.set_temp
			or temperature_service.get_cached_temperature_value(device, "set_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)

		-- Update session state if we've reached target temperature during this session
		do
			local last_target = device:get_field("last_target_temp")
			log.debug(
				string.format(
					"Session tracking: current=%s, target=%s, last_target_field=%s",
					tostring(current_temp),
					tostring(target_temp),
					tostring(last_target)
				)
			)
		end
		temperature_service.track_session_temp_reached(device, current_temp, target_temp)

		local preheating = temperature_service.is_grill_preheating(device, runtime, current_temp, target_temp)
		local heating = temperature_service.is_grill_heating(device, current_temp, target_temp)

		device:set_field("is_preheating", preheating, { persist = true })
		device:set_field("is_heating", heating, { persist = true })
		device:set_field("is_cooling", false, { persist = true })

		if preheating then
			return language.connected_preheating
		elseif heating then
			return language.connected_heating
		else
			return language.connected_at_temp
		end
	else
		device:set_field("is_preheating", false, { persist = true })
		device:set_field("is_heating", false, { persist = true })
		device:set_field("is_cooling", false, { persist = true })
		return language.connected_grill_off
	end
end

-- ============================================================================
-- POWER CONSUMPTION CALCULATION
-- ============================================================================

--- Calculate estimated power consumption based on grill component states
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @return number Estimated power consumption in watts
local function calculate_power_consumption(device, status)
	local total_watts = config.POWER_CONSTANTS.BASE_CONTROLLER
	local grill_on = device_status_service.is_grill_on(device, status)

	if not grill_on then
		-- Check for cooling mode
		if status.fan_state then
			local fan_cooling_net = config.POWER_CONSTANTS.FAN_HIGH_COOLING - config.POWER_CONSTANTS.BASE_CONTROLLER
			total_watts = total_watts + fan_cooling_net
		end
		return total_watts
	end

	-- Calculate component power consumption
	if status.fan_state then
		local is_cooling = is_grill_cooling(grill_on, status.fan_state)
		local fan_power_net = is_cooling
				and (config.POWER_CONSTANTS.FAN_HIGH_COOLING - config.POWER_CONSTANTS.BASE_CONTROLLER)
			or (config.POWER_CONSTANTS.FAN_LOW_OPERATION - config.POWER_CONSTANTS.BASE_CONTROLLER)
		total_watts = total_watts + fan_power_net
	end

	if status.motor_state then
		total_watts = total_watts + config.POWER_CONSTANTS.AUGER_MOTOR
	end

	if status.hot_state then
		total_watts = total_watts + config.POWER_CONSTANTS.IGNITOR_HOT
	end

	if status.light_state then
		total_watts = total_watts + config.POWER_CONSTANTS.LIGHT_ON
	end

	if status.prime_state then
		total_watts = total_watts + config.POWER_CONSTANTS.PRIME_ON
	end

	log.debug(string.format("Power calc total: %.1fW", total_watts))
	return math.max(0, total_watts)
end

-- ============================================================================
-- DEVICE UPDATE FUNCTIONS
-- ============================================================================

--- Update temperature ranges for all relevant device components
-- @param device SmartThings device object
-- @param unit string Current temperature unit
local function update_temperature_ranges(device, unit)
	local temp_range = config.get_temperature_range(unit)
	local range_event = { value = { minimum = temp_range.min, maximum = temp_range.max }, unit = unit }

	local components = { config.COMPONENTS.PROBE1, config.COMPONENTS.PROBE2, config.COMPONENTS.GRILL }
	for _, component_name in ipairs(components) do
		local component = device.profile.components[component_name]
		device:emit_component_event(component, capabilities.temperatureMeasurement.temperatureRange(range_event))
	end

	local standard_grill = device.profile.components[config.COMPONENTS.GRILL]
	device:emit_component_event(
		standard_grill,
		capabilities.thermostatHeatingSetpoint.heatingSetpointRange(range_event)
	)
end

--- Update all temperature probes with unified display
-- @param device SmartThings device object
-- @param status table Current grill status data containing probe temperatures
-- @param offsets table Temperature offsets for all probes
-- @param unit string Temperature unit
local function update_all_probes(device, status, offsets, unit)
	-- Process all probe temperatures and apply offsets
	local probe_temps = {}
	local probe_data = {
		{ temp = status.p1_temp, offset = offsets.probe1, component = "probe1", cache_field = "p1_temp" },
		{ temp = status.p2_temp, offset = offsets.probe2, component = "probe2", cache_field = "p2_temp" },
		{ temp = status.p3_temp, offset = offsets.probe3, cache_field = "p3_temp" }, -- No component for UI
		{ temp = status.p4_temp, offset = offsets.probe4, cache_field = "p4_temp" }, -- No component for UI
	}

	-- Process each probe and store valid temperatures
	for i, probe in ipairs(probe_data) do
		local is_valid = temperature_service.is_valid_temperature(probe.temp, unit)
		local temp_value, cached_value

		if is_valid then
			-- Apply Steinhart-Hart calibration instead of simple offset
			temp_value = temperature_calibration.apply_calibration(probe.temp, probe.offset, unit, "probe" .. i)
			temperature_service.store_temperature_value(device, probe.cache_field, temp_value)
			probe_temps[i] = temp_value
		else
			cached_value = temperature_service.get_cached_temperature_value(device, probe.cache_field, nil)
			temp_value = cached_value
			-- Use disconnect display constant if no cached value available
			probe_temps[i] = temp_value or config.CONSTANTS.DISCONNECT_DISPLAY
		end

		-- Update individual probe components (only for probes 1 & 2 in main UI)
		if i <= 2 then
			local _, numeric_value = temperature_service.format_temperature_display(temp_value, is_valid, cached_value)
			local component = device.profile.components[probe.component]
			if component then
				device:emit_component_event(
					component,
					capabilities.temperatureMeasurement.temperature({ value = numeric_value, unit = unit })
				)
			end
		end
	end

	-- Generate unified probe display text using status directly
	local probe_display_text = probe_display.generate_probe_text(probe_temps, status.is_fahrenheit)

	-- Emit the unified probe display event
	device:emit_event(custom_caps.temperatureProbes.probe({ value = probe_display_text }))
end

--- Update main grill temperature with caching support
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @param unit string Temperature unit
-- @param grill_offset number Temperature offset
local function update_grill_temperature(device, status, unit, grill_offset)
	local is_valid = temperature_service.is_valid_temperature(status.grill_temp, unit)
	local temp_value, cached_value

	if is_valid then
		-- Apply Steinhart-Hart calibration instead of simple offset
		temp_value = temperature_calibration.apply_calibration(status.grill_temp, grill_offset, unit, "grill")
		temperature_service.store_temperature_value(device, "grill_temp", temp_value)
	else
		cached_value = temperature_service.get_cached_temperature_value(device, "grill_temp", nil)
		temp_value = cached_value
	end

	local display_value, numeric_value =
		temperature_service.format_temperature_display(temp_value, is_valid, cached_value)

	-- If both current and cached values are invalid/nil, emit disconnected display
	if (not is_valid) and (cached_value == nil or cached_value == config.CONSTANTS.OFF_DISPLAY_TEMP) then
		display_value = config.CONSTANTS.DISCONNECT_DISPLAY
		numeric_value = config.CONSTANTS.OFF_DISPLAY_TEMP
	end

	-- Emit grill temperature events (centralized for clarity)
	local function emit_grill_temp_events(display_val, numeric_val)
		local standard_grill = device.profile.components[config.COMPONENTS.GRILL]
		device:emit_event(custom_caps.grillTemp.currentTemp({ value = display_val, unit = unit }))
		device:emit_component_event(
			standard_grill,
			capabilities.temperatureMeasurement.temperature({ value = numeric_val, unit = unit })
		)
	end

	emit_grill_temp_events(display_value, numeric_value)
end

--- Update target temperature with separate display logic
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @param unit string Temperature unit
local function update_target_temperature(device, status, unit)
	local target_display_value
	local setpoint_temp_value

	if temperature_service.is_valid_temperature(status.set_temp, unit) then
		local is_grill_really_off = (not device_status_service.is_grill_on(device, status))
			and (status.set_temp == config.CONSTANTS.MIN_TEMP_F)

		if is_grill_really_off then
			target_display_value = config.CONSTANTS.DISCONNECT_DISPLAY
			setpoint_temp_value = config.CONSTANTS.MIN_TEMP_F
			device:set_field("should_clear_cache", true, { persist = false })
		else
			target_display_value = string.format("%.0f", status.set_temp)
			setpoint_temp_value = status.set_temp
			temperature_service.store_temperature_value(device, "set_temp", status.set_temp)
			device:set_field("should_clear_cache", false, { persist = false })
		end
	else
		local cached_value = temperature_service.get_cached_temperature_value(device, "set_temp", nil)
		if cached_value ~= nil and cached_value > config.CONSTANTS.OFF_DISPLAY_TEMP then
			target_display_value = string.format("%.0f", cached_value)
		else
			target_display_value = config.CONSTANTS.DISCONNECT_DISPLAY
		end
		setpoint_temp_value = config.CONSTANTS.MIN_TEMP_F
	end

	device:emit_event(custom_caps.grillTemp.targetTemp({ value = target_display_value, unit = unit }))

	local standard_grill = device.profile.components[config.COMPONENTS.GRILL]
	device:emit_component_event(
		standard_grill,
		capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = setpoint_temp_value, unit = unit })
	)
end

--- Update system component states
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @param unit string Temperature unit
local function update_system_states(device, status, unit)
	-- Update pellet system states
	device:emit_event(custom_caps.pelletStatus.fanState({ value = status.fan_state and "ON" or "OFF" }))
	device:emit_event(custom_caps.pelletStatus.augerState({ value = status.motor_state and "ON" or "OFF" }))
	device:emit_event(custom_caps.pelletStatus.ignitorState({ value = status.hot_state and "ON" or "OFF" }))

	-- Update control states
	device:emit_event(custom_caps.lightControl.lightState({ value = status.light_state and "ON" or "OFF" }))

	local new_prime_state = status.prime_state and "ON" or "OFF"
	device:emit_event(custom_caps.primeControl.primeState({ value = new_prime_state }))

	-- Cancel prime timer if grill prime is off
	if not status.prime_state then
		local timer_ref = device:get_field("prime_auto_off_timer")
		if timer_ref then
			timer_ref:cancel()
			device:set_field("prime_auto_off_timer", nil)
			log.info("Cancelled prime auto-off timer - grill prime state is OFF")
		end
	end

	device:emit_event(custom_caps.temperatureUnit.unit({ value = unit }))

	-- Update main power switch state
	local standard_grill = device.profile.components[config.COMPONENTS.GRILL]
	local power_state = status.module_on and "on" or "off"

	temperature_service.store_temperature_value(device, "power_state", power_state)

	if status.module_on then
		device:emit_component_event(standard_grill, capabilities.switch.switch.on())
	else
		device:emit_component_event(standard_grill, capabilities.switch.switch.off())
	end
end

--- Update power meter capability
-- @param device SmartThings device object
-- @param status table Current grill status data
local function update_power_meter(device, status)
	local estimated_watts = calculate_power_consumption(device, status)

	-- Check if device supports powerMeter capability
	local has_power_meter = false
	for _, capability in ipairs(device.profile.capabilities or {}) do
		if capability.id == "powerMeter" then
			has_power_meter = true
			break
		end
	end

	if has_power_meter then
		device:emit_event(capabilities.powerMeter.power({ value = estimated_watts, unit = "W" }))
		log.info(string.format("Power meter set: %.1fW", estimated_watts))
	else
		log.info(string.format("Power consumption calculated: %.1fW", estimated_watts))
	end
end

--- Unified function to update panic alarm and status message
-- @param device SmartThings device object
-- @param status_message string Status message to display
-- @param force_panic_clear boolean Optional, force panic alarm to "clear" regardless of panic state
local function update_panic_alarm_and_status(device, status_message, force_panic_clear)
	local error_component = device.profile.components[config.COMPONENTS.ERROR]

	if error_component then
		local alarm_state
		if force_panic_clear then
			alarm_state = "clear"
		else
			local panic_state = panic_manager.is_in_panic_state(device)
			alarm_state = panic_state and "panic" or "clear"
		end
		device:emit_component_event(error_component, capabilities.panicAlarm.panicAlarm({ value = alarm_state }))
	end

	device:emit_event(custom_caps.grillStatus.lastMessage(status_message))
end

-- ============================================================================
-- PUBLIC INTERFACE
-- ============================================================================

--- Update comprehensive device status from grill status data
-- @param device SmartThings device object
-- @param status table Current grill status data
function device_status_service.update_device_status(device, status)
	-- Only mark device online if we have fresh, valid status data
	-- Do NOT automatically mark online just because this function is called
	-- The caller (health_monitor, refresh_service, etc.) should handle online/offline state

	-- Only clear panic if device is currently in panic state and is now online (is_connected)
	if panic_manager.is_in_panic_state(device) and device:get_field("is_connected") then
		panic_manager.clear_panic_on_reconnect(device, true)
	end

	-- Determine temperature unit and store for device reference
	local unit = status.is_fahrenheit and "F" or "C"
	device:set_field("unit", unit, { persist = true })

	-- Extract temperature offset preferences with safe defaults
	local offsets = {
		grill = device.preferences.grillOffset or config.CONSTANTS.DEFAULT_OFFSET,
		probe1 = device.preferences.probe1Offset or config.CONSTANTS.DEFAULT_OFFSET,
		probe2 = device.preferences.probe2Offset or config.CONSTANTS.DEFAULT_OFFSET,
		probe3 = device.preferences.probe3Offset or config.CONSTANTS.DEFAULT_OFFSET,
		probe4 = device.preferences.probe4Offset or config.CONSTANTS.DEFAULT_OFFSET,
	}

	-- Track grill runtime for operational state detection
	local grill_on = device_status_service.is_grill_on(device, status)
	track_grill_runtime(device, grill_on)
	-- Always update last_active_time if grill is ON (for panic logic)
	panic_manager.update_last_active_time_if_on(device, status)

	-- Update all device components
	update_temperature_ranges(device, unit)
	update_grill_temperature(device, status, unit, offsets.grill)
	update_target_temperature(device, status, unit)

	-- Update probe temperatures
	update_all_probes(device, status, offsets, unit)

	update_system_states(device, status, unit)
	update_power_meter(device, status)

	-- Update error states and communication status
	local status_message = get_communication_status(device, status, false, nil)
	local has_error = not string.find(collect_errors(status), "No Errors", 1, true)
	local panic_state = panic_manager.is_in_panic_state(device)

	-- Use unified function, force panic if there are errors OR panic state
	local force_panic = has_error or panic_state
	update_panic_alarm_and_status(device, status_message, not force_panic)

	-- Clear cache if grill is definitively off
	local should_clear = device:get_field("should_clear_cache")
	if should_clear then
		temperature_service.clear_temperature_cache(device)
		device:set_field("should_clear_cache", false, { persist = false })
	end

	-- Update virtual devices with the new status data
	local virtual_device_manager = require("virtual_device_manager")
	virtual_device_manager.update_virtual_devices(device, status)
end

--- Update device status for authentication failure
-- @param device SmartThings device object
-- @param grill_is_on boolean Whether the grill is currently on
function device_status_service.update_auth_failure_status(device, grill_is_on)
	-- Use get_communication_status with auth failure context
	local auth_failure_context = { grill_is_on = grill_is_on }
	local status_message = get_communication_status(device, nil, true, auth_failure_context)

	if grill_is_on then
		-- Grill is ON - trigger panic state using panic_manager
		panic_manager.handle_offline_panic_state(device)
		-- Use update_offline_status to emit proper panic alarm state and status message
		device_status_service.update_offline_status(device)
	else
		-- Grill is OFF - show status message but no panic
		update_panic_alarm_and_status(device, status_message, true) -- force clear

		log.debug(
			string.format("Auth failure status set: grill_on=%s, message=%s", tostring(grill_is_on), status_message)
		)
	end
end

--- Update device status when offline (panic handling)
-- @param device SmartThings device object
function device_status_service.update_offline_status(device)
	local status_message = get_communication_status(device, nil, true)
	update_panic_alarm_and_status(device, status_message)

	log.debug(string.format("Offline status set: message=%s", status_message))
end

--- Set status message on device
-- @param device SmartThings device object
-- @param message string Status message to display
function device_status_service.set_status_message(device, message)
	device:emit_event(custom_caps.grillStatus.lastMessage(message))
end

--- Calculate estimated power consumption (public interface)
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @return number Estimated power consumption in watts
function device_status_service.calculate_power_consumption(device, status)
	return calculate_power_consumption(device, status)
end

return device_status_service