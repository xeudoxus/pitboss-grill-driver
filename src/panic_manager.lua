--[[
  Panic Manager Service for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  Manages panic state detection and handling when communication is lost
  with an active grill. Provides safety monitoring to alert users when
  a hot grill becomes unreachable.

  Features:
  - Active grill monitoring with last-active tracking
  - Panic state detection when hot grill goes offline
  - Automatic panic clearing when communication resumes
  - Grace period handling for temporary network issues
--]]

local capabilities = require("st.capabilities")
local log = require("log")
local config = require("config")
local language = config.STATUS_MESSAGES

local panic_manager = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get current timestamp for timing operations
-- @return number Current Unix timestamp
local function get_current_time()
	return os.time()
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Check if grill is currently powered on based on status data
-- @param device SmartThings device object
-- @param status table Current grill status data
-- @return boolean True if grill is powered on
local function is_grill_on_from_status(device, status)
	if not status then
		-- Fallback: when no live status payload is available, read the last known
		-- switch state from the grill component. This provides a best-effort
		-- indicator for panic logic without requiring a network call.
		local switch_state =
			device:get_latest_state(config.COMPONENTS.GRILL, capabilities.switch.ID, capabilities.switch.switch.NAME)
		return (switch_state == "on")
	end

	-- If all three are false, grill is definitely off
	if not status.motor_state and not status.hot_state and not status.module_on then
		return false
	end

	-- If any is true, grill is on
	return status.motor_state or status.hot_state or status.module_on
end

-- ============================================================================
-- LAST ACTIVE TIME TRACKING
-- ============================================================================

--- Update the last active time when grill is detected as on
-- @param device SmartThings device object
function panic_manager.update_last_active_time(device)
	local current_time = get_current_time()
	device:set_field("last_active_time", current_time, { persist = true })
	log.debug(string.format("Last active time set to: %d", current_time))
end

--- Update last active time if grill is currently on (helper function)
-- @param device SmartThings device object
-- @param status table Current grill status data
function panic_manager.update_last_active_time_if_on(device, status)
	if is_grill_on_from_status(device, status) then
		panic_manager.update_last_active_time(device)
	end
end

--- Check if grill was recently active (within panic timeout period)
-- @param device SmartThings device object
-- @return boolean True if grill was on within the panic timeout
local function was_grill_recently_active(device)
	local last_active_time = device:get_field("last_active_time") or 0
	local current_time = get_current_time()

	-- Handle timestamp overflow/underflow issues
	if last_active_time <= 0 then
		return false
	end

	local time_since_active = current_time - last_active_time

	-- Check for negative time differences (clock issues)
	if time_since_active < 0 then
		device:set_field("last_active_time", current_time, { persist = true })
		return false
	end
	return time_since_active <= config.CONSTANTS.PANIC_TIMEOUT
end

-- ============================================================================
-- PANIC STATE MANAGEMENT
-- ============================================================================

--- Update panic display in device status and error component
-- @param device SmartThings device object
local function update_panic_display(device)
	local panic_state = device:get_field("panic_state") or false
	local error_component = device.profile.components[config.COMPONENTS.ERROR]

	if error_component then
		local alarm_state = panic_state and "panic" or "clear"
		device:emit_component_event(error_component, capabilities.panicAlarm.panicAlarm({ value = alarm_state }))
	end

	-- Update status message for panic state
	if panic_state then
		local panic_message = panic_manager.get_panic_status_message(device)
		if panic_message then
			local custom_caps = require("custom_capabilities")
			device:emit_event(custom_caps.grillStatus.lastMessage(panic_message))
		end
	end

	-- Status message will be handled by the main status update functions
	log.debug(string.format("Panic display set: panic_state=%s", tostring(panic_state)))
end

--- Handle panic state transitions and updates
-- @param device SmartThings device object
-- @param was_recently_active boolean True if grill was recently active
-- @param current_panic_state boolean Current panic state
local function handle_panic_state_transition(device, was_recently_active, current_panic_state)
	if was_recently_active and not current_panic_state then
		-- PANIC CONDITION: Grill was recently active but we lost communication
		log.error("PANIC: Lost communication with recently active grill!")
		device:set_field("panic_state", true, { persist = true })
		update_panic_display(device)
	elseif not was_recently_active and current_panic_state then
		-- Clear panic if enough time has passed
		log.info("Clearing panic state - grill no longer recently active")
		device:set_field("panic_state", false, { persist = true })
		update_panic_display(device)
	elseif current_panic_state then
		-- Maintain panic state display while still in panic mode
		update_panic_display(device)
	else
		-- Device is offline but not in panic state - update status to show disconnected
		update_panic_display(device)
	end
end

--- Handle panic state management when device goes offline
-- @param device SmartThings device object
function panic_manager.handle_offline_panic_state(device)
	local was_recently_active = was_grill_recently_active(device)
	local current_panic_state = device:get_field("panic_state") or false

	handle_panic_state_transition(device, was_recently_active, current_panic_state)
end

--- Clear panic state when device comes back online
-- @param device SmartThings device object
-- @param was_offline boolean True if device was previously offline
function panic_manager.clear_panic_on_reconnect(device, was_offline)
	if was_offline then
		local current_panic_state = device:get_field("panic_state") or false
		if current_panic_state then
			log.info("Clearing panic state - device reconnected successfully")
			device:set_field("panic_state", false, { persist = true })
			-- Status update will handle clearing the panic display
		end
	end
end

--- Clear panic state immediately (used after successful rediscovery)
-- @param device SmartThings device object
function panic_manager.clear_panic_state(device)
	local current_panic_state = device:get_field("panic_state") or false
	if current_panic_state then
		log.info("Clearing panic state - device reconnected")
		device:set_field("panic_state", false, { persist = true })

		local error_component = device.profile.components[config.COMPONENTS.ERROR]
		if error_component then
			device:emit_component_event(error_component, capabilities.panicAlarm.panicAlarm({ value = "clear" }))
		end
	end
end

--- Check if device is currently in panic state
-- @param device SmartThings device object
-- @return boolean True if device is in panic state
function panic_manager.is_in_panic_state(device)
	return device:get_field("panic_state") or false
end

--- Get panic status message for display
-- @param device SmartThings device object
-- @return string|nil Panic status message or nil if not in panic
function panic_manager.get_panic_status_message(device)
	local panic_state = device:get_field("panic_state") or false
	if panic_state then
		return language.panic_lost_connection_grill_on
	end
	return nil
end

--- Clean up panic-related fields when device is removed
-- @param device SmartThings device object
function panic_manager.cleanup_panic_resources(device)
	device:set_field("panic_state", nil)
	device:set_field("last_active_time", nil)
	log.debug("Panic manager cleanup completed")
end

return panic_manager