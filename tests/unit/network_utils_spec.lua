-- Comprehensive network_utils tests using config constants and mocked network
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Set up package path
package.path = "src/?.lua;tests/mocks/?.lua;tests/mocks/?/init.lua;" .. package.path

local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Mock dependencies
package.loaded["pitboss_api"] = {
  get_status = function(ip) return {grillTemp = 200, connected = true} end,
  send_command = function(ip, cmd) return true end,
  clear_auth_cache = function() end,
  get_system_info = function(ip) return {id = "test-device-id", version = "1.0", app = "PitBoss"} end,
  get_firmware_version = function(ip) return "1.2.3" end,
  is_firmware_valid = function(version) return true end,
  set_temperature = function(ip, temp) return true end,
  set_power = function(ip, state) return true end,
  set_light = function(ip, state) return true end,
  set_prime = function(ip, state) return true end,
  set_unit = function(ip, unit) return true end
}

package.loaded["cosock"] = {
  socket = {
    tcp = function()
      return {
        settimeout = function() end,
        connect = function() return true end,
        send = function() return 100 end,
        receive = function() return "HTTP/1.1 200 OK" end,
        close = function() end
      }
    end,
    sleep = function(seconds) end
  },
  spawn = function(func) func() end
}

-- Clear any cached network_utils to ensure fresh load with mocks
package.loaded["network_utils"] = nil
local network_utils = require("network_utils")

-- Test 1: Module structure validation
assert_eq(type(network_utils), "table", "network_utils should be a module table")
assert_eq(type(network_utils.validate_ip_address), "function", "validate_ip_address should be a function")

-- Test 2: IP address validation
local valid_ip, valid_msg = network_utils.validate_ip_address("192.168.1.100")
assert_eq(valid_ip, true, "should validate correct IP address")

local invalid_ip, invalid_msg = network_utils.validate_ip_address("999.999.999.999")
assert_eq(invalid_ip, false, "should reject IP with segments > 255")

local invalid_format, format_msg = network_utils.validate_ip_address("not.an.ip")
assert_eq(invalid_format, false, "should reject non-numeric format")

-- Test 2: Rediscovery decision logic
-- Mock os.time for rediscovery test
local original_os_time = os.time
local mock_time = 1000 -- Start time for the test
os.time = function() return mock_time end

local dev = Device:new({})
dev.preferences = { 
  refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL,
  ipAddress = "192.168.1.100"
}
function dev:get_field(key) 
  if key == "last_rediscovery" then return mock_time - 120 end -- 2 minutes ago
  if key == "ip_address" then return "192.168.1.100" end
  return nil 
end

local should_rediscover = network_utils.should_attempt_rediscovery(dev)
assert_eq(type(should_rediscover), "boolean", "should_attempt_rediscovery should return boolean")

-- Restore original os.time after the test
os.time = original_os_time

-- Test 3: Network cache cleanup
network_utils.cleanup_network_cache()
-- Should complete without error

-- Test 4: Subnet prefix extraction
local subnet = network_utils.get_subnet_prefix("192.168.1.100")
assert_eq(subnet, "192.168.1", "should extract correct subnet prefix")

-- Test 5: Hub IP finding (mock driver)
local mock_driver = {
  environment_info = {
    hub_ipv4 = "192.168.1.50"
  }
}
local hub_ip = network_utils.find_hub_ip(mock_driver)
assert_eq(hub_ip, "192.168.1.50", "should find hub IP from driver")

-- Test 6: Health check
local health_result = network_utils.health_check(dev, mock_driver)
assert_eq(type(health_result), "boolean", "health_check should return boolean")

-- Test 7: Grill testing at IP
local grill_test = network_utils.test_grill_at_ip("192.168.1.100", "test-device-id")
assert_eq(type(grill_test), "table", "test_grill_at_ip should return table or nil")

-- Test 8: Command sending
function dev:get_latest_state() return "on" end
local cmd_success = network_utils.send_command(dev, "set_temperature", 225, mock_driver)
assert_eq(type(cmd_success), "boolean", "send_command should return boolean")

-- Test 9: Status retrieval
local status_result = network_utils.get_status(dev, mock_driver)
assert_eq(type(status_result), "table", "get_status should return table or nil")

-- Test 10: Cache cleanup scheduling
network_utils.schedule_cache_cleanup(dev, 5)
-- Should complete without error

-- Test 11: IP resolution from multiple sources
local resolved_ip = network_utils.resolve_device_ip(dev, false)
assert_eq(resolved_ip, "192.168.1.100", "should resolve device IP from preferences")

-- Test 12: Update device IP with validation
local update_success = network_utils.update_device_ip(dev, "192.168.1.101")
assert_eq(update_success, true, "should successfully update valid IP")

local update_fail = network_utils.update_device_ip(dev, "invalid.ip")
assert_eq(update_fail, false, "should reject invalid IP update")

-- Test 13: Build device profile from grill data
local grill_data = {
  id = "new-grill-id",
  ip = "192.168.1.102",
  firmware_version = "1.2.5"
}
local device_profile = network_utils.build_device_profile(grill_data)
assert_eq(type(device_profile), "table", "should build device profile")
assert_eq(device_profile.device_network_id, "new-grill-id", "should set correct network ID")
assert_eq(device_profile.type, "LAN", "should set LAN device type")

-- Test 14: Device rediscovery
dev.preferences.autoRediscovery = true
local rediscovery_result = network_utils.rediscover_device(dev, mock_driver)
assert_eq(type(rediscovery_result), "boolean", "rediscover_device should return boolean")

-- Test 15: Test grill at IP
local grill_test = network_utils.test_grill_at_ip("192.168.1.100", "test-device-id")
assert_eq(type(grill_test), "table", "test_grill_at_ip should return table or nil")

-- Test 16: Find device by network ID
dev.network_id = "test-device-id"
mock_driver.get_devices = function() return {dev} end
local found_device = network_utils.find_device_by_network_id(mock_driver, "test-device-id")
assert_eq(found_device, dev, "should find device by network ID")