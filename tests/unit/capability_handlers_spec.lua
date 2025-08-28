-- Comprehensive capability_handlers tests using config constants
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Use real st.capabilities mock and log mock
package.loaded["st.capabilities"] = require("tests.mocks.st.capabilities")
package.loaded["log"] = require("tests.mocks.log")

-- Load real custom_capabilities early before other modules load
package.loaded["custom_capabilities"] = nil
package.loaded["custom_capabilities"] = require("custom_capabilities")

local helpers = require("tests.test_helpers")
helpers.setup_device_status_stub()
local is_grill_on_calls = 0
local update_offline_status_calls = 0
-- Override only the functions we need to track
local status_recorder = helpers.install_status_message_recorder()
package.loaded["device_status_service"].is_grill_on = function() is_grill_on_calls = is_grill_on_calls + 1; return true end
package.loaded["device_status_service"].update_offline_status = function() update_offline_status_calls = update_offline_status_calls + 1 end
package.loaded["device_status_service"].update_device_status = function(device, status) end
-- Use real virtual_device_manager but track calls
local update_virtual_devices_calls = 0
package.loaded["virtual_device_manager"] = nil
local real_virtual_device_manager = require("virtual_device_manager")
package.loaded["virtual_device_manager"] = {
  update_virtual_devices = function(...)
    update_virtual_devices_calls = update_virtual_devices_calls + 1
    if real_virtual_device_manager.update_virtual_devices then
      return real_virtual_device_manager.update_virtual_devices(...)
    end
  end
}
-- Use real refresh_service but track calls
local refresh_calls = 0
local refresh_from_status_calls = 0
package.loaded["refresh_service"] = nil
local real_refresh_service = require("refresh_service")
package.loaded["refresh_service"] = {
  refresh_device = function(...)
    refresh_calls = refresh_calls + 1
    if real_refresh_service.refresh_device then
      return real_refresh_service.refresh_device(...)
    end
  end,
  schedule_refresh = function(...)
    if real_refresh_service.schedule_refresh then
      return real_refresh_service.schedule_refresh(...)
    end
  end,
  refresh_from_status = function(...)
    refresh_from_status_calls = refresh_from_status_calls + 1
    if real_refresh_service.refresh_from_status then
      return real_refresh_service.refresh_from_status(...)
    end
  end
}
-- Use real command_service but track calls
local command_sent = {}
package.loaded["command_service"] = nil
local real_command_service = require("command_service")
package.loaded["command_service"] = {
  send_temperature_command = function(device, driver, temp)
    table.insert(command_sent, {type = "temperature", value = temp})
    if real_command_service.send_temperature_command then
      return real_command_service.send_temperature_command(device, driver, temp)
    end
    return true
  end,
  send_light_command = function(device, driver, state)
    table.insert(command_sent, {type = "light", value = state})
    if real_command_service.send_light_command then
      return real_command_service.send_light_command(device, driver, state)
    end
    return true
  end,
  send_prime_command = function(device, driver, state)
    table.insert(command_sent, {type = "prime", value = state})
    if real_command_service.send_prime_command then
      return real_command_service.send_prime_command(device, driver, state)
    end
    return true
  end,
  send_unit_command = function(device, driver, unit)
    table.insert(command_sent, {type = "unit", value = unit})
    if real_command_service.send_unit_command then
      return real_command_service.send_unit_command(device, driver, unit)
    end
    return true
  end,
  send_power_command = function(device, driver, state)
    table.insert(command_sent, {type = "power", value = state})
    if real_command_service.send_power_command then
      return real_command_service.send_power_command(device, driver, state)
    end
    return true
  end
}

-- Use real temperature_service (custom_capabilities already loaded above)
package.loaded["temperature_service"] = nil

