--[[
  Health Monitor Service for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  Manages adaptive health monitoring with intelligent scheduling based on grill activity.
  Handles device connectivity checks, rediscovery attempts, and panic state management.

  Features:
  - Adaptive monitoring intervals based on grill state
  - Intelligent rediscovery scheduling
  - Panic state management for safety
  - Resource-efficient monitoring
--]]

local capabilities = require("st.capabilities")
local log = require("log")
---@type Config
local config = require("config")
local network_utils = require("network_utils")
local panic_manager = require("panic_manager")

local health_monitor = {}

-- ============================================================================
-- TIMER MANAGEMENT AND DETECTION
-- ============================================================================

--- Check if a health check timer is currently active
-- @param device SmartThings device object
-- @return boolean True if timer is active
local function is_health_timer_active(device)
	local timer_id = device:get_field("health_timer_id")
	local last_scheduled = device:get_field("last_health_scheduled") or 0
	local current_time = os.time()

	-- If no timer ID, consider inactive
	if not timer_id then
		log.debug("No timer ID found - timer inactive")
		return false
	end

	local inactive_threshold = config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL * config.CONSTANTS.INACTIVE_GRILL_MULTIPLIER
	-- Check if timer is very old
	local timer_age = current_time - last_scheduled
	if timer_age > inactive_threshold then
		log.warn(
			string.format(
				"Timer ID exists but is very old (%d minutes) - clearing and considering inactive",
				math.floor(timer_age / 60)
			)
		)
		device:set_field("health_timer_id", nil, { persist = true })
		device:set_field("last_health_scheduled", nil, { persist = true })
		return false
	end

	log.debug(string.format("Timer active: %s (age: %d seconds)", timer_id, timer_age))
	return true
end

--- Mark that a health timer is active
-- @param device SmartThings device object
-- @param timer_id string Timer identifier
local function mark_health_timer_active(device, timer_id)
	device:set_field("health_timer_id", timer_id, { persist = true })
	device:set_field("last_health_scheduled", os.time(), { persist = true })
	log.info(string.format("Marked health timer active: %s", timer_id))
end

--- Clear health timer tracking
-- @param device SmartThings device object
local function clear_health_timer_tracking(device)
	device:set_field("health_timer_id", nil, { persist = true })
	device:set_field("last_health_scheduled", nil, { persist = true })
	log.debug("Cleared health timer tracking")
end

--- Start comprehensive timer recovery process with retries
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
-- @param attempt number Current attempt (defaults to 1)
local function start_timer_recovery_process(driver, device, attempt)
	attempt = attempt or 1
	local max_attempts = 3

	log.warn(
		string.format("Timer recovery attempt %d/%d for device %s", attempt, max_attempts, device.label or device.id)
	)

	-- Clear any stale timer tracking before attempting recovery
	clear_health_timer_tracking(device)

	-- Wait a moment for cleanup
	device.thread:call_with_delay(1, function()
		-- Attempt to start new timer
		local success = pcall(function()
			health_monitor.schedule_next_health_check(driver, device)
		end)

		if not success then
			log.error(string.format("Timer recovery attempt %d failed with error", attempt))
		end

		-- Verify timer is now active after a brief delay
		device.thread:call_with_delay(2, function()
			if is_health_timer_active(device) then
				log.info(string.format("Timer recovery successful on attempt %d", attempt))
				return
			end

			log.error(string.format("Timer recovery failed on attempt %d - timer still not active", attempt))

			-- If more attempts remaining, schedule next attempt
			if attempt < max_attempts then
				local retry_delay = math.min(config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL * attempt, 300) -- Max 5 min
				log.info(
					string.format(
						"Scheduling recovery retry in %d seconds (attempt %d/%d)",
						retry_delay,
						attempt + 1,
						max_attempts
					)
				)

				device.thread:call_with_delay(retry_delay, function()
					start_timer_recovery_process(driver, device, attempt + 1)
				end)
			else
				log.error("Timer recovery failed after all attempts - system may need restart")
				-- Set a flag to indicate recovery failure
				device:set_field("timer_recovery_failed", true, { persist = true })
			end
		end)
	end)
end

