--[[
  Pit Boss Grill SmartThings Edge Driver - Main Entry Point
  Created by: xeudoxus
  Version: 2025.9.4

  This is the main driver entry point that orchestrates device lifecycle management,
  intelligent health monitoring, and efficient resource utilization for Pit Boss WiFi grills.

  Features:
    - Separation of concerns with dedicated service modules
    - Error handling and recovery mechanisms
    - Efficient resource management
    - Configuration management
    - Logging and debugging capabilities

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local capabilities = require("st.capabilities")
local Driver = require("st.driver")
local log = require("log")
local cosock = require("cosock")

-- Import core modules with clear dependency hierarchy
---@type Config
local config = require("config")
local custom_caps = require("custom_capabilities")
local network_utils = require("network_utils")
local device_manager = require("device_manager")
local handlers_module = require("capability_handlers")
local health_monitor = require("health_monitor")
local virtual_device_manager = require("virtual_device_manager")
local panic_manager = require("panic_manager")

-- Small helper to validate driver/device parameters and centralize logging.
local function validate_driver_and_device(driver, device, fn_name)
	if not driver then
		log.error(fn_name .. " called with nil driver")
		return false
	end
	if not device then
		log.error(fn_name .. " called with nil device")
		return false
	end
	if type(device) ~= "table" then
		log.error(
			string.format(
				"%s called with invalid device object (type: %s, value: %s)",
				fn_name,
				type(device),
				tostring(device)
			)
		)
		return false
	end
	return true
end

--- Force capability refresh for device profile updates
-- @param device SmartThings device object
local function force_capability_refresh(device)
	-- Force a profile metadata update to refresh capabilities
	local success, err = pcall(function()
		-- Get the profile ID as a string instead of passing the whole profile object
		local profile_id = device.profile_id or (device.profile and device.profile.id)
		if profile_id then
			device:try_update_metadata({ profile = profile_id })
		else
			log.warn("Cannot refresh device capabilities: no profile ID found")
		end
	end)

	if not success then
		log.warn(string.format("Failed to refresh device capabilities: %s", tostring(err)))
	else
		log.debug("Device capabilities refresh triggered")
	end
end

-- ============================================================================
-- DRIVER LIFECYCLE HANDLERS
-- ============================================================================

--- Attempt device rediscovery during initialization
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @return boolean True if rediscovery was successful
local function attempt_initialization_rediscovery(device, driver)
	log.debug("--- INIT --- attempt_initialization_rediscovery: Entered")

	if not network_utils.should_attempt_rediscovery(device) then
		log.debug("--- INIT --- attempt_initialization_rediscovery: Should not attempt rediscovery. Exiting.")
		return false
	end

	device_manager.mark_rediscovery_attempt(device)
	log.info("--- INIT --- attempt_initialization_rediscovery: Attempting rediscovery during initialization")

	if network_utils.attempt_rediscovery(device, driver, "initialization") then
		log.debug("--- INIT --- attempt_initialization_rediscovery: rediscover_device returned true")
		if network_utils.health_check(device) then
			network_utils.mark_device_online(device)
			log.info("--- INIT --- attempt_initialization_rediscovery: Device successfully rediscovered and online")

			-- Initialize device status after successful rediscovery with timeout
			log.debug("--- INIT --- attempt_initialization_rediscovery: Getting device status with timeout")
			local status_start_time = os.time()
			local status = network_utils.get_status(device, driver)
			local status_elapsed = os.time() - status_start_time

			if status_elapsed > config.CONSTANTS.STATUS_UPDATE_TIMEOUT then
				log.warn(
					string.format(
						"Status update took %ds (timeout: %ds) during initialization",
						status_elapsed,
						config.CONSTANTS.STATUS_UPDATE_TIMEOUT
					)
				)
			end

			if status then
				handlers_module.update_device_from_status(device, status)
				panic_manager.update_last_active_time_if_on(device, status)
			else
				log.warn("--- INIT --- attempt_initialization_rediscovery: Status update failed during initialization")
			end

			log.debug("--- INIT --- attempt_initialization_rediscovery: Exiting, returning true")
			return true
		end
	end

	log.debug("--- INIT --- attempt_initialization_rediscovery: Exiting, returning false")
	return false
end

--- Perform initial device setup with comprehensive error handling
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @return boolean True if initialization was successful
local function perform_initial_setup(driver, device)
	log.debug("--- INIT --- perform_initial_setup: Entered")
	local ip = device_manager.get_device_ip(device)

	if not ip then
		log.info(
			"--- INIT --- perform_initial_setup: No IP found during initialization, marking offline until discovery"
		)
		network_utils.mark_device_offline(device)
		log.debug("--- INIT --- perform_initial_setup: Exiting, returning false")
		return false
	end

	log.debug(string.format("--- INIT --- perform_initial_setup: Attempting initial setup for device at IP: %s", ip))

	-- Perform health check with timeout
	if network_utils.health_check(device) then
		network_utils.mark_device_online(device)
		log.info(
			string.format("--- INIT --- perform_initial_setup: Device successfully initialized and online at %s", ip)
		)

		-- Initialize device status with timeout monitoring
		log.debug("--- INIT --- perform_initial_setup: Getting device status with timeout")
		local status_start_time = os.time()
		local status = network_utils.get_status(device, driver)
		local status_elapsed = os.time() - status_start_time

		if status_elapsed > config.CONSTANTS.STATUS_UPDATE_TIMEOUT then
			log.warn(
				string.format(
					"Status update took %ds (timeout: %ds) during initialization",
					status_elapsed,
					config.CONSTANTS.STATUS_UPDATE_TIMEOUT
				)
			)
		end

		if status then
			handlers_module.update_device_from_status(device, status)
			panic_manager.update_last_active_time_if_on(device, status)
		else
			log.warn("--- INIT --- perform_initial_setup: Status update failed during initialization")
		end

		-- Refresh capabilities to ensure platform synchronization
		force_capability_refresh(device)

		-- Create virtual devices based on preferences
		virtual_device_manager.manage_virtual_devices(driver, device)

		log.debug("--- INIT --- perform_initial_setup: Exiting, returning true")
		return true
	else
		log.warn("--- INIT --- perform_initial_setup: Initial health check failed for device at %s", ip)

		-- Attempt rediscovery if appropriate
		if attempt_initialization_rediscovery(device, driver) then
			log.debug("--- INIT --- perform_initial_setup: Exiting after successful rediscovery, returning true")
			return true
		end

		-- Add delay before marking device offline to allow for retry in case of transient network issues
		log.warn(
			string.format(
				"--- INIT --- perform_initial_setup: Device initialization failed, waiting %ds before marking offline",
				config.CONSTANTS.DISCOVERY_RETRY_DELAY
			)
		)
		cosock.socket.sleep(config.CONSTANTS.DISCOVERY_RETRY_DELAY)

		log.warn("--- INIT --- perform_initial_setup: Device initialization failed, marking offline")
		network_utils.mark_device_offline(device)
		log.debug("--- INIT --- perform_initial_setup: Exiting, returning false")
		return false
	end
end

--- Device initialization with intelligent health monitoring setup
-- @param driver SmartThings driver object
-- @param device SmartThings device object
local function device_init(driver, device)
	if not validate_driver_and_device(driver, device, "device_init") then
		return
	end

	log.debug("--- INIT --- device_init: Entered for device: " .. tostring(device.id))

	log.info(string.format("Initializing Pit Boss Grill device: %s", tostring(device.id)))

	-- Handle virtual device initialization
	if device.parent_assigned_child_key then
		log.info(
			string.format(
				"--- INIT --- device_init: Initializing virtual device: %s (%s)",
				device.label or "Unknown",
				device.parent_assigned_child_key
			)
		)
		network_utils.mark_device_online(device)
		log.debug("--- INIT --- device_init: Exiting for virtual device")
		return
	end

	-- Initialize main grill device
	log.debug("--- INIT --- device_init: Calling perform_initial_setup")
	local init_success = perform_initial_setup(driver, device)

	-- Initialize virtual devices
	log.debug("--- INIT --- device_init: Calling virtual_device_manager.initialize_virtual_devices")
	virtual_device_manager.initialize_virtual_devices(driver, device, init_success)

	-- Set up health monitoring with proper parameter validation
	log.debug("--- INIT --- device_init: Setting up health monitoring...")
	if type(device) == "table" and device.id then
		health_monitor.setup_monitoring(driver, device)
	else
		log.error("--- INIT --- device_init: Cannot setup health monitoring - invalid device object")
	end

	-- Schedule periodic network cache cleanup
	log.debug("--- INIT --- device_init: Setting up network cache cleanup...")
	if type(device) == "table" and device.id and device.thread then
		network_utils.schedule_cache_cleanup(device)
	else
		log.error("--- INIT --- device_init: Cannot setup cache cleanup - invalid device object or missing thread")
	end

	log.info(
		string.format(
			"Pit Boss Grill initialization %s with adaptive monitoring",
			init_success and "completed successfully" or "completed with warnings"
		)
	)
	log.debug("--- INIT --- device_init: Exiting")
end

--- Handle device addition with metadata extraction and initialization
-- @param driver SmartThings driver object
-- @param device SmartThings device object
local function device_added(driver, device)
	if not validate_driver_and_device(driver, device, "device_added") then
		return
	end

	log.debug("--- INIT --- device_added: Entered for device: " .. tostring(device.id))

	log.info(string.format("Pit Boss Grill device added: %s", tostring(device.id)))

	-- Skip initialization for virtual devices
	if device.parent_assigned_child_key then
		log.info(
			string.format(
				"--- INIT --- device_added: Skipping initialization for virtual device: %s (%s)",
				device.label or "Unknown",
				device.parent_assigned_child_key
			)
		)
		network_utils.mark_device_online(device)
		log.debug("--- INIT --- device_added: Exiting for virtual device")
		return
	end

	-- Extract and store device metadata
	log.debug("--- INIT --- device_added: Calling device_manager.extract_device_metadata")
	device_manager.extract_device_metadata(device)

	-- Initialize device state
	log.debug("--- INIT --- device_added: Calling device_manager.initialize_device_state")
	local ok, err = pcall(function()
		device_manager.initialize_device_state(device)
	end)
	if not ok then
		log.warn(string.format("--- INIT --- device_added: initialize_device_state failed: %s", tostring(err)))
	end

	log.debug("--- INIT --- device_added: Exiting")
end

--- Handle device removal with cleanup
-- @param driver SmartThings driver object
-- @param device SmartThings device object
local function device_removed(driver, device)
	if not validate_driver_and_device(driver, device, "device_removed") then
		return
	end

	log.info(string.format("Pit Boss Grill device removed: %s", tostring(device.id)))

	-- Skip cleanup for virtual devices
	if device.parent_assigned_child_key then
		log.info(
			string.format(
				"Virtual device removed: %s (%s)",
				device.label or "Unknown",
				device.parent_assigned_child_key
			)
		)
		return
	end

	-- Clean up resources
	device_manager.cleanup_device_resources(device)
	health_monitor.cleanup_monitoring(device)

	log.debug("Device cleanup completed")
end

--- Handle device preference changes with intelligent reconfiguration
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param event SmartThings event object
-- @param old_prefs table Previous preferences
local function device_info_changed(driver, device, _event, old_prefs) -- luacheck: ignore 212
	if not validate_driver_and_device(driver, device, "device_info_changed") then
		return
	end

	-- SmartThings Edge sometimes doesn't pass prefs correctly, so get them from device
	local current_prefs = device.preferences or {}

	log.info(
		string.format(
			"Device info changed for %s (old_prefs: %s, new_prefs: %s)",
			tostring(device.id),
			old_prefs and "present" or "nil",
			current_prefs and "present" or "nil"
		)
	)

	-- Skip preference handling for virtual devices
	if device.parent_assigned_child_key then
		log.debug(
			string.format("Skipping preference handling for virtual device: %s", device.parent_assigned_child_key)
		)
		return
	end

	-- Process preference changes
	device_manager.handle_preference_changes(device, driver, old_prefs.old_st_store.preferences, current_prefs)

	-- Update virtual devices if needed
	virtual_device_manager.handle_preference_changes(driver, device, old_prefs.old_st_store.preferences, current_prefs)

	log.debug("Preference change processing completed")
end

--- Clear discovery state to prevent stale flags after driver restart
--- NOTE: This function appears unused to static analysis but is called from:
--- 1. Driver lifecycle handler (callback function)
--- 2. Signal handlers (SIGTERM/SIGINT)
--- 3. Driver run wrapper (crash/normal exit)
--- 4. cleanup_driver function
---@diagnostic disable-next-line: unused-local
local function clear_discovery_state(driver)
	if not driver then
		log.debug("🧹 No driver provided - skipping discovery state cleanup")
		return
	end

	if driver and driver.datastore then
		log.info("🧹 Clearing discovery state")
		driver.datastore.discovery_in_progress = false
		driver.datastore.discovery_start_time = nil
		log.debug("✅ Discovery state cleared")
	else
		log.debug("🧹 No driver datastore found - skipping discovery state cleanup")
	end
end

--- Comprehensive shutdown cleanup to stop all timers and scans
---@diagnostic disable-next-line: unused-local
local function shutdown_cleanup(driver)
	log.info("🛑 Performing comprehensive shutdown cleanup...")

	-- 1. Clear discovery state
	clear_discovery_state(driver)

	-- 2. Clean up network resources
	network_utils.cleanup_network_cache()

	-- 3. Stop all health monitoring timers and rediscovery scans for all devices
	if driver and driver.devices then
		local device_count = 0
		local timer_count = 0

		for _, device in pairs(driver.devices) do
			if device and type(device) == "table" then
				device_count = device_count + 1

				-- Clean up health monitoring for each device
				health_monitor.cleanup_monitoring(device)

				-- Clean up panic resources for each device
				panic_manager.cleanup_panic_resources(device)

				-- Clear rediscovery state for this device
				local rediscovery_in_progress = device:get_field("rediscovery_in_progress") or false
				if rediscovery_in_progress then
					device:set_field("rediscovery_in_progress", false, { persist = true })
					device:set_field("rediscovery_start_time", nil, { persist = true })
					timer_count = timer_count + 1
					log.debug(
						string.format(
							"🛑 Stopped rediscovery scan for device: %s",
							device.label or device.id or "unknown"
						)
					)
				end

				log.debug(
					string.format("🧹 Cleaned up monitoring for device: %s", device.label or device.id or "unknown")
				)
			end
		end

		log.info(
			string.format(
				"🛑 Shutdown cleanup: %d devices processed, %d active scans stopped",
				device_count,
				timer_count
			)
		)
	end

	-- 4. Stop timer system if available
	if driver and driver.thread and driver.thread.stop then
		log.info("🛑 Stopping timer system...")
		driver.thread.stop()
		log.debug("✅ Timer system stopped")
	end

	log.info("✅ Comprehensive shutdown cleanup completed")
end

-- ============================================================================
-- DRIVER CONFIGURATION AND STARTUP
-- ============================================================================

--- Create and configure the main driver instance
local pitboss_driver = Driver("pitboss-grill", {
	-- Network discovery handler for automatic device detection
	discovery = require("discovery"),

	-- Device lifecycle management handlers
	lifecycle_handlers = {
		init = device_init,
		added = device_added,
		infoChanged = device_info_changed,
		removed = device_removed,
	},

	-- Driver-level lifecycle handler to capture platform events
	driver_lifecycle = function(driver, event_type, event_data)
		log.info(string.format("🔄 DRIVER LIFECYCLE: Received event '%s'", event_type or "unknown"))

		if event_data then
			log.debug(string.format("Driver lifecycle event data: %s", tostring(event_data)))
		end

		-- Log specific lifecycle events we're interested in
		if event_type == "shutdown" or event_type == "restart" then
			log.warn(
				string.format("🚨 DRIVER %s DETECTED - preparing for graceful shutdown", string.upper(event_type))
			)

			-- Perform comprehensive shutdown cleanup (stops timers, scans, clears state)
			shutdown_cleanup(driver)

			log.info(string.format("✅ Driver %s cleanup completed", event_type))
		elseif event_type == "start" or event_type == "init" then
			log.info(string.format("🚀 Driver %s: Initializing Pit Boss Grill SmartThings Edge Driver", event_type))
		else
			log.debug(string.format("Driver lifecycle event: %s (unhandled)", event_type))
		end
	end,

	-- Global event handler to capture all driver events
	event_handler = function(_driver, event) -- luacheck: ignore 212
		if event and event.type then
			log.debug(string.format("📨 DRIVER EVENT: Received event type '%s'", event.type))

			-- Specifically log driver_lifecycle events
			if event.type == "driver_lifecycle" then
				log.info(string.format("🔄 DRIVER LIFECYCLE EVENT: %s", tostring(event.data or "no data")))
			end
		end
	end,

	-- Capability command handlers
	capability_handlers = handlers_module.capability_handlers,

	-- Complete set of supported SmartThings capabilities
	supported_capabilities = {
		-- Standard SmartThings capabilities
		capabilities.switch,
		capabilities.temperatureMeasurement,
		capabilities.thermostatHeatingSetpoint,
		capabilities.powerMeter,
		capabilities.panicAlarm,
		capabilities.refresh,

		-- Custom Pit Boss specific capabilities
		custom_caps.lightControl,
		custom_caps.primeControl,
		custom_caps.grillTemp,
		custom_caps.temperatureProbes,
		custom_caps.pelletStatus,
		custom_caps.temperatureUnit,
		custom_caps.grillStatus,
	},
})

-- ============================================================================
-- DRIVER STARTUP AND GLOBAL REGISTRATION
-- ============================================================================

-- Register driver globally for fallback access by other modules
_G.current_driver = pitboss_driver

-- Add threading capabilities to the driver for discovery and other operations
if not pitboss_driver.thread then
	-- Try to load st.timer, but handle gracefully if it's not available
	local st_timer_loaded, st_timer = pcall(require, "st.timer")
	if st_timer_loaded and st_timer then
		pitboss_driver.thread = {
			call_with_delay = function(delay, func)
				return st_timer.call_with_delay(delay, func)
			end,
			call_on_schedule = function(delay, func, name)
				return st_timer.call_on_schedule(delay, func, name)
			end,
		}
		log.debug("Added threading capabilities to driver using st.timer")
	else
		-- Fallback: create a basic threading implementation with actual timer execution
		local active_timers = {}
		local timer_counter = 0
		local timer_thread_running = false

		-- Function to start the timer execution thread
		local function start_timer_thread()
			if timer_thread_running then
				return
			end
			timer_thread_running = true

			-- Start a background thread to check and execute timers
			cosock.spawn(function()
				log.debug("Timer execution thread started")
				while timer_thread_running do
					local current_time = os.time()
					local timers_to_execute = {}

					-- Find expired timers
					for timer_id, timer_info in pairs(active_timers) do
						if current_time >= timer_info.scheduled then
							table.insert(timers_to_execute, { id = timer_id, func = timer_info.func })
						end
					end

					-- Execute expired timers
					for _, timer_data in ipairs(timers_to_execute) do
						local success, err = pcall(timer_data.func)
						if not success then
							log.error(string.format("Timer execution failed for %s: %s", timer_data.id, err))
						else
							log.debug(string.format("Executed timer: %s", timer_data.id))
						end
						active_timers[timer_data.id] = nil
					end

					-- Sleep for 1 second before checking again
					cosock.socket.sleep(1)
				end
				log.debug("Timer execution thread stopped")
			end)
		end

		pitboss_driver.thread = {
			call_with_delay = function(delay, func)
				if type(func) == "function" then
					timer_counter = timer_counter + 1
					local timer_id = string.format("timer_%d_%d", os.time(), timer_counter)
					active_timers[timer_id] = {
						func = func,
						delay = delay,
						scheduled = os.time() + delay,
					}
					log.debug(string.format("Scheduled timer for %d seconds (timer_id: %s)", delay, timer_id))

					-- Start the timer thread if not already running
					start_timer_thread()

					return {
						cancel = function()
							if active_timers[timer_id] then
								active_timers[timer_id] = nil
								log.debug(string.format("Cancelled timer: %s", timer_id))
							end
						end,
					}
				end
				return { cancel = function() end }
			end,
			call_on_schedule = function(delay, func, _name) -- luacheck: ignore 212
				return pitboss_driver.thread.call_with_delay(delay, func)
			end,
			stop = function()
				timer_thread_running = false
				active_timers = {}
				log.debug("Timer system stopped")
			end,
		}
		log.debug("Added fallback threading capabilities to driver (st.timer not available)")
	end
end

-- Add cleanup handler for graceful shutdown
local function cleanup_driver()
	log.info("Cleaning up Pit Boss Grill Driver...")

	-- Perform comprehensive shutdown cleanup
	shutdown_cleanup(pitboss_driver)

	log.info("Driver cleanup completed")
end

-- Register cleanup handler (if available in the environment)
---@diagnostic disable: undefined-field
if _G and _G.register_cleanup_handler then
	_G.register_cleanup_handler(cleanup_driver)
end

-- Start the driver and begin processing SmartThings events
log.info("Starting Pit Boss Grill SmartThings Edge Driver")

-- Add signal handler for termination detection (if available)
if _G and _G.signal then
	_G.signal("SIGTERM", function()
		log.warn("🚨 DRIVER TERMINATION: Received SIGTERM signal")
		-- Perform comprehensive shutdown cleanup
		shutdown_cleanup(pitboss_driver)
		cleanup_driver()
	end)

	_G.signal("SIGINT", function()
		log.warn("🚨 DRIVER TERMINATION: Received SIGINT signal")
		-- Perform comprehensive shutdown cleanup
		shutdown_cleanup(pitboss_driver)
		cleanup_driver()
	end)
end
---@diagnostic enable: undefined-field

-- Monitor for os.exit calls by wrapping the driver run
local driver_run_success, driver_run_error = pcall(function()
	log.info("🚀 Driver event loop starting...")
	pitboss_driver:run()
end)

if not driver_run_success then
	log.error(string.format("🚨 DRIVER CRASH: Driver run failed with error: %s", tostring(driver_run_error)))
	log.error("Stack trace:", debug.traceback())
	-- Perform comprehensive shutdown cleanup on crash
	shutdown_cleanup(pitboss_driver)
	cleanup_driver()
else
	log.info("✅ Driver event loop ended normally")
	-- Perform comprehensive shutdown cleanup on normal exit
	shutdown_cleanup(pitboss_driver)
end