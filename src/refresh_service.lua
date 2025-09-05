--[[
  Refresh Service for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module provides centralized device refresh logic to avoid code duplication and circular dependencies.
  It handles all device status updates, virtual device synchronization, and offline status management
  with proper error handling and recovery mechanisms.

  Features:
  - Centralized refresh logic with error handling
  - Status fetching with network failure recovery
  - Device status updates via dedicated services
  - Virtual device synchronization with grill data
  - Offline status handling with panic state preservation
  - Scheduled refresh with configurable delay for UI
  - No circular dependencies between service modules

  Refresh Operations:
  - Manual refresh: User-triggered via refresh capability
  - Scheduled refresh: Automatic refresh after command execution
  - Status-based refresh: Update from already-available status data
  - Offline handling: Graceful degradation when grill is unreachable

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local log = require("log")
---@type Config
local config = require("config")
local network_utils = require("network_utils")
local device_status_service = require("device_status_service")
local health_monitor = require("health_monitor")
local panic_manager = require("panic_manager")

local refresh_service = {}

-- ============================================================================
-- CORE REFRESH FUNCTIONALITY
-- ============================================================================

--- Perform a complete device refresh with status update
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param command table Command that triggered the refresh (optional)
function refresh_service.refresh_device(device, driver, command)
	log.info(string.format("Refreshing device: %s", device.id))

	-- Check if a health check is already in progress to prevent duplicate operations
	local is_polling = device:get_field("is_polling") or false
	if is_polling then
		log.info("Health check already in progress - skipping manual refresh to prevent duplicate operations")
		return false
	end

	-- Check if this is a manual refresh and ensure health timer is active
	local is_manual_refresh = command and command.command and command.command == "refresh"
	if is_manual_refresh then
		log.debug("Manual refresh detected - checking health timer status")
		local timer_started = health_monitor.ensure_health_timer_active(driver, device, false)
		if timer_started then
			log.info("Manual refresh detected missing health timer - restarted automatic monitoring")
		end
	end

	-- Safely attempt to retrieve status and update device
	local status = network_utils.get_status(device, driver)
	if status then
		device_status_service.update_device_status(device, status)
		-- Virtual device updates are now handled within update_device_status
		log.info("Device refresh completed successfully")
		return true
	end

	log.error("Device refresh failed - grill is offline")
	device_status_service.update_offline_status(device)
	-- Trigger panic logic if grill was recently active and is unreachable
	panic_manager.handle_offline_panic_state(device)
	return false
end

--- Schedule a device refresh after a delay
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param command table Command that triggered the refresh (optional)
function refresh_service.schedule_refresh(device, driver, command)
	device.thread:call_with_delay(config.CONSTANTS.REFRESH_DELAY, function()
		refresh_service.refresh_device(device, driver, command)
	end)
end

--- Refresh device from status data (when status is already available)
-- @param device SmartThings device object
-- @param status table Current grill status data
function refresh_service.refresh_from_status(device, status)
	if not status then
		log.warn("No status data provided for refresh")
		return false
	end

	log.debug("Refreshing device from provided status data")

	-- Update device status using dedicated service
	device_status_service.update_device_status(device, status)

	-- Virtual device updates are now handled within update_device_status

	log.debug("Device refresh from status completed successfully")
	return true
end

return refresh_service