--- Ensure exactly one health timer is running
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
-- @param force_restart boolean Force restart even if timer appears active
-- @return boolean True if new timer was started
function health_monitor.ensure_health_timer_active(driver, device, force_restart)
	if not device or type(device) ~= "table" then
		log.error("ensure_health_timer_active called with invalid device object")
		return false
	end

	if force_restart then
		log.info("Force restarting health timer as requested")
		clear_health_timer_tracking(device)
		device:set_field("timer_recovery_failed", nil, { persist = true }) -- Clear failure flag
	end

	if not is_health_timer_active(device) then
		log.warn("No active health timer detected - starting new timer")
		local success = pcall(function()
			health_monitor.schedule_next_health_check(driver, device)
		end)

		if not success then
			log.error("Failed to start health timer - attempting recovery")
			start_timer_recovery_process(driver, device)
		end
		return true -- Started new timer (or attempted to)
	else
		log.debug("Health timer is already active")
		return false -- Timer already running
	end
end

-- ============================================================================
-- MAIN EXPORTED FUNCTIONS
-- ============================================================================

--- Calculate adaptive health check interval based on grill activity state
-- This function determines the refresh rate based on whether the grill is active,
-- preheating, in panic state, or inactive. The result is clamped between a minimum and maximum
-- interval to prevent overly aggressive or sparse polling.
-- @param device SmartThings device object
-- @param is_active boolean True if grill switch is ON
-- @return number Calculated interval in seconds
function health_monitor.compute_interval(device, is_active)
	-- Get the base refresh interval from the device preferences, with a fallback to the default.
	local base_interval = config.get_refresh_interval(device)

	local multiplier
	-- PRIORITY 1: Check for panic state first (fastest reconnection attempts)
	if panic_manager.is_in_panic_state(device) then
		-- Use fastest multiplier for panic recovery to aggressively attempt reconnection
		multiplier = config.CONSTANTS.PANIC_RECOVERY_MULTIPLIER
	elseif is_active then
		-- If the grill is powered on, check for the preheating state.
		if device:get_field("is_preheating") then
			-- Use a faster multiplier for the preheating state to get quicker temperature updates.
			multiplier = config.CONSTANTS.PREHEATING_GRILL_MULTIPLIER
		else
			-- If not preheating, use the standard active multiplier.
			multiplier = config.CONSTANTS.ACTIVE_GRILL_MULTIPLIER
		end
	else
		-- If the grill is off, use a much slower multiplier to conserve resources.
		multiplier = config.CONSTANTS.INACTIVE_GRILL_MULTIPLIER
	end

	local interval = base_interval * multiplier

	-- Clamp the calculated interval to be within the min and max bounds defined in the config.
	return math.max(
		config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL,
		math.min(interval, config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL)
	)
end

--- Schedule the next health check
-- This function is called from the main driver thread
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
function health_monitor.schedule_next_health_check(driver, device)
	if not device or type(device) ~= "table" then
		log.error("schedule_next_health_check called with invalid device object")
		return
	end

	local switch_state =
		device:get_latest_state(config.COMPONENTS.GRILL, capabilities.switch.ID, capabilities.switch.switch.NAME)

	-- Check if this is the first health check after initial setup - use shorter interval for better UX
	local is_first_check = device:get_field("first_health_check_after_setup")
	local interval
	if is_first_check then
		log.debug("Using shorter interval for first health check after setup")
		-- Clear the flag so subsequent checks use normal intervals
		device:set_field("first_health_check_after_setup", nil, { persist = true })
		-- Use base interval (30 seconds) instead of multiplied interval for first check
		local base_interval = config.get_refresh_interval(device)
		interval = math.max(config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL, base_interval)
	else
		interval = health_monitor.compute_interval(device, switch_state == "on")
	end

	-- Clamp interval to prevent timer overflow after long sessions
	-- SmartThings timers may have problems with very large delay values
	local max_safe_interval = config.CONSTANTS.MAX_HEALTH_INTERVAL_HOURS or 7200 -- 2 hours default
	local safe_interval = math.min(interval, max_safe_interval)

	if safe_interval ~= interval then
		log.warn(
			string.format(
				"Clamped health check interval from %d to %d seconds to prevent timer overflow",
				interval,
				safe_interval
			)
		)
	end

	-- Generate unique timer ID for tracking
	local timer_id = string.format("health_check_%d_%d", os.time(), math.random(1000, 9999))

	-- Schedule the timer with error handling
	local timer_success, timer_err = pcall(function()
		device.thread:call_with_delay(safe_interval, function()
			device:set_field("last_health_timer_fired", os.time(), { persist = true })
			log.debug("Health check timer fired, clearing timer tracking before next action")
			clear_health_timer_tracking(device)

			-- Re-check health after the delay
			if device:get_field("is_polling") then
				log.debug("Polling already in progress, skipping scheduled health check.")
				-- Still need to reschedule even if skipping this check
				health_monitor.schedule_next_health_check(driver, device)
			else
				health_monitor.do_health_check(driver, device)
			end
		end, timer_id)
	end)

	if timer_success then
		-- Mark timer as active only if scheduling succeeded
		mark_health_timer_active(device, timer_id)
		log.info(
			string.format("Successfully scheduled next health check in %d seconds (timer: %s)", safe_interval, timer_id)
		)
	else
		log.error("Failed to schedule health check timer: " .. tostring(timer_err))
		-- Don't mark as active if scheduling failed
		clear_health_timer_tracking(device)
	end
