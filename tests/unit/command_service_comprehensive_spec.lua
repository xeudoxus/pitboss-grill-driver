-- Comprehensive command_service tests with all grill states
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

local helpers = require("tests.test_helpers")
local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Use shared helpers to install network recorder and device_status stub
local recorder = helpers.setup_network_recorder()

helpers.setup_device_status_stub()
-- Install a status message recorder so tests can assert status-setting behavior
local status_recorder = helpers.install_status_message_recorder()

-- Minimal custom_capabilities used in this spec
package.loaded["custom_capabilities"] = package.loaded["custom_capabilities"] or {
  grillTemp = { targetTemp = function(args) return {value = args.value, unit = args.unit} end },
  lightControl = { lightState = function(args) return {value = args.value} end },
  primeControl = { primeState = function(args) return {value = args.value} end }
}

-- Clear any cached command_service to ensure fresh load with mocks
package.loaded["command_service"] = nil
local command_service = require("command_service")

-- Helper function to create test device
local function create_test_device(state, unit)
  local dev = Device:new({})
  dev.preferences = {enableVirtualGrillMain = false, enableVirtualGrillLight = false, enableVirtualGrillPrime = false}
  dev.profile = {components = {Standard_Grill = "grill_component"}}
  
  function dev:get_latest_state() return state end
  function dev:get_field(key) 
    if key == "unit" then return unit or "F" end
    return nil
  end
  function dev:emit_event(event) 
    self.last_event = event
  end
  function dev:emit_component_event(component, event) 
    self.last_component_event = {component = component, event = event}
  end
  
  return dev
end

-- Test 1: Power Commands - Grill OFF to ON
recorder.clear_sent()
network_should_fail = false
grill_state = "off"
local dev = create_test_device("off", "F")

local success = command_service.send_power_command(dev, {}, "on")
assert_eq(success, false, "power on command should fail")
assert_eq(#recorder.sent, 0, "command should not be sent")

-- Test 2: Power Commands - Grill ON to OFF
recorder.clear_sent()
grill_state = "on"
dev = create_test_device("on", "F")

success = command_service.send_power_command(dev, {}, "off")
assert_eq(success, true, "power off command should succeed")
assert_eq(#recorder.sent, 1, "should send one command")
assert_eq(recorder.sent[1].cmd, "set_power", "should send power command")
assert_eq(recorder.sent[1].arg, "off", "should send 'off' argument")

-- Test 3: Temperature Command - Grill ON (Success)
recorder.clear_sent()
grill_state = "on"
dev = create_test_device("on", "F")

success = command_service.send_temperature_command(dev, {}, 225)
assert_eq(success, true, "temperature command should succeed when grill is on")
assert_eq(#recorder.sent, 1, "should send one command")
assert_eq(recorder.sent[1].cmd, "set_temperature", "should send temperature command")

-- Test 4: Temperature Command - Grill OFF (Failure)
recorder.clear_sent()
grill_state = "off"
dev = create_test_device("off", "F")

success = command_service.send_temperature_command(dev, {}, 225)
assert_eq(success, false, "temperature command should fail when grill is off")
assert_eq(#recorder.sent, 0, "should not send command when grill is off")
-- Check the recorded status messages
assert_eq(#status_recorder.messages >= 1, true, "should have recorded at least one status message")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Set temp failed (Grill Off)", "should set appropriate error message")

-- Test 5: Invalid Temperature Range (Failure)
recorder.clear_sent()
grill_state = "on"
dev = create_test_device("on", "F")

success = command_service.send_temperature_command(dev, {}, 50) -- Too low (Celsius equivalent)
assert_eq(success, false, "should reject temperature below minimum")
assert_eq(#recorder.sent, 0, "should not send command for invalid temperature")

success = command_service.send_temperature_command(dev, {}, 600) -- Too high
assert_eq(success, false, "should reject temperature above maximum")

-- Test 6: Light Control - Grill ON (Success)
recorder.clear_sent()
grill_state = "on"
dev = create_test_device("on", "F")

success = command_service.send_light_command(dev, {}, "ON")
assert_eq(success, true, "light command should succeed when grill is on")
assert_eq(#recorder.sent, 1, "should send one command")
assert_eq(recorder.sent[1].cmd, "set_light", "should send light command")
assert_eq(recorder.sent[1].arg, "on", "should convert ON to lowercase")

-- Test 7: Light Control - Grill OFF (Failure)
recorder.clear_sent()
grill_state = "off"
dev = create_test_device("off", "F")

success = command_service.send_light_command(dev, {}, "ON")
assert_eq(success, false, "light command should fail when grill is off")
assert_eq(#recorder.sent, 0, "should not send command when grill is off")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Light control failed (Grill Off)", "should set appropriate error message")

-- Test 8: Prime Control - Grill ON (Success)
recorder.clear_sent()
grill_state = "on"
dev = create_test_device("on", "F")

success = command_service.send_prime_command(dev, {}, "ON")
assert_eq(success, true, "prime command should succeed when grill is on")
assert_eq(#recorder.sent, 1, "should send one command")
assert_eq(recorder.sent[1].cmd, "set_prime", "should send prime command")
assert_eq(recorder.sent[1].arg, "on", "should convert ON to lowercase")

-- Test 9: Prime Control - Grill OFF (Failure)
recorder.clear_sent()
grill_state = "off"
dev = create_test_device("off", "F")

success = command_service.send_prime_command(dev, {}, "ON")
assert_eq(success, false, "prime command should fail when grill is off")
assert_eq(#recorder.sent, 0, "should not send command when grill is off")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Prime failed (Grill Off)", "should set appropriate error message")

-- Test 10: Network Failure Handling
recorder.clear_sent()
network_should_fail = true
grill_state = "on"
dev = create_test_device("on", "F")

success = command_service.send_power_command(dev, {}, "off")
assert_eq(success, false, "should handle network failure")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Failed to change power state", "should set network error message")

success = command_service.send_temperature_command(dev, {}, 225)
assert_eq(success, false, "should handle network failure for temperature")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Failed to set temp", "should set network error message")

success = command_service.send_light_command(dev, {}, "ON")
assert_eq(success, false, "should handle network failure for light")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Failed to control light", "should set network error message")

-- Test 11: Temperature Unit Conversion
recorder.clear_sent()
network_should_fail = false
grill_state = "on"
dev = create_test_device("on", "C") -- Celsius device

success = command_service.send_temperature_command(dev, {}, 107) -- 107°C
assert_eq(success, true, "should handle Celsius temperature")
assert_eq(#recorder.sent, 1, "should send command")

-- Test 12: Invalid IP Address Handling
local network_utils = require("network_utils")
local valid, msg = network_utils.validate_ip_address("999.999.999.999")
assert_eq(valid, false, "should reject invalid IP address")
assert_eq(type(msg), "string", "should return error message")

valid, msg = network_utils.validate_ip_address("192.168.1.100")
assert_eq(valid, true, "should accept valid IP address")