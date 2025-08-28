--[[
  Health Monitor Service for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 1.0.0
   
  Manages adaptive health monitoring with intelligent scheduling based on grill activity.
  Handles device connectivity checks, rediscovery attempts, and panic state management.
  
  Features:
  - Adaptive monitoring intervals based on grill state
  - Intelligent rediscovery scheduling
  - Panic state management for safety
  - Resource-efficient monitoring
--]]

local capabilities = require "st.capabilities"
local log = require "log"
---@type Config
local config = require "config"
local network_utils = require "network_utils"
local panic_manager = require "panic_manager"

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
  
  -- If no timer ID or it's very old, consider inactive
  if not timer_id or (current_time - last_scheduled) > 7200 then -- 2 hours max
    return false
  end
  
  return true
end

--- Mark that a health timer is active
-- @param device SmartThings device object
-- @param timer_id string Timer identifier
local function mark_health_timer_active(device, timer_id)
  device:set_field("health_timer_id", timer_id, {persist = true})
  device:set_field("last_health_scheduled", os.time(), {persist = true})
  log.debug(string.format("Marked health timer active: %s", timer_id))
end

--- Clear health timer tracking
-- @param device SmartThings device object
local function clear_health_timer_tracking(device)
  device:set_field("health_timer_id", nil, {persist = true})      -- Clear from persistent storage
  device:set_field("last_health_scheduled", nil, {persist = true}) -- Clear from persistent storage
  log.debug("Cleared health timer tracking")
end

--- Ensure exactly one health timer is running
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
-- @param force_restart boolean Force restart even if timer appears active
function health_monitor.ensure_health_timer_active(driver, device, force_restart)
  if force_restart then
    log.info("Force restarting health timer as requested")
    clear_health_timer_tracking(device)
  end
  
  if not is_health_timer_active(device) then
    log.warn("No active health timer detected - starting new timer")
    health_monitor.schedule_next_health_check(driver, device)
    return true -- Started new timer
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
-- preheating, or inactive. The result is clamped between a minimum and maximum
-- interval to prevent overly aggressive or sparse polling.
-- @param device SmartThings device object
-- @param is_active boolean True if grill switch is ON
-- @return number Calculated interval in seconds
function health_monitor.compute_interval(device, is_active)
  -- Get the base refresh interval from the device preferences, with a fallback to the default.
  local base_interval = config.get_refresh_interval(device)

  local multiplier
  if is_active then
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
  return math.max(config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL, math.min(interval, config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL))
end