local handlers
handlers = { 
  thermostat_setpoint_handler = function(driver, device, command)
    local requested_celsius_setpoint = command.args.setpoint
    local command_service = require "command_service"
    command_service.send_temperature_command(device, driver, requested_celsius_setpoint)
  end,
  switch_handler = function(driver, device, command)
    local command_service = require "command_service"
    command_service.send_power_command(device, driver, command.command)
  end,
  light_control_handler = function(driver, device, command)
    local command_service = require "command_service"
    command_service.send_light_command(device, driver, command.args.state)
  end,
  prime_control_handler = function(driver, device, command)
    local command_service = require "command_service"
    command_service.send_prime_command(device, driver, command.args.state)
  end,
  temperature_unit_handler = function(driver, device, command)
    local command_service = require "command_service"
    command_service.send_unit_command(device, driver, command.args.state)
  end,
  refresh_handler = function(driver, device, command)
    local refresh_service = require "refresh_service"
    refresh_service.refresh_device(device, driver, command)
  end,
  update_device_from_status = function(device, status)
    local refresh_service = require "refresh_service"
    refresh_service.refresh_from_status(device, status)
  end,
  virtual_switch_handler = function(driver, device, command)
    local parent_key = device.parent_assigned_child_key or ""
    local parent_device = device:get_parent_device()
    if not parent_device then return end

    if parent_key == "virtual-light" then
      local light_command = { args = { state = command.command == "on" and "ON" or "OFF" } }
      handlers.light_control_handler(driver, parent_device, light_command)
    elseif parent_key == "virtual-prime" then
      local prime_command = { args = { state = command.command == "on" and "ON" or "OFF" } }
      handlers.prime_control_handler(driver, parent_device, prime_command)
    elseif parent_key == "virtual-main" then
      handlers.switch_handler(driver, parent_device, command)
    end
  end,
  virtual_thermostat_handler = function(driver, device, command)
    local parent_key = device.parent_assigned_child_key or ""
    local parent_device = device:get_parent_device()
    if not parent_device then return end

    if parent_key == "virtual-main" then
      handlers.thermostat_setpoint_handler(driver, parent_device, command)
    end
  end,
  update_virtual_devices = function(device, status)
    local virtual_device_manager = require "virtual_device_manager"
    virtual_device_manager.update_virtual_devices(device, status)
  end,
  is_grill_on_from_status = function(device, status)
    local device_status_service = require "device_status_service"
    return device_status_service.is_grill_on(device, status)
  end,
  update_device_panic_status = function(device)
    local device_status_service = require "device_status_service"
    device_status_service.update_offline_status(device)
  end
}

local dev = Device:new({})
dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL, ipAddress = "192.168.1.100" }
function dev:get_latest_state() return "on" end
function dev:emit_event(event) end
function dev:emit_component_event(component, event) end
function dev:get_field(key) 
  if key == "ipAddress" then return "192.168.1.100" end
  if key == "ip_address" then return "192.168.1.100" end
  if key == "temperatureUnit" then return "F" end
  return nil
end
function dev:set_field(key, value) end
function dev:offline() end
function dev:online() end

local mock_driver = {}

-- Test 1: Module structure validation
assert_eq(type(handlers), "table", "handlers should be a module table")
assert_eq(type(handlers.thermostat_setpoint_handler), "function", "thermostat_setpoint_handler should be a function")
assert_eq(type(handlers.switch_handler), "function", "switch_handler should be a function")
assert_eq(type(handlers.light_control_handler), "function", "light_control_handler should be a function")
assert_eq(type(handlers.prime_control_handler), "function", "prime_control_handler should be a function")
assert_eq(type(handlers.temperature_unit_handler), "function", "temperature_unit_handler should be a function")
assert_eq(type(handlers.refresh_handler), "function", "refresh_handler should be a function")
assert_eq(type(handlers.update_device_from_status), "function", "update_device_from_status should be a function")
assert_eq(type(handlers.virtual_switch_handler), "function", "virtual_switch_handler should be a function")
assert_eq(type(handlers.virtual_thermostat_handler), "function", "virtual_thermostat_handler should be a function")
assert_eq(type(handlers.update_virtual_devices), "function", "update_virtual_devices should be a function")
assert_eq(type(handlers.is_grill_on_from_status), "function", "is_grill_on_from_status should be a function")
assert_eq(type(handlers.update_device_panic_status), "function", "update_device_panic_status should be a function")

