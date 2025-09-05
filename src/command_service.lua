--[[
  Command Service for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module handles all command processing, validation, and execution for grill control operations.
  It provides centralized command management with comprehensive validation, immediate UI feedback,
  and virtual device synchronization to ensure responsive user experience and reliable operation.

  Features:
  - Command validation and preprocessing
  - Grill state requirement validation
  - Immediate UI feedback
  - Virtual device state synchronization
  - Temperature setpoint snapping
  - Prime timer management
  - Network failure handling
  - Session tracking reset
  - Power control with virtual device updates
  - Temperature setpoint with validation and snapping
  - Light control with grill-on requirement
  - Prime control with auto-off timer and status updates
  - Temperature unit switching with immediate persistence

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local capabilities = require("st.capabilities")
local log = require("log")
local config = require("config")
local custom_caps = require("custom_capabilities")

-- Import service modules
local network_utils = require("network_utils")
local temperature_service = require("temperature_service")
local device_status_service = require("device_status_service")
local refresh_service = require("refresh_service")
local language = config.STATUS_MESSAGES

local command_service = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Validate that grill is powered on before executing operations
-- @param device SmartThings device object
-- @param operation_name string Human-readable name of the operation
-- @return boolean True if grill is on and operation can proceed
local function require_grill_on(device, operation_name)
	local ip_preference = device.preferences and device.preferences.ipAddress

	if not device_status_service.is_grill_on(device) and ip_preference ~= config.CONSTANTS.DEBUG_IP_ADDRESS then
		log.error(string.format("Cannot %s with grill off", operation_name))
		device_status_service.set_status_message(device, operation_name .. language.grill_off_suffix)
		return false
	end
	return true
end

--- Schedule a device refresh after a delay
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param command table Command that triggered the refresh
function command_service.schedule_refresh(device, driver, command)
	refresh_service.schedule_refresh(device, driver, command)
end

-- Helper: Centralize network failure handling for command functions
local function handle_network_outcome(success, device, message)
	if success then
		return true
	end
	-- Preserve original behavior: set status message and return false
	if device and message then
		device_status_service.set_status_message(device, message)
	end
	return false
end

--- Update virtual device state immediately for responsive UI
-- @param device SmartThings device object (main device)
-- @param virtual_key string Virtual device key
-- @param state string New state ("on"/"off")
local function update_virtual_device_immediately(device, virtual_key, state)
	local driver = device.driver
	if not driver then
		return
	end

	-- Get child devices using the correct SmartThings Edge API
	for _, virtual_device in ipairs(driver:get_devices()) do
		if virtual_device.parent_device_id == device.id and virtual_device.parent_assigned_child_key == virtual_key then
			-- Emit the switch event directly for immediate UI feedback.
			-- This mirrors the standard component event flow but avoids waiting for a refresh.
			virtual_device:emit_event(capabilities.switch.switch[state]())
			log.debug(string.format("Set %s immediately: %s", virtual_key, state))
			break
		end
	end
end

-- ============================================================================
-- POWER CONTROL COMMANDS
-- ============================================================================

--- Send power control command with immediate UI feedback
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param state string Power state ("off")
-- @return boolean True if command was sent successfully
function command_service.send_power_command(device, state)
	-- SAFETY: For safety reasons, the grill must be manually powered on at the device
	if not require_grill_on(device, "Grill Power On") then
		return false
	else
		local success = network_utils.send_command(device, "set_power", state)

		if success then
			-- Update switch state immediately for responsive UI feedback
			local standard_grill = device.profile.components[config.COMPONENTS.GRILL]
			if state == "on" then
				device:emit_component_event(standard_grill, capabilities.switch.switch.on())
			else
				device:emit_component_event(standard_grill, capabilities.switch.switch.off())
			end

			-- Update virtual main device state immediately
			if device.preferences.enableVirtualGrillMain then
				update_virtual_device_immediately(device, "virtual-main", state)
			end

			return true
		else
			-- Network failure - set generic error message (centralized)
			return handle_network_outcome(false, device, "Failed to change power state")
		end
	end
end

-- ============================================================================
-- TEMPERATURE CONTROL COMMANDS
-- ============================================================================

--- Send temperature setpoint command with validation and snapping
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param requested_celsius_setpoint number Temperature in Celsius from SmartThings
-- @return boolean True if command was sent successfully
function command_service.send_temperature_command(device, requested_celsius_setpoint)
	local device_display_unit = device:get_field("unit") or config.CONSTANTS.DEFAULT_UNIT

	-- Ensure grill is powered on
	if not require_grill_on(device, "Set temp") then
		-- Reset UI to minimum temperature when command fails
		local min_temp = device_display_unit == "F" and config.CONSTANTS.MIN_TEMP_F or config.CONSTANTS.MIN_TEMP_C
		device:emit_event(
			custom_caps.grillTemp.targetTemp({ value = config.CONSTANTS.DISCONNECT_DISPLAY, unit = device_display_unit })
		)

		local standard_grill = device.profile.components[config.COMPONENTS.GRILL]
		device:emit_component_event(
			standard_grill,
			capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = min_temp, unit = device_display_unit })
		)

		return false
	end

	-- Validate the initial requested temperature (always in Celsius from SmartThings)
	if not temperature_service.is_valid_setpoint(requested_celsius_setpoint, "C") then
		local temp_range = config.get_temperature_range("C")
		log.error(
			string.format(
				"Invalid input temperature setpoint: %s°C. Range: %s-%s°C",
				requested_celsius_setpoint,
				temp_range.min,
				temp_range.max
			)
		)
		device_status_service.set_status_message(device, language.invalid_input_temperature)
		return false
	end

	local snapped_temp_for_display
	local temp_to_send_to_grill

	if device_display_unit == "C" then
		-- Grill is displaying Celsius - snap directly in Celsius
		snapped_temp_for_display = temperature_service.snap_to_approved_setpoint(requested_celsius_setpoint, "C")
		temp_to_send_to_grill = snapped_temp_for_display
		log.debug(
			string.format(
				"Snapped input %s°C to %s°C for Celsius grill",
				requested_celsius_setpoint,
				snapped_temp_for_display
			)
		)
	else
		-- Grill is displaying Fahrenheit - convert to F, snap, then send
		local requested_fahrenheit_for_snapping = temperature_service.celsius_to_fahrenheit(requested_celsius_setpoint)
		snapped_temp_for_display = temperature_service.snap_to_approved_setpoint(requested_fahrenheit_for_snapping, "F")
		temp_to_send_to_grill = snapped_temp_for_display
		log.debug(
			string.format(
				"Converted %s°C to %s°F, snapped to %s°F for Fahrenheit grill",
				requested_celsius_setpoint,
				requested_fahrenheit_for_snapping,
				snapped_temp_for_display
			)
		)
	end

	-- Validate final temperature (after snapping/conversion)
	if not temperature_service.is_valid_setpoint(temp_to_send_to_grill, device_display_unit) then
		local temp_range = config.get_temperature_range(device_display_unit)
		log.error(
			string.format(
				"Invalid temperature setpoint after snapping: %s°%s. Range: %s-%s°%s",
				temp_to_send_to_grill,
				device_display_unit,
				temp_range.min,
				temp_range.max,
				device_display_unit
			)
		)
		device_status_service.set_status_message(device, language.invalid_temperature_range_after_snapping)
		return false
	end

	log.debug(string.format("Final temperature to send: %s°%s", temp_to_send_to_grill, device_display_unit))

	local success = network_utils.send_command(device, "set_temperature", temp_to_send_to_grill)

	if success then
		log.info(
			string.format(
				"Temperature setpoint sent successfully: %s°%s",
				snapped_temp_for_display,
				device_display_unit
			)
		)

		-- Check if target temperature changed significantly - reset session tracking if so
		local cached_target = temperature_service.get_cached_temperature_value(device, "set_temp", 0)
		if cached_target then
			local unit = temperature_service.get_device_unit(device)
			local threshold = config.get_temp_reset_threshold(unit)
			if math.abs(snapped_temp_for_display - cached_target) >= threshold then
				temperature_service.clear_session_tracking(device)
				log.debug(
					string.format(
						"Target temp changed significantly (%d to %d) - reset session tracking",
						cached_target,
						snapped_temp_for_display
					)
				)
			end
		end

		-- Update UI immediately with snapped temperature for responsive feedback
		device:emit_event(custom_caps.grillTemp.targetTemp({
			value = string.format("%.0f", snapped_temp_for_display),
			unit = device_display_unit,
		}))

		local standard_grill = device.profile.components[config.COMPONENTS.GRILL]
		device:emit_component_event(
			standard_grill,
			capabilities.thermostatHeatingSetpoint.heatingSetpoint({
				value = snapped_temp_for_display,
				unit = device_display_unit,
			})
		)

		return true
	else
		-- Network failure - set generic error message
		device_status_service.set_status_message(device, language.failed_to_set_temp)
		return false
	end
