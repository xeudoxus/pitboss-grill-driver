---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

-- Device mock setup (single block, DRY)
local dev_off = Device:new({})
dev_off.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }
dev_off.profile = dev_off.profile or { components = {} }
dev_off.profile.components["Standard_Grill"] = { id = "Standard_Grill" }
dev_off._latest_state = "off"
function dev_off:get_latest_state(component, cap_id, attr)
  if component == "Standard_Grill" then return "off" end
  return self._latest_state or "off"
end
dev_off.driver = dev_off.driver or { get_devices = function() return {} end }

local dev_on = Device:new({})
dev_on.id = "main-device-id"
dev_on.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL, enableVirtualGrillMain = true }
dev_on.profile = dev_on.profile or { components = {} }
dev_on.profile.components["Standard_Grill"] = { id = "Standard_Grill" }
dev_on._latest_state = "on"
function dev_on:get_latest_state(component, cap_id, attr)
  if component == "Standard_Grill" then return "on" end
  return self._latest_state or "on"
end
-- Mock get_devices to return a virtual device with matching parent_device_id and parent_assigned_child_key
local virtual_main = {
  parent_device_id = dev_on.id,
  parent_assigned_child_key = "virtual-main",
  emit_event = function(self, evt) end
}
dev_on.driver = {
  get_devices = function() return {virtual_main} end
}

package.loaded["temperature_service"] = nil

local helpers = require("tests.test_helpers")
local recorder = helpers.setup_network_recorder()
helpers.setup_device_status_stub()
local status_recorder = helpers.install_status_message_recorder()
-- Load real custom capabilities from src so command_service can emit capability events
package.loaded["custom_capabilities"] = require("custom_capabilities")
_G.command_service = require("command_service")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Mock network to simulate real network calls
recorder.clear_sent()

-- Use real device_status_service module
package.loaded["device_status_service"] = nil

-- Test 1: Temperature command when grill is OFF (expected failure)
local approved_setpoints = config.get_approved_setpoints(config.CONSTANTS.DEFAULT_UNIT)
local test_temp = approved_setpoints[1]
local ok_off = command_service.send_temperature_command(dev_off, dev_off.driver, test_temp)
assert_eq(ok_off, false, "should reject temperature command when grill is off")
assert_eq(#recorder.sent, 0, "no network command should be sent when grill is off")

recorder.clear_sent()
-- Use an approved Celsius setpoint for the on-device test to align with real temperature_service behavior
local celsius_approved = config.get_approved_setpoints("C")[1]
local ok_on = command_service.send_temperature_command(dev_on, dev_on.driver, celsius_approved)
-- The mocked network will record the outgoing command
assert_eq(ok_on, true, "should accept temperature command when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent when grill is on")

-- Test 2: Temperature snapping behavior (extreme values get snapped to valid range)
recorder.clear_sent()
local temp_range = config.get_temperature_range(config.CONSTANTS.DEFAULT_UNIT)
local extreme_temp = temp_range.max + 100
local ok_extreme = command_service.send_temperature_command(dev_on, dev_on.driver, extreme_temp)
assert_eq(ok_extreme, false, "extreme temperature should be rejected as invalid input")
assert_eq(#recorder.sent, 0, "no network command should be sent for invalid input")

-- Test 3: Verify temperature conversion and snapping
recorder.clear_sent()
local celsius_temp = 100 -- 100°C = 212°F
local ok_celsius = command_service.send_temperature_command(dev_on, dev_on.driver, celsius_temp)
assert_eq(ok_celsius, true, "celsius temperature should be converted and snapped")
assert_eq(#recorder.sent >= 1, true, "network command should be sent after conversion")
-- Optionally check last recorded command type
assert_eq(recorder.sent[#recorder.sent].cmd, "set_temperature", "last network command should be set_temperature")

-- Test 4: Power command tests
recorder.clear_sent()
local power_off_result = command_service.send_power_command(dev_on, dev_on.driver, "off")
assert_eq(power_off_result, true, "power off should succeed when grill is on")
assert_eq(#recorder.sent, 1, "should send power command")
assert_eq(recorder.sent[1].cmd, "set_power", "should send power command")

-- Test 5: Light command when grill is off (should fail)
recorder.clear_sent()
local light_off_result = command_service.send_light_command(dev_off, dev_off.driver, "ON")
assert_eq(light_off_result, false, "should reject light command when grill is off")
assert_eq(#recorder.sent, 0, "no network command should be sent when grill is off")

-- Test 6: Light command when grill is on (should succeed)
recorder.clear_sent()
local light_on_result = command_service.send_light_command(dev_on, dev_on.driver, "ON")
assert_eq(light_on_result, true, "should accept light command when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent when grill is on")
assert_eq(recorder.sent[1].cmd, "set_light", "should send light command")

-- Test 7: Prime command when grill is off (should fail)
recorder.clear_sent()
local prime_off_result = command_service.send_prime_command(dev_off, dev_off.driver, "ON")
assert_eq(prime_off_result, false, "should reject prime command when grill is off")
assert_eq(#recorder.sent, 0, "no network command should be sent when grill is off")

-- Test 8: Prime command when grill is on (should succeed)
recorder.clear_sent()
-- Need to mock the timer for prime auto-off
dev_on.thread = {
  call_with_delay = function(delay, func) 
    return {cancel = function() end}
  end
}
local prime_on_result = command_service.send_prime_command(dev_on, dev_on.driver, "ON")
assert_eq(prime_on_result, true, "should accept prime command when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent when grill is on")
assert_eq(recorder.sent[1].cmd, "set_prime", "should send prime command")

-- Test 9: Unit command when grill is off (should fail)
recorder.clear_sent()
local unit_off_result = command_service.send_unit_command(dev_off, dev_off.driver, "C")
assert_eq(unit_off_result, false, "should reject unit command when grill is off")
assert_eq(#recorder.sent, 0, "no network command should be sent when grill is off")

-- Test 10: Unit command when grill is on (should succeed)
recorder.clear_sent()
local unit_on_result = command_service.send_unit_command(dev_on, dev_on.driver, "C")
assert_eq(unit_on_result, true, "should accept unit command when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent when grill is on")
assert_eq(recorder.sent[1].cmd, "set_unit", "should send unit command")