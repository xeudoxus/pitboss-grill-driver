--[[
  Device Manager for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 1.0
  
  This module provides device lifecycle management for Pit Boss grills,
  including device discovery coordination, metadata handling, preference
  management, and device state initialization.
  
  Key Features:
  - Device discovery coordination and creation
  - Preference change handling and validation
  - Device metadata extraction and storage
  - Device lifecycle state management
  - Resource cleanup and memory management
  - Device state initialization and reset
  - Connection status tracking and management
  - Backward compatibility wrappers for IP operations
  
  Note: IP address resolution and validation is now handled by network_utils
  which provides cached validation, priority-based source selection, and
  optimized metadata parsing with automatic cleanup.
  
  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

-- ============================================================================
-- MODULE DEPENDENCIES
-- ============================================================================

local log = require "log"
local json = require "st.json"
---@type Config
local config = require "config"
local network_utils = require "network_utils"
local device_status_service = require "device_status_service"
local health_monitor = require "health_monitor"

local device_manager = {}

-- ============================================================================
-- CONSTANTS AND CONFIGURATION
-- ============================================================================

-- Fields that should be cleared during resource cleanup
local CLEANUP_FIELDS = {
  "ip_address", "mac_address", "last_health_check", "last_rediscovery_attempt",
  "grill_start_time", "session_reached_temp", "last_target_temp", "panic_state", 
  "last_active_time", "last_periodic_rediscovery", "rediscovery_in_progress"
}

-- Fields that should be reset during operational state reset
local OPERATIONAL_RESET_FIELDS = {
  "grill_start_time", "last_target_temp", "session_reached_temp",
  "is_preheating", "is_heating", "is_cooling"
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Clear multiple persisted fields on a device
-- @param device SmartThings device object
-- @param fields table Array of field names to clear
local function clear_fields(device, fields)
  for _, field_name in ipairs(fields) do
    device:set_field(field_name, nil, {persist = true})  -- Clear from persistent storage
  end
end

--- Get preference value with fallback for quoted keys (SmartThings Edge quirk)
-- @param prefs table Preferences object
-- @param key string Preference key
-- @param default any Default value if not found
-- @return any Preference value or default
local function get_preference(prefs, key, default)
  if not prefs or type(prefs) ~= "table" then
    return default
  end
  
  local value = prefs[key] or prefs[string.format('"%s"', key)]
  return value ~= nil and value or default
end

--- Log preference changes consistently
-- @param key string Preference name
-- @param old_value any Old value
-- @param new_value any New value
-- @param is_initial boolean True if initial setup
local function log_preference_change(key, old_value, new_value, is_initial)
  if is_initial then
    log.debug(string.format("Setting initial %s: %s", key, tostring(new_value)))
  else
    log.info(string.format("%s changed from %s to %s", key, tostring(old_value), tostring(new_value)))
  end
end

-- ============================================================================
-- DISCOVERY SUPPORT
-- ============================================================================

--- Handle discovered grill device data
-- @param driver SmartThings driver object
-- @param grill_data table Must contain id and ip fields
-- @return boolean True if successfully handled
function device_manager.handle_discovered_grill(driver, grill_data)
  -- Validate input parameters
  if not grill_data or not grill_data.id or not grill_data.ip then
    log.warn("Invalid grill data for discovery:", grill_data)
    return false
  end
  
  local network_id = grill_data.id
  local discovered_ip = grill_data.ip
  
  -- Look for existing device
  local existing_device = network_utils.find_device_by_network_id(driver, network_id)
  
  if existing_device then
    -- Handle existing device discovery
    local current_ip = network_utils.resolve_device_ip(existing_device, false)
    local ip_changed = (current_ip ~= discovered_ip)
    
    if ip_changed then
      log.info(string.format("Device IP changed: %s %s -> %s", network_id, current_ip or "unknown", discovered_ip))
      network_utils.update_device_ip(existing_device, discovered_ip)
      device_status_service.set_status_message(existing_device, "Connected (Rediscovered)")
    else
      log.info(string.format("Device found at same IP: %s at %s", network_id, discovered_ip))
      device_status_service.set_status_message(existing_device, "Connected")
    end
    
    log.debug("Discovery status update completed for existing device")
    return true
    
  else
    -- Handle new device creation
    log.info(string.format("Creating new device for grill: %s at %s", network_id, discovered_ip))
    local device_request = network_utils.build_device_profile(grill_data)
    
    if device_request then
      local success, error_msg = pcall(function() 
        driver:try_create_device(device_request) 
      end)
      
      if success then
        log.info(string.format("Device creation request sent for: %s", network_id))
        return true
      else
        log.error(string.format("Failed to create device %s: %s", network_id, error_msg))
        return false
      end
    else
      log.error(string.format("Failed to build device profile for: %s", network_id))
      return false
    end
  end
end

--- Backward compatible wrapper for IP update operations
-- @param device SmartThings device object
-- @param new_ip string New IP address
-- @return boolean True if IP was successfully updated
function device_manager.update_device_ip(device, new_ip)
  return network_utils.update_device_ip(device, new_ip)
end

-- ============================================================================
-- DEVICE METADATA MANAGEMENT
-- ============================================================================

--- Extract and store IP from device metadata if available
-- @param device SmartThings device object
-- @return boolean True if metadata was processed successfully
function device_manager.extract_device_metadata(device)
  if not device.metadata or device.metadata == "" then
    log.debug("No metadata available for device")
    return false
  end
  
  local success, decoded = pcall(json.decode, device.metadata)
  if not success or not decoded or type(decoded) ~= "table" then
    log.warn("Failed to decode device metadata or metadata is invalid")
    return false
  end
  
  local processed_fields = 0
  
  -- Process IP address
  if decoded.ip and type(decoded.ip) == "string" then
    if network_utils.update_device_ip(device, decoded.ip) then
      log.debug(string.format("Updated IP from metadata: %s", decoded.ip))
      processed_fields = processed_fields + 1
    else
      log.warn(string.format("Failed to set IP from metadata: %s", decoded.ip))
    end
  end
  
  -- Process MAC address
  if decoded.mac and type(decoded.mac) == "string" then
    device:set_field("mac_address", decoded.mac, {persist = true})
    log.debug(string.format("Stored MAC address: %s", decoded.mac))
    processed_fields = processed_fields + 1
  end
  
  -- Process device model if available
  if decoded.model and type(decoded.model) == "string" then
    device:set_field("device_model", decoded.model, {persist = true})
    log.debug(string.format("Stored device model: %s", decoded.model))
    processed_fields = processed_fields + 1
  end
  
  return processed_fields > 0
end

--- Get device IP address from stored fields or preferences
-- @param device SmartThings device object
-- @return string|nil IP address or nil if not found
function device_manager.get_device_ip(device)
  return network_utils.resolve_device_ip(device, false)
end

--- Clean up device resources when device is removed
-- @param device SmartThings device object
function device_manager.cleanup_device_resources(device)
  clear_fields(device, CLEANUP_FIELDS)
  log.debug("Device resource cleanup completed")
end

--- Mark rediscovery attempt timestamp
-- @param device SmartThings device object
function device_manager.mark_rediscovery_attempt(device)
  local current_time = os.time()
  device:set_field("last_rediscovery_attempt", current_time, {persist = true})
end

-- ============================================================================
-- PREFERENCE CHANGE HANDLERS
-- ============================================================================

--- Handle IP address preference change with validation
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param old_ip string Previous IP address
-- @param new_ip string New IP address
-- @param is_initial_setup boolean True if this is initial device setup
-- @return boolean True if change was handled successfully
local function handle_ip_preference_change(device, driver, old_ip, new_ip, is_initial_setup)
  if old_ip == new_ip or not new_ip then
    return true
  end
  
  -- Allow processing when user switches to rediscovery mode (e.g., custom IP → auto-discovery)
  if network_utils.is_rediscovery_ip(new_ip) then
    log_preference_change("IP address", old_ip, new_ip .. " (auto-discovery)", is_initial_setup)
    return true -- Valid change to auto-discovery mode
  end
  
  -- Validate the new IP address
  local is_valid, error_message = network_utils.validate_ip_address(new_ip)
  
  if not is_valid then
    log.error(string.format("Invalid IP address: %s - %s", new_ip, error_message))
    device_status_service.set_status_message(device, "Error: " .. error_message)
    return false
  end
  
  -- Log the change
  log_preference_change("IP address", old_ip, new_ip, is_initial_setup)
  
  -- Update the IP address
  if not device_manager.update_device_ip(device, new_ip) then
    log.error("Failed to update device IP address")
    device_status_service.set_status_message(device, "Error: Failed to update IP address")
    return false
  end
  
  -- Trigger immediate health check for non-initial setups
  if not is_initial_setup then
    if network_utils.health_check(device, driver) then
      device:online()
      log.info("Device verified online with new IP")
      device_status_service.set_status_message(device, "Connected")
    else
      log.warn("Device not reachable at new IP address")
      device_status_service.set_status_message(device, "Warning: Device not reachable at " .. new_ip)
    end
  end
  
  return true
end

--- Handle auto-rediscovery preference change
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param old_auto_rediscovery boolean Previous auto-rediscovery setting
-- @param new_auto_rediscovery boolean New auto-rediscovery setting
-- @param is_initial_setup boolean True if this is initial device setup
-- @return boolean True if change was handled successfully
local function handle_auto_rediscovery_preference_change(device, driver, old_auto_rediscovery, new_auto_rediscovery, is_initial_setup)
  -- Only process if autoRediscovery preference actually changed
  if old_auto_rediscovery == new_auto_rediscovery then
    return true
  end
  
  log_preference_change("Auto IP Rediscovery", old_auto_rediscovery, new_auto_rediscovery, is_initial_setup)
  
  -- Immediate rediscovery when autoRediscovery preference is enabled
  -- Only if device is offline and IP is set to DEFAULT_IP_ADDRESS
  if new_auto_rediscovery and not old_auto_rediscovery and not is_initial_setup then
    local device_online = device:get_field("is_connected") or false
    local current_ip_pref = get_preference(device.preferences, "ipAddress")
    
    -- Check if IP preference is set to rediscovery-compatible values
    local is_rediscovery_ip = (current_ip_pref == config.CONSTANTS.DEFAULT_IP_ADDRESS or 
                               current_ip_pref == config.CONSTANTS.DEBUG_IP_ADDRESS)
    
    if not device_online and is_rediscovery_ip then
      -- Prevent rapid rediscovery attempts (min 30 seconds between attempts)
      local last_attempt = device:get_field("last_rediscovery_attempt") or 0
      local current_time = os.time()
      local min_interval = 30 -- 30 seconds minimum between rediscovery attempts
      
      if (current_time - last_attempt) < min_interval then
        log.info(string.format("Auto-rediscovery requested but blocked by rate limit (%ds remaining)", 
                 min_interval - (current_time - last_attempt)))
        return true
      end
      
      log.info("Auto-rediscovery enabled for offline device with rediscovery IP - attempting immediate network scan")
      
      -- Update attempt timestamp before starting (prevents multiple rapid calls)
      device:set_field("last_rediscovery_attempt", current_time, {persist = true})
      
      -- Attempt rediscovery (flood protection is now handled inside rediscover_device function)
      if network_utils.rediscover_device(device, driver) then
        if network_utils.health_check(device, driver) then
          device:online()
          log.info("Device successfully rediscovered after enabling auto-rediscovery")
          device_status_service.set_status_message(device, "Connected (Rediscovered)")
        else
          log.warn("Device rediscovered but health check failed")
        end
      else
        log.info("Immediate rediscovery attempt failed - will retry during normal health checks")
      end
    elseif not device_online and not is_rediscovery_ip then
      log.info("Auto-rediscovery enabled but IP preference is custom (%s) - skipping immediate scan", current_ip_pref)
    else
      log.debug("Auto-rediscovery enabled but device is online - no immediate action needed")
    end
  end
  
  return true
end
--- Handle refresh interval preference change
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param old_interval number Previous refresh interval
-- @param new_interval number New refresh interval
-- @param is_initial_setup boolean True if this is initial device setup
-- @return boolean True if change was handled successfully
local function handle_refresh_interval_change(device, driver, old_interval, new_interval, is_initial_setup)
  if old_interval == new_interval then
    return true
  end
  
  log_preference_change("Refresh interval", old_interval, new_interval, is_initial_setup)
  
  -- Restart timer for non-initial setups to apply new interval
  if not is_initial_setup then
    local timer_restarted = health_monitor.check_and_recover_timer(driver, device)
    if timer_restarted then
      log.info("Refresh interval change triggered timer recovery")
    end
  end
  
  return true
end

-- ============================================================================
-- PREFERENCE MANAGEMENT
-- ============================================================================

--- Handle device preference changes with intelligent reconfiguration
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param old_prefs table Previous preferences
-- @param new_prefs table New preferences
function device_manager.handle_preference_changes(device, driver, old_prefs, new_prefs)
  -- SmartThings Edge sometimes doesn't pass new_prefs correctly, so get them from device
  local current_prefs = new_prefs or device.preferences or {}
  
  if type(current_prefs) ~= "table" then
    log.warn("Device preferences are not available. Ignoring.")
    return
  end
  
  -- Check if this is initial device setup (old_prefs is nil or empty)
  local is_initial_setup = not old_prefs or (type(old_prefs) == "table" and next(old_prefs) == nil)
  
  -- Prevent repeated processing of the same preferences
  -- Don't skip if new_prefs was nil (SmartThings Edge bug) since we can't detect changes
  local prefs_hash = json.encode(current_prefs)
  local last_processed_prefs = device:get_field("last_processed_prefs")
  
  if last_processed_prefs == prefs_hash and not is_initial_setup and new_prefs ~= nil then
    log.debug("Preferences unchanged since last processing, skipping")
    return
  elseif new_prefs == nil and old_prefs then
    log.debug("SmartThings passed nil for new_prefs - forcing preference processing to detect changes")
  end
  
  -- Store the current preferences hash to prevent reprocessing
  device:set_field("last_processed_prefs", prefs_hash, {persist = true})
  
  if is_initial_setup then
    log.debug("Initial device setup detected, applying default preferences without change notifications")
  else
    log.debug("Processing preference changes")
  end
  
  -- Extract preference values (handle quoted keys from SmartThings Edge)
  local old_interval = get_preference(old_prefs, "refreshInterval")
  local new_interval = get_preference(current_prefs, "refreshInterval")
  
  local old_ip = get_preference(old_prefs, "ipAddress")
  local new_ip = get_preference(current_prefs, "ipAddress")
  
  local old_auto_rediscovery = get_preference(old_prefs, "autoRediscovery")
  local new_auto_rediscovery = get_preference(current_prefs, "autoRediscovery")
  
  -- Process each preference change
  local success = true
  
  success = handle_refresh_interval_change(device, driver, old_interval, new_interval, is_initial_setup) and success
  success = handle_ip_preference_change(device, driver, old_ip, new_ip, is_initial_setup) and success
  
  -- Only handle autoRediscovery if it actually changed (avoid triggering on unrelated pref changes)
  if old_auto_rediscovery ~= new_auto_rediscovery or is_initial_setup then
    success = handle_auto_rediscovery_preference_change(device, driver, old_auto_rediscovery, new_auto_rediscovery, is_initial_setup) and success
  else
    log.debug("autoRediscovery preference unchanged, skipping rediscovery handler")
  end
  
  if not success then
    log.warn("One or more preference changes failed to process")
  end
end

--- Get device preferences with safe defaults
-- @param device SmartThings device object
-- @return table Table of device preferences
function device_manager.get_device_preferences(device)
  local prefs = device.preferences or {}
  
  -- Apply safe defaults for essential preferences
  prefs.refreshInterval = prefs.refreshInterval or config.CONSTANTS.DEFAULT_REFRESH_INTERVAL
  prefs.grillOffset = prefs.grillOffset or config.CONSTANTS.DEFAULT_OFFSET
  prefs.probe1Offset = prefs.probe1Offset or config.CONSTANTS.DEFAULT_OFFSET
  prefs.probe2Offset = prefs.probe2Offset or config.CONSTANTS.DEFAULT_OFFSET
  prefs.probe3Offset = prefs.probe3Offset or config.CONSTANTS.DEFAULT_OFFSET
  prefs.probe4Offset = prefs.probe4Offset or config.CONSTANTS.DEFAULT_OFFSET
  
  return prefs
end

--- Check if device preference exists and has a non-default value
-- @param device SmartThings device object
-- @param preference_name string Name of the preference to check
-- @param default_value any Default value to compare against
-- @return boolean True if preference exists and is not the default
function device_manager.has_custom_preference(device, preference_name, default_value)
  local prefs = device.preferences or {}
  local pref_value = get_preference(prefs, preference_name, default_value)
  
  return pref_value ~= nil and pref_value ~= default_value
end

-- ============================================================================
-- DEVICE STATE MANAGEMENT
-- ============================================================================

--- Initialize device state fields with safe defaults
-- @param device SmartThings device object
function device_manager.initialize_device_state(device)
  -- Initialize timing fields
  device:set_field("last_health_check", 0, {persist = true})
  device:set_field("last_rediscovery_attempt", 0, {persist = true})
  device:set_field("last_periodic_rediscovery", 0, {persist = true})
  
  -- Initialize operational state fields
  device:set_field("is_preheating", false, {persist = true})
  device:set_field("is_heating", false, {persist = true})
  device:set_field("is_cooling", false, {persist = true})
  device:set_field("session_reached_temp", false, {persist = true})
  
  -- Initialize panic state fields
  device:set_field("panic_state", false, {persist = true})
  device:set_field("last_active_time", 0, {persist = true})
  
  log.debug("Device state initialized with safe defaults")
end

--- Reset device operational state (called when grill turns off)
-- @param device SmartThings device object
function device_manager.reset_operational_state(device)
  -- Set boolean defaults directly instead of clear+set for efficiency
  device:set_field("grill_start_time", nil, {persist = true})
  device:set_field("last_target_temp", nil, {persist = true})
  device:set_field("session_reached_temp", false, {persist = true})
  device:set_field("is_preheating", false, {persist = true})
  device:set_field("is_heating", false, {persist = true})
  device:set_field("is_cooling", false, {persist = true})

  log.debug("Device operational state reset")
end

--- Get device connection status
-- @param device SmartThings device object
-- @return boolean True if device is considered connected
function device_manager.is_device_connected(device)
  local connected = device:get_field("is_connected")
  return connected ~= nil and connected or false
end

--- Set device connection status
-- @param device SmartThings device object
-- @param connected boolean True if device is connected
function device_manager.set_device_connected(device, connected)
  device:set_field("is_connected", connected, {persist = true})
end

-- ============================================================================
-- DEVICE INFORMATION AND DIAGNOSTICS
-- ============================================================================

--- Get device information summary for logging
-- @param device SmartThings device object
-- @return table Device information summary
function device_manager.get_device_info(device)
  local ip = device_manager.get_device_ip(device)
  local mac = device:get_field("mac_address")
  local unit = device:get_field("temperature_unit") or "F"
  local connected = device_manager.is_device_connected(device)
  
  return {
    id = device.id,
    label = device.label,
    ip_address = ip,
    mac_address = mac,
    temperature_unit = unit,
    connected = connected,
    is_virtual = device.parent_assigned_child_key ~= nil,
    device_model = device:get_field("device_model")
  }
end

--- Log device information for debugging
-- @param device SmartThings device object
-- @param context string Context for the log message
function device_manager.log_device_info(device, context)
  local info = device_manager.get_device_info(device)
  if not info then
    log.error(string.format("%s - Unable to get device info", context))
    return
  end
  
  log.info(string.format("%s - Device: %s, IP: %s, Unit: %s, Connected: %s", 
    context, info.label or info.id, info.ip_address or "none", 
    info.temperature_unit, tostring(info.connected)))
end

return device_manager