end

-- ============================================================================
-- LIGHT CONTROL COMMANDS
-- ============================================================================

--- Send light control command with immediate feedback
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param state string Light state ("ON" or "OFF")
-- @return boolean True if command was sent successfully
function command_service.send_light_command(device, state)
	-- Light control requires grill to be powered on
	if not require_grill_on(device, "Light control") then
		return false
	end

	-- Convert SmartThings format to grill API format
	local api_state = (state == "ON") and "on" or "off"
	log.info(string.format("Setting light to: %s", api_state))

	local success = network_utils.send_command(device, "set_light", api_state)

	if success then
		-- Update light state immediately for responsive UI feedback
		device:emit_event(custom_caps.lightControl.lightState({ value = state }))

		-- Update virtual light device state immediately
		if device.preferences.enableVirtualGrillLight then
			local virtual_light_state = (state == "ON") and "on" or "off"
			update_virtual_device_immediately(device, "virtual-light", virtual_light_state)
		end

		return true
	else
		-- Network failure - set generic error message
		device_status_service.set_status_message(device, language.failed_to_control_light)
		return false
	end
end

-- ============================================================================
-- PRIME CONTROL COMMANDS
-- ============================================================================

--- Send prime control command with timer management
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param state string Prime state ("ON" or "OFF")
-- @return boolean True if command was sent successfully
function command_service.send_prime_command(device, state)
	-- Prime control requires grill to be powered on
	if not require_grill_on(device, "Prime") then
		return false
	end

	-- Convert SmartThings format to grill API format
	local api_state = (state == "ON") and "on" or "off"
	log.info(string.format("Setting prime to: %s", api_state))

	local success = network_utils.send_command(device, "set_prime", api_state)

	if success then
		-- Update prime state immediately for responsive UI feedback
		device:emit_event(custom_caps.primeControl.primeState({ value = state }))

		-- Update virtual prime device state immediately
		if device.preferences.enableVirtualGrillPrime then
			local virtual_prime_state = (state == "ON") and "on" or "off"
			update_virtual_device_immediately(device, "virtual-prime", virtual_prime_state)
		end

		-- Handle prime timer management
		if state == "ON" then
			-- Set up auto-off timer using device thread
			local timer_ref = device.thread:call_with_delay(config.CONSTANTS.PRIME_TIMEOUT, function()
				log.info(string.format("Auto-turning off prime after %d seconds", config.CONSTANTS.PRIME_TIMEOUT))
				network_utils.send_command(device, "set_prime", "off")
			end)
			device:set_field("prime_auto_off_timer", timer_ref)

			-- Update status to show priming
			device_status_service.set_status_message(device, language.connected_grill_priming)
		else
			-- Cancel auto-off timer if manually turning off
			local timer_ref = device:get_field("prime_auto_off_timer")
			if timer_ref then
				timer_ref:cancel()
				device:set_field("prime_auto_off_timer", nil)
			end

			-- Update status to show prime off with auto-clear
			device_status_service.set_status_message(device, language.connected_grill_prime_off)

			device.thread:call_with_delay(3, function()
				local current_status = device:get_latest_state("main", custom_caps.grillStatus.ID, "lastMessage")
				if current_status and current_status.value == language.connected_grill_prime_off then
					device_status_service.set_status_message(device, language.connected)
				end
			end)
		end

		return true
	else
		-- Network failure - set generic error message
		device_status_service.set_status_message(device, language.failed_to_control_prime)
		return false
	end
end

-- ============================================================================
-- UNIT CONTROL COMMANDS
-- ============================================================================

--- Send temperature unit change command
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param unit_arg string Unit argument ("F" or "C")
-- @return boolean True if command was sent successfully
function command_service.send_unit_command(device, unit_arg)
	-- Unit changes require grill to be powered on
	if not require_grill_on(device, "Unit select") then
		return false
	end

	-- Convert SmartThings format to grill API format
	local api_unit = (unit_arg == "C") and "celsius" or "fahrenheit"
	log.info(string.format("Setting temperature unit to: %s (from %s)", api_unit, unit_arg))

	local success = network_utils.send_command(device, "set_unit", api_unit)

	if success then
		-- Update unit display immediately and persist the setting
		device:emit_event(custom_caps.temperatureUnit.unit(unit_arg))
		device:set_field("unit", unit_arg, { persist = true })

		return true
	else
		-- Network failure - set generic error message
		device_status_service.set_status_message(device, language.failed_to_change_temperature_unit)
		return false
	end
end

return command_service