end

--- Perform a single health check for the grill
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
function health_monitor.do_health_check(driver, device)
	-- Defensive check to ensure we have a valid device table
	if type(device) ~= "table" then
		log.error("do_health_check called with invalid device object (type: " .. type(device) .. ")")
		return false
	end

	-- Mark that we are polling to prevent re-entrancy (non-persistent to avoid stale flags)
	device:set_field("is_polling", true)
	device:set_field("last_health_check_run", os.time(), { persist = true })

	-- Use get_status instead of send_command with "status" + crash protection
	log.debug(string.format("Performing health check for device: %s", device.label or device.id))

	local status_info = nil
	local auth_failure = false
	local consecutive_auth_failures = 0
	local success, err = pcall(function()
		status_info = network_utils.get_status(device, driver)
	end)

	-- Always clear polling flag, even if crash occurred
	device:set_field("is_polling", false)

	if not success then
		log.error(string.format("Health check crashed for device %s: %s", device.label or device.id, err))
		status_info = nil -- Treat crash as failure
	elseif not status_info then
		-- Check if this was an authentication failure vs connectivity issue
		local last_error = device:get_field("last_network_error") or ""
		auth_failure = (
			string.find(last_error, "Authentication")
			or string.find(last_error, "401")
			or string.find(last_error, "403")
		) ~= nil

		if auth_failure then
			-- Track consecutive authentication failures
			consecutive_auth_failures = device:get_field("consecutive_auth_failures") or 0
			consecutive_auth_failures = consecutive_auth_failures + 1
			device:set_field("consecutive_auth_failures", consecutive_auth_failures, { persist = true })

			log.warn(string.format("Authentication failure #%d for %s", consecutive_auth_failures, device.label))

			-- Check if grill is currently ON (use last known status or switch state)
			local device_status_service = require("device_status_service")
			local grill_is_on = device_status_service.is_grill_on(device)

			if grill_is_on then
				-- Grill is ON - only treat as offline if we've had 2+ consecutive auth failures
				if consecutive_auth_failures < 2 then
					log.info(
						"Authentication failure detected (grill ON) but not panicking yet (waiting for 2nd failure)"
					)
					return true -- Don't mark as offline yet
				end
				-- Grill is ON and we've had 2+ auth failures - trigger panic with proper status
				log.warn("Grill is ON with 2+ consecutive auth failures - triggering panic")

				-- Mark as offline
				pcall(function()
					network_utils.mark_device_offline(device)
				end)

				-- Update status for authentication failure (grill ON) - this will trigger panic
				device_status_service.update_auth_failure_status(device, true)

				-- Handle panic state
				panic_manager.handle_offline_panic_state(device)
				return true
			else
				-- Grill is OFF - don't trigger panic, but notify in grillStatus
				if consecutive_auth_failures < 2 then
					log.info(
						"Authentication failure detected (grill OFF) but not marking offline yet (waiting for 2nd failure)"
					)
					return true -- Don't mark as offline yet
				end
				-- Grill is OFF and we've had 2+ auth failures - mark offline but don't panic
				log.warn("Grill is OFF with 2+ consecutive auth failures - marking offline but no panic")

				-- Mark as offline but skip panic handling
				pcall(function()
					network_utils.mark_device_offline(device)
				end)

				-- Update status for authentication failure (grill OFF)
				device_status_service.update_auth_failure_status(device, false)

				-- Don't call panic_manager.handle_offline_panic_state for auth failures when grill is OFF
				return true
			end
		end
	end

	if status_info then
		-- Grill is healthy and responsive
		log.info(string.format("Health check successful for %s. Grill is online.", device.label))

		-- Clear recovery failure flag on successful health check
		device:set_field("timer_recovery_failed", nil, { persist = true })

		-- Clear consecutive authentication failures on successful connection
		device:set_field("consecutive_auth_failures", 0, { persist = true })

		-- Mark device as online
		pcall(function()
			network_utils.mark_device_online(device)
		end)

		-- Clear panic state immediately when connection/auth works again
		panic_manager.clear_panic_state(device)

		-- Update device status based on the received information
		-- Use device_status_service directly to avoid circular dependencies
		local device_status_service = require("device_status_service")
		local ok, update_err = pcall(function()
			device_status_service.update_device_status(device, status_info)
			-- Virtual device updates are now handled within update_device_status
		end)

		if not ok then
			log.error(string.format("Failed to update device status during health check: %s", tostring(update_err)))
		end

		-- Schedule the next check based on the new status with error handling
		local schedule_success = pcall(health_monitor.schedule_next_health_check, driver, device)
		if not schedule_success then
			log.error("Failed to schedule next health check - attempting fallback scheduling")
			start_timer_recovery_process(driver, device)
		end
	else
		-- Grill is unresponsive or offline
		log.warn(string.format("Health check failed for %s. Grill may be offline or unreachable.", device.label))

		-- For authentication failures, don't mark as offline or trigger panic yet
		if not auth_failure or consecutive_auth_failures >= 2 then
			-- Ensure platform and UI reflect offline status
			pcall(function()
				network_utils.mark_device_offline(device)
			end)

			-- If panic is active, force a virtual error device update so it can be brought online for routines
			local virtual_device_manager = require("virtual_device_manager")
			if panic_manager.is_in_panic_state(device) then
				-- Use cached status (nil) to avoid network calls
				virtual_device_manager.update_virtual_devices_from_status(device, nil)
			end

			-- Handle panic state for recently active grills (only for non-auth failures or repeated auth failures)
			panic_manager.handle_offline_panic_state(device)
		end

		-- Check for periodic rediscovery (24-hour rule) when device is offline
		local auto_rediscovery = device.preferences and device.preferences.autoRediscovery
		local ip_preference = device.preferences and device.preferences.ipAddress
		local is_rediscovery_ip = (
			ip_preference == config.CONSTANTS.DEFAULT_IP_ADDRESS
			or ip_preference == config.CONSTANTS.DEBUG_IP_ADDRESS
		)

		if auto_rediscovery and is_rediscovery_ip then
			-- Track when device first went offline for proper 24-hour timing
			local first_offline_time = device:get_field("first_offline_time")
			local current_time = os.time()

			-- Initialize first offline time if not set (done by mark_device_offline)
			if not first_offline_time then
				log.debug("Device went offline - starting 24-hour countdown for periodic rediscovery")
			else
				-- Check if device has been offline for 24 hours
				local time_since_offline = current_time - first_offline_time
				local last_periodic_rediscovery = device:get_field("last_periodic_rediscovery") or 0
				local time_since_last_periodic = current_time - last_periodic_rediscovery

				-- Only trigger periodic scan if:
				-- 1. Device has been offline for 24+ hours AND
				-- 2. Haven't done a periodic scan in the last 24 hours
				if
					time_since_offline >= config.CONSTANTS.PERIODIC_REDISCOVERY_INTERVAL
					and time_since_last_periodic >= config.CONSTANTS.PERIODIC_REDISCOVERY_INTERVAL
				then
					log.info("24-hour periodic rediscovery check triggered - attempting network scan")

					-- Update timestamp before attempt to prevent rapid retries
					device:set_field("last_periodic_rediscovery", current_time, { persist = true })

					-- Attempt rediscovery with bypass flag for periodic scans
					if network_utils.attempt_rediscovery(device, driver, "periodic_24h", true) then
						if network_utils.health_check(device) then
							network_utils.mark_device_online(device)
							-- Offline timer cleared by mark_device_online
							log.info("Device successfully rediscovered during periodic 24-hour scan")
							local device_status_service = require("device_status_service")
							local language = config.STATUS_MESSAGES
							device_status_service.set_status_message(device, language.connected_periodic_rediscovery)
						else
							log.warn("Device found during periodic scan but health check failed")
						end
					else
						log.info("Periodic 24-hour rediscovery scan completed - no device found")
					end
				end
			end
		end

		-- Still try to schedule next check even when offline (for recovery)
		local schedule_success = pcall(health_monitor.schedule_next_health_check, driver, device)
		if not schedule_success then
			log.error("Failed to schedule next health check while offline - attempting recovery")
			start_timer_recovery_process(driver, device)
		end
	end
