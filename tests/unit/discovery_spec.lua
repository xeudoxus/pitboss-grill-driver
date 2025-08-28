---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Comprehensive discovery tests using config constants
local config = require("config")

-- Mock dependencies
package.loaded["network_utils"] = {
  find_hub_ip = function(driver) return "192.168.1.50" end,
  get_subnet_prefix = function(ip) return "192.168.1" end,
  scan_for_grills = function(driver, subnet, start_ip, end_ip, callback)
    -- Simulate finding a grill
    callback({
      ip = "192.168.1.100",
      device_network_id = "pitboss-192-168-1-100",
      name = "Pit Boss Grill",
      model = "Test Model"
    })
    return true
  end,
  test_grill_at_ip = function(ip, device_id)
    if ip == "192.168.1.100" then
      return {
        ip = ip,
        device_network_id = "pitboss-" .. ip:gsub("%.", "-"),
        name = "Pit Boss Grill",
        model = "Test Model"
      }
    end
    return nil
  end
}

local discovery = require("discovery")

-- Mock driver
local mock_driver = {
  environment_info = {
    hub_ipv4 = "192.168.1.50"
  },
  try_create_device = function(device_info)
    return {
      id = "test-device-id",
      device_network_id = device_info.device_network_id
    }
  end
}

-- Test 1: Discovery handler function exists and is callable
assert(type(discovery) == "function", "discovery should be a function")

-- Test 2: Discovery handler can be called with proper parameters
local should_continue = function() return true end
local opts = {}

-- This should not error - the discovery handler should handle the call gracefully
local success, err = pcall(discovery, mock_driver, opts, should_continue)
if not success then
  error("Discovery handler failed: " .. tostring(err))
end

-- Test 3: Discovery handler with nil parameters (should handle gracefully)
local success2, err2 = pcall(discovery, mock_driver, nil, should_continue)
if not success2 then
  error("Discovery handler with nil opts failed: " .. tostring(err2))
end

-- Test 4: Discovery handler with different should_continue function
local should_continue_false = function() return false end
local success3, err3 = pcall(discovery, mock_driver, opts, should_continue_false)
if not success3 then
  error("Discovery handler with false should_continue failed: " .. tostring(err3))
end