--[[
  Capability Handlers for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module handles all SmartThings capability commands and coordinates device state updates.
  It serves as the main interface between SmartThings commands and the grill's functionality,
  providing comprehensive control over temperature, lighting, priming, and system operations.

  Features:
  - Temperature control with setpoint snapping
  - Light and prime control with grill state validation
  - Virtual device command routing and state synchronization
  - Error handling and user feedback
  - Device refresh and status management
  - Support for both Fahrenheit and Celsius units
  - Session-based heating state tracking
  - Virtual device updates for responsive UI
  - Delegates operations to specialized service modules
  - Immediate UI feedback with scheduled background refresh
  - Handles both main device and virtual device commands

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local capabilities = require("st.capabilities")
local log = require("log")
local custom_caps = require("custom_capabilities")
local config = require("config")

-- Import service modules
local device_status_service = require("device_status_service")
local command_service = require("command_service")
local virtual_device_manager = require("virtual_device_manager")
local refresh_service = require("refresh_service")
local language = config.STATUS_MESSAGES

local handlers = {}

-- Helper to route commands to virtual handler or main handler depending on device type
local function route_or_call(device, virtual_handler, main_handler, driver, device_arg, command)
	if device.parent_assigned_child_key then
		-- Device is virtual - call virtual handler
		return virtual_handler(driver, device_arg, command)
	else
		-- Device is main - call main handler
		return main_handler(driver, device_arg, command)
	end
end

-- ============================================================================
-- MAIN DEVICE STATUS UPDATE
-- ============================================================================

--- Update all device capabilities from grill status data
-- This is the main orchestration function that coordinates all device state updates
-- @param device SmartThings device object
-- @param status table Current grill status data from network_utils.get_status()
function handlers.update_device_from_status(device, status)
	refresh_service.refresh_from_status(device, status)
end

--- Handle refresh requests to get current grill status and update all capabilities
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param command table Refresh command details
function handlers.refresh_handler(driver, device, command)
	refresh_service.refresh_device(device, driver, command)
end

-- ============================================================================
-- COMMAND HANDLERS
-- ============================================================================

--- Handle power switch commands (off) with state synchronization
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param command table Switch command ("off")
function handlers.switch_handler(driver, device, command)
	log.info(string.format("Switch command: %s for device: %s", command.command, device.id))

	local state = command.command == "on" and "on" or "off"
	local success = command_service.send_power_command(device, state)

	if success then
		log.info("Power command sent successfully")
		-- Schedule refresh after command
		command_service.schedule_refresh(device, driver, command)
	else
		log.error("Failed to send power command")
		-- Don't override the specific error message from require_grill_on
		-- The command_service already set the appropriate error message
	end
end

--- Handle thermostat setpoint commands with temperature snapping and validation
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param command table Setpoint command with temperature in Celsius from SmartThings
function handlers.thermostat_setpoint_handler(driver, device, command)
	local requested_celsius_setpoint = command.args.setpoint

	log.info(string.format("Thermostat setpoint command: %s°C for device: %s", requested_celsius_setpoint, device.id))

	local success = command_service.send_temperature_command(device, requested_celsius_setpoint)

	if success then
		log.info("Temperature setpoint sent successfully")
		-- Schedule refresh after command
		command_service.schedule_refresh(device, driver, command)
	else
		log.error("Failed to send temperature command")
		-- Don't override the specific error message from require_grill_on
		-- The command_service already set the appropriate error message
	end
end

--- Handle light control commands and update both main and virtual device states
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param command table Light command with state argument
function handlers.light_control_handler(driver, device, command)
	log.info(string.format("Light control command for device: %s", device.id))

	local state = command.args and command.args.state
	if not state then
		log.error("No state argument provided in light command")
		device_status_service.set_status_message(device, language.invalid_light_command)
		return
	end

	local success = command_service.send_light_command(device, state)

	if success then
		log.info("Light command sent successfully")
		-- Schedule refresh after command
		command_service.schedule_refresh(device, driver, command)
	else
		log.error("Failed to send light command")
		-- Don't override the specific error message from require_grill_on
		-- The command_service already set the appropriate error message
	end
end

--- Handle prime control commands and update both main and virtual device states
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param command table Prime command with state argument
function handlers.prime_control_handler(driver, device, command)
	log.info(string.format("Prime control command for device: %s", device.id))

	local state = command.args and command.args.state
	if not state then
		log.error("No state argument provided in prime command")
		device_status_service.set_status_message(device, language.invalid_prime_command)
		return
	end

	local success = command_service.send_prime_command(device, state)

	if success then
		log.info("Prime command sent successfully")
		-- Schedule refresh after command
		command_service.schedule_refresh(device, driver, command)
	else
		log.error("Failed to send prime command")
		-- Don't override the specific error message from require_grill_on
		-- The command_service already set the appropriate error message
	end
end

--- Handle temperature unit change commands with grill state validation
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param command table Unit command with state argument ("F" or "C")
function handlers.temperature_unit_handler(driver, device, command)
	log.info(string.format("Temperature unit command for device: %s", device.id))

	local unit_arg = command.args and command.args.state
	if not unit_arg then
		log.error("No state argument provided in unit command")
		device_status_service.set_status_message(device, language.invalid_unit_command)
		return
	end

	local success = command_service.send_unit_command(device, unit_arg)

	if success then
		log.info("Unit command sent successfully")
		-- Schedule refresh after command
		command_service.schedule_refresh(device, driver, command)
	else
		log.error("Failed to send unit command")
		-- Don't override the specific error message from require_grill_on
		-- The command_service already set the appropriate error message
	end
end

-- ============================================================================
-- VIRTUAL DEVICE COMMAND HANDLERS
-- ============================================================================

--- Handle virtual device switch commands
-- @param driver SmartThings driver object
-- @param device SmartThings device object (virtual device)
-- @param command table Switch command with on/off state
function handlers.virtual_switch_handler(driver, device, command)
	local parent_key = device.parent_assigned_child_key or ""
	local parent_device = device:get_parent_device()

	if not parent_device then
		log.error(string.format("No parent device found for virtual device: %s", parent_key))
		return
	end

	log.info(string.format("Virtual switch command for %s: %s", parent_key, command.command))

	-- Route commands based on virtual device type
	if parent_key == "virtual-light" then
		local light_command = {
			args = {
				state = command.command == "on" and "ON" or "OFF",
			},
		}
		handlers.light_control_handler(driver, parent_device, light_command)
	elseif parent_key == "virtual-prime" then
		local prime_command = {
			args = {
				state = command.command == "on" and "ON" or "OFF",
			},
		}
		handlers.prime_control_handler(driver, parent_device, prime_command)
	elseif parent_key == "virtual-main" then
		handlers.switch_handler(driver, parent_device, command)
	elseif parent_key == "virtual-at-temp" or parent_key == "virtual-error" then
		-- These are indicator-only switches - do nothing
		log.debug(string.format("%s switch pressed - indicator only, no action taken", parent_key))
	else
		log.warn(string.format("Unknown virtual device type: %s", parent_key))
	end
end

--- Handle virtual device thermostat setpoint commands
-- @param driver SmartThings driver object
-- @param device SmartThings device object (virtual device)
-- @param command table Setpoint command with temperature value
function handlers.virtual_thermostat_handler(driver, device, command)
	local parent_key = device.parent_assigned_child_key or ""
	local parent_device = device:get_parent_device()

	if not parent_device then
		log.error(string.format("No parent device found for virtual device: %s", parent_key))
		return
	end

	log.info(
		string.format("Virtual thermostat command for %s: setpoint=%s", parent_key, tostring(command.args.setpoint))
	)

	-- Route thermostat commands to main grill thermostat handler
	if parent_key == "virtual-main" then
		handlers.thermostat_setpoint_handler(driver, parent_device, command)
	else
		log.warn(string.format("Thermostat command not supported for virtual device type: %s", parent_key))
	end
end

-- ============================================================================
-- VIRTUAL DEVICE UPDATE FUNCTION
-- ============================================================================

--- Update virtual devices with real grill data (delegated to virtual_device_manager)
-- @param device SmartThings device object (main device)
-- @param status table Current grill status data (optional)
function handlers.update_virtual_devices(device, status)
	virtual_device_manager.update_virtual_devices(device, status)
end

-- ============================================================================
-- HELPER FUNCTIONS FOR EXTERNAL MODULES
-- ============================================================================

--- Helper function to check if grill is on from status data (for external modules)
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @return boolean True if grill is powered on
function handlers.is_grill_on_from_status(device, status)
	return device_status_service.is_grill_on(device, status)
end

--- Update device error states and panic status (used when offline)
-- @param device SmartThings device object
function handlers.update_device_panic_status(device)
	device_status_service.update_offline_status(device)
end

-- ============================================================================
-- CAPABILITY HANDLER MAPPING
-- ============================================================================

--- Map SmartThings capabilities to handler functions
handlers.capability_handlers = {
	-- Standard refresh capability for manual device updates
	[capabilities.refresh.ID] = {
		[capabilities.refresh.commands.refresh.NAME] = handlers.refresh_handler,
	},

	-- Power meter capability (read-only, calculated automatically)
	[capabilities.powerMeter.ID] = {
		-- No commands needed - power is calculated and emitted automatically
	},

	-- Standard switch capability for power control (main device and virtual devices)
	[capabilities.switch.ID] = {
		[capabilities.switch.commands.on.NAME] = function(driver, device, command)
			route_or_call(device, handlers.virtual_switch_handler, handlers.switch_handler, driver, device, command)
		end,
		[capabilities.switch.commands.off.NAME] = function(driver, device, command)
			route_or_call(device, handlers.virtual_switch_handler, handlers.switch_handler, driver, device, command)
		end,
	},

	-- Thermostat heating setpoint capability
	[capabilities.thermostatHeatingSetpoint.ID] = {
		[capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = function(driver, device, command)
			route_or_call(
				device,
				handlers.virtual_thermostat_handler,
				handlers.thermostat_setpoint_handler,
				driver,
				device,
				command
			)
		end,
	},

	-- Custom light control capability
	[custom_caps.lightControl.ID] = {
		[custom_caps.lightControl.commands.setLightState.NAME] = handlers.light_control_handler,
	},

	-- Custom prime control capability
	[custom_caps.primeControl.ID] = {
		[custom_caps.primeControl.commands.setPrimeState.NAME] = handlers.prime_control_handler,
	},

	-- Custom temperature unit selection capability
	[custom_caps.temperatureUnit.ID] = {
		[custom_caps.temperatureUnit.commands.setTemperatureUnit.NAME] = handlers.temperature_unit_handler,
	},
}

return handlers