end

--- Set up health monitoring for a device
-- This is called once during device initialization
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
function health_monitor.setup_monitoring(driver, device)
	-- Defensive check to ensure we have a valid device table
	if type(device) ~= "table" then
		log.error("setup_monitoring called with invalid device object (type: " .. type(device) .. ")")
		return false
	end

	-- Skip initial health check during initialization to prevent redundant network calls
	-- The device has already been initialized with fresh data, so we'll start periodic monitoring
	-- without an immediate baseline check
	log.info(string.format("Setting up health monitoring for %s...", device.label))
	log.debug("Skipping initial health check during setup - using initialization data as baseline")

	-- Clear any stale recovery flags
	device:set_field("timer_recovery_failed", nil, { persist = true })

	-- Set flag to indicate this is the first health check after setup
	device:set_field("first_health_check_after_setup", true, { persist = true })

	-- Force restart health timer on initialization to clear any stale timer fields
	log.info("Forcing health timer restart on device initialization to clear any stale timer fields.")
	health_monitor.ensure_health_timer_active(driver, device, true)
end

--- Perform a comprehensive timer health check and recovery with retry logic
-- This can be called periodically or when problems are suspected
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
-- @return boolean True if timer recovery was initiated
function health_monitor.check_and_recover_timer(driver, device)
	if not device or type(device) ~= "table" then
		log.error("check_and_recover_timer called with invalid device object")
		return false
	end

	log.debug(string.format("Performing comprehensive timer health check for %s", device.label or device.id))

	-- Check if we've had previous recovery failures
	local recovery_failed = device:get_field("timer_recovery_failed")
	if recovery_failed then
		log.warn("Previous timer recovery failed - forcing complete restart")
		device:set_field("timer_recovery_failed", nil, { persist = true })
		health_monitor.ensure_health_timer_active(driver, device, true)
		return true
	end

	-- Check if timer is initially missing
	if is_health_timer_active(device) then
		log.debug("Timer health check passed - timer is active")
		return false
	end

	-- Timer is missing - start recovery process
	log.warn("Timer health check detected missing timer - initiating recovery")
	start_timer_recovery_process(driver, device)
	return true
end

--- Force restart the health monitoring timer
-- Use this when you suspect the timer is stuck or corrupted
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
function health_monitor.force_restart_timer(driver, device)
	if not device or type(device) ~= "table" then
		log.error("force_restart_timer called with invalid device object")
		return
	end

	log.info(string.format("Force restarting health monitoring timer for %s", device.label or device.id))
	health_monitor.ensure_health_timer_active(driver, device, true)
end

--- Clean up health monitoring resources for a device
-- @param device SmartThings device object
function health_monitor.cleanup_monitoring(device)
	-- Clear health monitoring related fields
	if type(device) == "table" then
		device:set_field("last_health_check", nil)
		device:set_field("last_rediscovery_attempt", nil)
		device:set_field("last_periodic_rediscovery", nil)
		device:set_field("timer_recovery_failed", nil)
		-- Clear timer tracking
		clear_health_timer_tracking(device)
	end

	log.debug("Health monitor cleanup completed.")
end

return health_monitor