-- Clean command_service.prime tests using config constants
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Set up mocks before loading test_helpers
package.loaded["st.capabilities"] = require("tests.mocks.st.capabilities")
package.loaded["custom_capabilities"] = nil
package.loaded["custom_capabilities"] = require("custom_capabilities")
package.loaded["st.timer"] = require("tests.mocks.st.timer")

local helpers = require("tests.test_helpers")
local recorder = helpers.setup_network_recorder()
helpers.setup_device_status_stub()
local status_recorder = helpers.install_status_message_recorder()

-- Clear any cached command_service to ensure fresh load with mocks
package.loaded["command_service"] = nil
local command_service = require("command_service")

-- Test 1: Prime command when grill is OFF (expected failure)
recorder.clear_sent()
local dev_off = Device:new({})
function dev_off:get_latest_state() return "off" end

local ok_off = command_service.send_prime_command(dev_off, {}, "ON")
assert_eq(ok_off, false, "prime command should fail when grill is off")
assert_eq(#recorder.sent, 0, "no network command should be sent when grill is off")

-- Test 2: Prime command when grill is ON (expected success)
recorder.clear_sent()
local dev_on = Device:new({})
function dev_on:get_latest_state() return "on" end
function dev_on:set_field(key, value) end -- Mock set_field
function dev_on:get_field(key) return nil end -- Mock get_field
dev_on.preferences = {}
-- Mock device.thread to not execute delayed callbacks immediately
dev_on.thread = {
  call_with_delay = function(delay, callback)
    return { cancel = function() end } -- Return a mock timer that doesn't execute
  end
}

local ok_on = command_service.send_prime_command(dev_on, {}, "ON")
assert_eq(ok_on, true, "prime command should succeed when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent when grill is on")
assert_eq(recorder.sent[1].cmd, "set_prime", "command should be 'set_prime'")
assert_eq(recorder.sent[1].arg, "on", "argument should be 'on'")

-- Test 3: Prime timeout configuration
assert_eq(config.CONSTANTS.PRIME_TIMEOUT, 30, "prime timeout should use config constant")

-- Test 4: Prime OFF command when grill is ON
recorder.clear_sent()
-- Add thread mock to dev_on for OFF command test too
dev_on.thread = {
  call_with_delay = function(delay, callback)
    return { cancel = function() end }
  end
}
local ok_off_cmd = command_service.send_prime_command(dev_on, {}, "OFF")
assert_eq(ok_off_cmd, true, "prime OFF command should succeed when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent for OFF")
assert_eq(recorder.sent[1].arg, "off", "argument should be 'off'")