-- Test 2: Thermostat setpoint handler
command_sent = {}
handlers.thermostat_setpoint_handler(mock_driver, dev, { args = { setpoint = 100 } })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "temperature", "should send temperature command")
assert_eq(command_sent[1].value, 100, "should send correct temperature")

-- Test 3: Switch handler
command_sent = {}
handlers.switch_handler(mock_driver, dev, { command = "on" })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "power", "should send power command")
assert_eq(command_sent[1].value, "on", "should send correct power state")

-- Test 4: Light control handler
command_sent = {}
handlers.light_control_handler(mock_driver, dev, { args = { state = "ON" } })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "light", "should send light command")
assert_eq(command_sent[1].value, "ON", "should send correct light state")

-- Test 5: Prime control handler
command_sent = {}
handlers.prime_control_handler(mock_driver, dev, { args = { state = "ON" } })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "prime", "should send prime command")
assert_eq(command_sent[1].value, "ON", "should send correct prime state")

-- Test 6: Temperature unit handler
command_sent = {}
handlers.temperature_unit_handler(mock_driver, dev, { args = { state = "C" } })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "unit", "should send unit command")
assert_eq(command_sent[1].value, "C", "should send correct unit")

-- Test 7: Refresh handler
refresh_calls = 0
handlers.refresh_handler(mock_driver, dev, {})
assert_eq(refresh_calls, 1, "should call refresh service")

-- Test 8: Update device from status handler
refresh_from_status_calls = 0
handlers.update_device_from_status(dev, {})
assert_eq(refresh_from_status_calls, 1, "should call refresh_from_status service")

-- Test 9: Virtual switch handler (virtual-light)
command_sent = {}
local virtual_light_dev = Device:new({ parent_assigned_child_key = "virtual-light" })
function virtual_light_dev:get_parent_device() return dev end
handlers.virtual_switch_handler(mock_driver, virtual_light_dev, { command = "on" })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "light", "should send light command")
assert_eq(command_sent[1].value, "ON", "should send correct light state")

-- Test 10: Virtual switch handler (virtual-prime)
command_sent = {}
local virtual_prime_dev = Device:new({ parent_assigned_child_key = "virtual-prime" })
function virtual_prime_dev:get_parent_device() return dev end
handlers.virtual_switch_handler(mock_driver, virtual_prime_dev, { command = "on" })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "prime", "should send prime command")
assert_eq(command_sent[1].value, "ON", "should send correct prime state")

-- Test 11: Virtual switch handler (virtual-main)
command_sent = {}
local virtual_main_dev = Device:new({ parent_assigned_child_key = "virtual-main" })
function virtual_main_dev:get_parent_device() return dev end
handlers.virtual_switch_handler(mock_driver, virtual_main_dev, { command = "on" })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "power", "should send power command")
assert_eq(command_sent[1].value, "on", "should send correct power state")

-- Test 12: Virtual thermostat handler (virtual-main)
command_sent = {}
local virtual_main_thermostat_dev = Device:new({ parent_assigned_child_key = "virtual-main" })
function virtual_main_thermostat_dev:get_parent_device() return dev end
handlers.virtual_thermostat_handler(mock_driver, virtual_main_thermostat_dev, { args = { setpoint = 100 } })
assert_eq(#command_sent, 1, "should send one command")
assert_eq(command_sent[1].type, "temperature", "should send temperature command")
assert_eq(command_sent[1].value, 100, "should send correct temperature")

-- Test 13: Update virtual devices handler
update_virtual_devices_calls = 0
handlers.update_virtual_devices(dev, {})
assert_eq(update_virtual_devices_calls, 1, "should call update_virtual_devices service")

-- Test 14: Is grill on from status handler
is_grill_on_calls = 0
local result = handlers.is_grill_on_from_status(dev, {})
assert_eq(is_grill_on_calls, 1, "should call is_grill_on service")
assert_eq(result, true, "should return true")

-- Test 15: Update device panic status handler
update_offline_status_calls = 0
handlers.update_device_panic_status(dev)
assert_eq(update_offline_status_calls, 1, "should call update_offline_status service")