--- Schedule the next health check
-- This function is called from the main driver thread
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
function health_monitor.schedule_next_health_check(driver, device) 
  local switch_state = device:get_latest_state(config.COMPONENTS.GRILL, capabilities.switch.ID, capabilities.switch.switch.NAME)
  local interval = health_monitor.compute_interval(device, switch_state == "on")
  
  -- Clamp interval to prevent timer overflow after long sessions
  -- SmartThings timers may have problems with very large delay values
  local max_safe_interval = config.CONSTANTS.MAX_HEALTH_INTERVAL_HOURS
  local safe_interval = math.min(interval, max_safe_interval)
  
  if safe_interval ~= interval then
    log.warn(string.format("Clamped health check interval from %d to %d seconds to prevent timer overflow", interval, safe_interval))
  end
  
  -- Generate unique timer ID for tracking
  local timer_id = string.format("health_check_%d_%d", os.time(), math.random(1000, 9999))
  
  device.thread:call_with_delay(safe_interval, function()
    -- Clear timer tracking since this timer is now executing
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
  
  -- Mark timer as active
  mark_health_timer_active(device, timer_id)
  
  log.info(string.format("Successfully scheduled next health check in %d seconds (timer: %s)", safe_interval, timer_id))
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

  -- Mark that we are polling to prevent re-entrancy
  device:set_field("is_polling", true, {persist = true})

  -- Use get_status instead of send_command with "status" + crash protection
  log.debug(string.format("Performing health check for device: %s", device.label or device.id))
  
  local status_info = nil
  local success, err = pcall(function()
    status_info = network_utils.get_status(device, driver)
  end)
  
  -- Always clear polling flag, even if crash occurred
  device:set_field("is_polling", false, {persist = true})
  
  if not success then
    log.error(string.format("Health check crashed for device %s: %s", device.label or device.id, err))
    status_info = nil -- Treat crash as failure
  end

  if status_info then
    -- Grill is healthy and responsive
    log.info(string.format("Health check successful for %s. Grill is online.", device.label))
    
    -- Mark device as online in SmartThings
    device:online()
    device:set_field("is_connected", true, {persist = true})
    
    -- Clear panic state if panic_manager supports it
    if panic_manager.clear_panic_state then
      panic_manager.clear_panic_state(device)
    end

    -- Update device status based on the received information
    -- Use device_status_service directly to avoid circular dependencies
    local device_status_service = require "device_status_service"
    local virtual_device_manager = require "virtual_device_manager"
    
    local ok, err = pcall(function()
      device_status_service.update_device_status(device, status_info)
      virtual_device_manager.update_virtual_devices(device, status_info)
    end)
    
    if not ok then
      log.error(string.format("Failed to update device status during health check: %s", tostring(err)))
    end

    -- Schedule the next check based on the new status with error handling
    local schedule_success = pcall(health_monitor.schedule_next_health_check, driver, device)
    if not schedule_success then
      log.error("Failed to schedule next health check - attempting fallback scheduling")
      -- Clear any stale timer tracking and try fallback
      clear_health_timer_tracking(device)
      pcall(function()
        local fallback_timer_id = string.format("health_fallback_%d_%d", os.time(), math.random(1000, 9999))
        device.thread:call_with_delay(config.CONSTANTS.DEFAULT_REFRESH_INTERVAL, function()
          clear_health_timer_tracking(device)
          health_monitor.do_health_check(driver, device)
        end, fallback_timer_id)
        mark_health_timer_active(device, fallback_timer_id)
      end)
    end

  else
    -- Grill is unresponsive or offline
    log.warn(string.format("Health check failed for %s. Grill may be offline or unreachable.", device.label))

    -- Mark device as offline in SmartThings
    device:offline()
    device:set_field("is_connected", false, {persist = true})
    log.info(string.format("Marked device %s as offline", device.label or device.id))

    -- Handle panic state for recently active grills
    panic_manager.handle_offline_panic_state(device)
    
    -- Still try to schedule next check even when offline (for recovery)
    local schedule_success = pcall(health_monitor.schedule_next_health_check, driver, device)
    if not schedule_success then
      log.error("Failed to schedule next health check while offline - attempting fallback scheduling")
      clear_health_timer_tracking(device)
      pcall(function()
        local fallback_timer_id = string.format("health_offline_fallback_%d_%d", os.time(), math.random(1000, 9999))
        device.thread:call_with_delay(config.CONSTANTS.DEFAULT_REFRESH_INTERVAL, function()
          clear_health_timer_tracking(device)
          health_monitor.do_health_check(driver, device)
        end, fallback_timer_id)
        mark_health_timer_active(device, fallback_timer_id)
      end)
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

  -- Perform an initial health check immediately to get a baseline
  log.info(string.format("Setting up health monitoring for %s...", device.label))
  health_monitor.do_health_check(driver, device)
end

--- Perform a comprehensive timer health check and recovery
-- This can be called periodically or when problems are suspected
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
-- @return boolean True if timer was restarted
function health_monitor.check_and_recover_timer(driver, device)
  log.debug("Performing comprehensive timer health check")
  
  local timer_was_missing = not is_health_timer_active(device)
  local timer_restarted = health_monitor.ensure_health_timer_active(driver, device, false)
  
  if timer_restarted then
    log.warn("Timer health check detected missing timer - recovery initiated")
  else
    log.debug("Timer health check passed - timer is active")
  end
  
  return timer_restarted
end

--- Force restart the health monitoring timer
-- Use this when you suspect the timer is stuck or corrupted
-- @param driver The SmartThings driver object
-- @param device The SmartThings device object
function health_monitor.force_restart_timer(driver, device)
  log.info("Force restarting health monitoring timer")
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
    -- Clear timer tracking
    clear_health_timer_tracking(device)
  end
  
  log.debug("Health monitor cleanup completed.")
end

return health_monitor