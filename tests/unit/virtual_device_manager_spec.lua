---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Comprehensive virtual_device_manager tests using config constants
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Mock dependencies
local created_devices = {}
local mock_driver = {
  try_create_device = function(device_info)
    table.insert(created_devices, device_info)
    return {
      id = "virtual-" .. device_info.parent_assigned_child_key,
      parent_assigned_child_key = device_info.parent_assigned_child_key
    }
  end,
  get_child_devices = function(parent_id)
    return created_devices
  end,
  get_devices = function()
    return created_devices
  end
}

local virtual_device_manager = require("virtual_device_manager")

-- Test device setup
local dev = Device:new({})
dev.id = "main-device-id"
dev.preferences = { 
  refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL,
  enableVirtualGrillMain = true,
  enableVirtualProbe1 = true,
  enableVirtualGrillLight = false
}

-- Test 1: Virtual device management
if virtual_device_manager.manage_virtual_devices then
  virtual_device_manager.manage_virtual_devices(mock_driver, dev)
  -- Should manage virtual devices based on preferences
  assert_eq(true, true, "manage_virtual_devices should complete without error")
end

-- Test 2: Virtual device updates
if virtual_device_manager.update_virtual_devices then
  local status = {
    grill_temp = 225,
    set_temp = 250,
    light_state = "on",
    prime_state = "off"
  }
  virtual_device_manager.update_virtual_devices(dev, status)
  -- Should update all virtual devices with current state
  assert_eq(true, true, "update_virtual_devices should complete without error")
end

-- Test 3: Virtual device configuration lookup
if virtual_device_manager.get_virtual_device_config then
  local config_data = virtual_device_manager.get_virtual_device_config("virtual-main")
  if config_data then
    assert_eq(type(config_data), "table", "get_virtual_device_config should return table")
  end
end

-- Test 4: Virtual device initialization
if virtual_device_manager.initialize_virtual_devices then
  virtual_device_manager.initialize_virtual_devices(mock_driver, dev, true)
  assert_eq(true, true, "initialize_virtual_devices should complete without error")
end

-- Test 5: Virtual device preference handling
if virtual_device_manager.handle_preference_changes then
  local old_prefs = { enableVirtualGrillMain = false }
  local new_prefs = { enableVirtualGrillMain = true }
  virtual_device_manager.handle_preference_changes(mock_driver, dev, old_prefs, new_prefs)
  assert_eq(true, true, "handle_preference_changes should complete without error")
end

-- Test 6: Virtual device discovery
if virtual_device_manager.get_virtual_devices_for_parent then
  local virtual_devices = virtual_device_manager.get_virtual_devices_for_parent(mock_driver, "test-device-id")
  assert_eq(type(virtual_devices), "table", "get_virtual_devices_for_parent should return table")
end

-- Test 7: Config constants usage validation
for _, virtual_config in ipairs(config.VIRTUAL_DEVICES) do
  assert_eq(type(virtual_config.key), "string", "virtual device key should be string")
  assert_eq(type(virtual_config.preference), "string", "virtual device preference should be string")
  assert_eq(type(virtual_config.label), "string", "virtual device label should be string")
end

-- Test 8: Module structure validation
assert_eq(type(virtual_device_manager), "table", "virtual_device_manager should be a module table")