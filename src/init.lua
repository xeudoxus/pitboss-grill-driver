--[[
  Pit Boss Grill SmartThings Edge Driver - Main Entry Point
  Created by: xeudoxus
  Version: 1.0.0
  
  This is the main driver entry point that orchestrates device lifecycle management,
  intelligent health monitoring, and efficient resource utilization for Pit Boss WiFi grills.

  Features:
    - Separation of concerns with dedicated service modules
    - Error handling and recovery mechanisms
    - Efficient resource management
    - Configuration management
    - Logging and debugging capabilities

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk.
--]]

local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

-- Import core modules with clear dependency hierarchy
local custom_caps = require "custom_capabilities"
local network_utils = require "network_utils"
local device_manager = require "device_manager"
local handlers_module = require "capability_handlers"
local health_monitor = require "health_monitor"
local virtual_device_manager = require "virtual_device_manager"
local panic_manager = require "panic_manager"

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
    log.error(string.format("%s called with invalid device object (type: %s, value: %s)", fn_name, type(device), tostring(device)))
    return false
  end
  return true
end

--- Force capability refresh for device profile updates
-- @param driver SmartThings driver object
-- @param device SmartThings device object
local function force_capability_refresh(driver, device)
  -- Force a profile metadata update to refresh capabilities
  local success, err = pcall(function()
    -- Get the profile ID as a string instead of passing the whole profile object
    local profile_id = device.profile_id or (device.profile and device.profile.id)
    if profile_id then
      device:try_update_metadata({profile = profile_id})
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
  if not network_utils.can_attempt_rediscovery(device) then
    return false
  end
  
  if not network_utils.should_attempt_rediscovery(device) then
    return false
  end
  
  device_manager.mark_rediscovery_attempt(device)
  log.info("Attempting rediscovery during initialization")
  
  if network_utils.rediscover_device(device, driver) then
    if network_utils.health_check(device, driver) then
      device:online()
      log.info("Device successfully rediscovered and online")
      
      -- Initialize device status after successful rediscovery
      local status = network_utils.get_status(device, driver)
      if status then
        handlers_module.update_device_from_status(device, status)
        panic_manager.update_last_active_time_if_on(device, status)
      end
      
      return true
    end
  end
  
  return false
end

--- Perform initial device setup with comprehensive error handling
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @return boolean True if initialization was successful
local function perform_initial_setup(driver, device)
  local ip = device_manager.get_device_ip(device)
  
  if not ip then
    log.info("No IP found during initialization, marking offline until discovery")
    device:offline()
    return false
  end
  
  log.debug(string.format("Attempting initial setup for device at IP: %s", ip))
  
  -- Perform health check with timeout
  if network_utils.health_check(device, driver) then
    device:online()
    log.info(string.format("Device successfully initialized and online at %s", ip))
    
    -- Initialize device status
    local status = network_utils.get_status(device, driver)
    if status then
      handlers_module.update_device_from_status(device, status)
      panic_manager.update_last_active_time_if_on(device, status)
    end
    
    -- Force capability refresh to ensure platform recognizes updated capabilities
    force_capability_refresh(driver, device)
    
    -- Create virtual devices based on preferences
    virtual_device_manager.manage_virtual_devices(driver, device)
    
    return true
  else
    log.warn(string.format("Initial health check failed for device at %s", ip))
    
    -- Attempt rediscovery if appropriate
    if attempt_initialization_rediscovery(device, driver) then
      return true
    end
    
    log.warn("Device initialization failed, marking offline")
    device:offline()
    return false
  end
end

--- Device initialization with intelligent health monitoring setup
-- @param driver SmartThings driver object
-- @param device SmartThings device object
local function device_init(driver, device)
  if not validate_driver_and_device(driver, device, "device_init") then return end
  
  log.info(string.format("Initializing Pit Boss Grill device: %s", tostring(device.id)))

  -- Handle virtual device initialization
  if device.parent_assigned_child_key then
    log.info(string.format("Initializing virtual device: %s (%s)", 
             device.label or "Unknown", device.parent_assigned_child_key))
    device:online()
    return
  end

  -- Initialize main grill device
  -- Ensure baseline state fields exist before any status/health logic
  if device and not device.parent_assigned_child_key then
    local ok, err = pcall(function() require("device_manager").initialize_device_state(device) end)
    if not ok then
      log.warn(string.format("initialize_device_state failed: %s", tostring(err)))
    end
  end

  local init_success = perform_initial_setup(driver, device)
  
  -- Initialize virtual devices
  virtual_device_manager.initialize_virtual_devices(driver, device, init_success)
  
  -- Set up health monitoring with proper parameter validation
  log.debug("Setting up health monitoring...")
  if type(device) == "table" and device.id then
    health_monitor.setup_monitoring(driver, device)
  else
    log.error("Cannot setup health monitoring - invalid device object")
  end
  
  log.info(string.format("Pit Boss Grill initialization %s with adaptive monitoring", 
           init_success and "completed successfully" or "completed with warnings"))
end

--- Handle device addition with metadata extraction and initialization
-- @param driver SmartThings driver object
-- @param device SmartThings device object
local function device_added(driver, device)
  if not validate_driver_and_device(driver, device, "device_added") then return end
  
  log.info(string.format("Pit Boss Grill device added: %s", tostring(device.id)))
  
  -- Skip initialization for virtual devices
  if device.parent_assigned_child_key then
    log.info(string.format("Skipping initialization for virtual device: %s (%s)", 
             device.label or "Unknown", device.parent_assigned_child_key))
    device:online()
    return
  end
  
  -- Extract and store device metadata
  device_manager.extract_device_metadata(device)
  
  -- Initialize device
  device_init(driver, device)
end

--- Handle device removal with cleanup
-- @param driver SmartThings driver object
-- @param device SmartThings device object
local function device_removed(driver, device)
  if not validate_driver_and_device(driver, device, "device_removed") then return end
  
  log.info(string.format("Pit Boss Grill device removed: %s", tostring(device.id)))
  
  -- Skip cleanup for virtual devices
  if device.parent_assigned_child_key then
    log.info(string.format("Virtual device removed: %s (%s)", 
             device.label or "Unknown", device.parent_assigned_child_key))
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
-- @param new_prefs table New preferences
local function device_info_changed(driver, device, event, old_prefs, new_prefs)
  if not validate_driver_and_device(driver, device, "device_info_changed") then return end
  
  log.info(string.format("Device info changed for %s (old_prefs: %s, new_prefs: %s)", 
           tostring(device.id), old_prefs and "present" or "nil", new_prefs and "present" or "nil"))

  -- Skip preference handling for virtual devices
  if device.parent_assigned_child_key then
    log.debug(string.format("Skipping preference handling for virtual device: %s", 
             device.parent_assigned_child_key))
    return
  end

  -- Process preference changes
  device_manager.handle_preference_changes(device, driver, old_prefs, new_prefs)
  
  -- Update virtual devices if needed
  virtual_device_manager.handle_preference_changes(driver, device, old_prefs, new_prefs)
  
  log.debug("Preference change processing completed")
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
    removed = device_removed
  },
  
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
    custom_caps.grillStatus
  }
})

-- ============================================================================
-- DRIVER STARTUP AND GLOBAL REGISTRATION
-- ============================================================================

-- Register driver globally for fallback access by other modules
_G.current_driver = pitboss_driver

-- Start the driver and begin processing SmartThings events
log.info("Starting Pit Boss Grill SmartThings Edge Driver v1.0.0")
pitboss_driver:run()