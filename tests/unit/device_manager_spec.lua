-- Comprehensive device_manager tests using config constants
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Use real virtual_device_manager module
package.loaded["virtual_device_manager"] = nil

-- Use real network_utils but mock the network-dependent functions
package.loaded["cosock"] = require("tests.mocks.cosock")
package.loaded["pitboss_api"] = {
  get_status = function(ip) return {grillTemp = 200, connected = true} end,
  send_command = function(ip, cmd) return true end,
  get_system_info = function(ip) return {id = "test-device-id"} end,
  set_temperature = function(ip, temp) return true end,
  set_power = function(ip, state) return true end,
  set_light = function(ip, state) return true end,
  set_prime = function(ip, state) return true end,
  set_unit = function(ip, unit) return true end
}
package.loaded["network_utils"] = nil

local device_manager = require("device_manager")

-- Test device setup
local dev = Device:new({})
dev.id = "test-device-id"
dev.preferences = { 
  refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL,
  ipAddress = "192.168.1.100"
}
function dev:get_field(key) return nil end
function dev:set_field(key, value) end
function dev:emit_event(event) end
function dev:get_latest_state(component, cap_id, attr) return "off" end

local mock_driver = {
  environment_info = {
    hub_ipv4 = "192.168.1.50"
  }
}

-- Test 1: Device initialization
if device_manager.initialize_device then
  local init_result = device_manager.initialize_device(dev, mock_driver)
  assert_eq(type(init_result), "boolean", "initialize_device should return boolean")
end

-- Test 2: Device configuration update
if device_manager.update_device_config then
  local config_result = device_manager.update_device_config(dev, mock_driver)
  assert_eq(type(config_result), "boolean", "update_device_config should return boolean")
end

-- Test 3: Device state management
if device_manager.update_device_state then
  local state_data = {
    grillTemp = 225,
    targetTemp = 250,
    connected = true
  }
  device_manager.update_device_state(dev, state_data, mock_driver)
  -- Should complete without error
end

-- Test 4: Device cleanup
if device_manager.cleanup_device then
  device_manager.cleanup_device(dev, mock_driver)
  -- Should complete without error
end

-- Test 5: Device validation
if device_manager.validate_device then
  local validation_result = device_manager.validate_device(dev)
  assert_eq(type(validation_result), "boolean", "validate_device should return boolean")
end

-- Test 6: Device preferences handling
if device_manager.handle_preferences_changed then
  local old_prefs = { ipAddress = "192.168.1.99" }
  local new_prefs = { ipAddress = "192.168.1.100" }
  device_manager.handle_preferences_changed(dev, old_prefs, new_prefs, mock_driver)
  -- Should complete without error
end

-- Add mock for the missing network_utils functions that device_manager needs
local function setup_enhanced_mocks()
  
  -- Mock device_status_service 
  package.loaded["device_status_service"] = {
    set_status_message = function(device, message) 
      device.last_status_message = message
    end
  }
  
  -- Mock health_monitor
  package.loaded["health_monitor"] = {
    start_monitoring = function(device, driver) end,
    stop_monitoring = function(device) end
  }
end

setup_enhanced_mocks()

-- Test 7: Discovery handling for new device
local grill_data = {
  id = "new-device-id",
  ip = "192.168.1.101"
}
mock_driver.try_create_device = function(device_request) return true end
local discovery_result = device_manager.handle_discovered_grill(mock_driver, grill_data)
assert_eq(discovery_result, true, "should handle new device discovery")

-- Test 8: Discovery handling for existing device  
mock_driver.existing_device = dev
grill_data = {
  id = "existing-device-id", 
  ip = "192.168.1.102"
}
local existing_discovery_result = device_manager.handle_discovered_grill(mock_driver, grill_data)
assert_eq(existing_discovery_result, true, "should handle existing device discovery")

-- Test 9: Device metadata extraction
dev.metadata = "{\"ip\":\"192.168.1.100\",\"mac\":\"aa:bb:cc:dd:ee:ff\"}"
device_manager.extract_device_metadata(dev)
-- Should complete without error

-- Test 10: Preference changes handling (simplified to avoid network calls)
local old_prefs = { ipAddress = "192.168.1.99", autoRediscovery = false }
local new_prefs = { ipAddress = "192.168.1.100", autoRediscovery = false } -- Keep autoRediscovery false to avoid network scanning
device_manager.handle_preference_changes(dev, mock_driver, old_prefs, new_prefs)
-- Should complete without error

-- Test 11: Device resource cleanup
device_manager.cleanup_device_resources(dev)
-- Should complete without error

-- Test 12: Module structure validation
assert_eq(type(device_manager), "table", "device_manager should be a module table")