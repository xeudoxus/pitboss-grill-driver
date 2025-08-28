--[[
  Device Discovery Handler for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 1.0.0
  
  This module provides intelligent network discovery for Pit Boss grills with optimized
  scanning algorithms, comprehensive error handling, and efficient resource utilization.
  
  Key Features:
  - Intelligent network subnet detection with fallback mechanisms
  - Optimized concurrent scanning with configurable limits
  - Comprehensive error handling and recovery
  - Smart discovery timing and resource management
  - Detailed logging and performance monitoring
  - Graceful handling of network topology changes
  
  Performance Optimizations:
  - Efficient subnet calculation with caching
  - Concurrent scanning with thread management
  - Early termination on discovery completion
  - Minimal network overhead with targeted scanning
  - Smart retry logic for transient failures
  
  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local log = require "log"
local config = require "config"
local network_utils = require "network_utils"
local device_manager = require "device_manager"

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get current timestamp for performance monitoring
-- @return number Current Unix timestamp
local function get_current_time()
  return os.time()
end

--- Validate and optimize IP scanning range based on network conditions
-- @param start_ip number Requested start IP
-- @param end_ip number Requested end IP
-- @return number, number Validated and optimized start and end IPs
local function optimize_scan_range(start_ip, end_ip)
  -- Ensure valid range bounds
  local optimized_start = math.max(config.CONSTANTS.MIN_SCAN_RANGE, start_ip or config.CONSTANTS.DEFAULT_SCAN_START_IP)
  local optimized_end = math.min(config.CONSTANTS.MAX_SCAN_RANGE, end_ip or config.CONSTANTS.DEFAULT_SCAN_END_IP)
  
  -- Ensure start is not greater than end
  if optimized_start > optimized_end then
    optimized_start = config.CONSTANTS.MIN_SCAN_RANGE
    optimized_end = config.CONSTANTS.MAX_SCAN_RANGE
  end
  
  return optimized_start, optimized_end
end

-- ============================================================================
-- DISCOVERY IMPLEMENTATION
-- ============================================================================

--- Main discovery function with comprehensive error handling and performance monitoring
-- Called by SmartThings framework to discover Pit Boss grills on the network
-- @param driver SmartThings driver object
-- @param opts table Discovery options (unused but required by framework)
-- @param should_continue function Callback to check if discovery should continue
local function discovery_handler(driver, opts, should_continue)
  local discovery_start_time = get_current_time()
  
  log.info("=== Pit Boss Grill Discovery Started ===")
  log.debug(string.format("Discovery initiated with options: %s", opts and "provided" or "none"))

  -- Validate basic discovery parameters
  local function validate_discovery_params()
    if not should_continue or type(should_continue) ~= "function" then
      log.debug("No should_continue callback provided; assuming always continue")
    end
  end
  validate_discovery_params()

  -- Validate driver parameter
  if not driver then
    log.error("No driver provided to discovery handler")
    return
  end

  -- Determine hub IP address with comprehensive error handling
  local hub_ipv4 = network_utils.find_hub_ip(driver)
  if not hub_ipv4 then
    log.error("Cannot determine hub IP address - discovery aborted")
    return
  end
  
  log.info(string.format("Hub IP detected: %s", hub_ipv4))
  
  -- Extract network subnet for scanning
  local subnet = network_utils.get_subnet_prefix(hub_ipv4)
  if not subnet then 
    log.error(string.format("Cannot determine network subnet from hub IP: %s", hub_ipv4))
    return 
  end
  
  log.info(string.format("Network subnet determined: %s", subnet))

  -- Optimize scanning range for performance
  local start_ip, end_ip = optimize_scan_range(
    config.CONSTANTS.DEFAULT_SCAN_START_IP,
    config.CONSTANTS.DEFAULT_SCAN_END_IP
  )
  
  local scan_range = end_ip - start_ip + 1
  log.info(string.format("Optimized scan range: %s.%d to %s.%d (%d addresses)", 
           subnet, start_ip, subnet, end_ip, scan_range))

  -- Track discovery statistics
  local discovered_count = 0
  local scan_start_time = get_current_time()

  -- Execute network scan with callback for discovered devices
  network_utils.scan_for_grills(
    driver,
    subnet,
    start_ip,
    end_ip,
    function(grill_data, driver_ref)
      -- Validate discovered grill data
      if not grill_data or not grill_data.id or not grill_data.ip then
        log.warn("Invalid grill data received from network scan")
        return
      end
      
      discovered_count = discovered_count + 1
      log.info(string.format("Processing discovered grill #%d: %s at %s", 
               discovered_count, grill_data.id, grill_data.ip))
      
      -- Handle discovered grill with error protection
      local success, err = pcall(function()
        device_manager.handle_discovered_grill(driver_ref, grill_data)
      end)
      
      if not success then
        log.error(string.format("Failed to handle discovered grill %s: %s", 
                  grill_data.id, err or "unknown error"))
      else
        log.debug(string.format("Successfully processed grill: %s", grill_data.id))
      end
    end
  )
  
  log.info(string.format("Network scan initiated: %s.%d to %s.%d (%d addresses)", 
           subnet, start_ip, subnet, end_ip, scan_range))
  log.info("Discovery running in background - devices will be added as found")
end

return discovery_handler