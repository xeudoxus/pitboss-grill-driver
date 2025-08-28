---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

local helpers = require("tests.test_helpers")
local recorder = helpers.setup_network_recorder()
helpers.setup_device_status_stub()
local status_recorder = helpers.install_status_message_recorder()

-- Load st.capabilities mock first, then clear and reload custom_capabilities
package.loaded["st.capabilities"] = require("tests.mocks.st.capabilities")
package.loaded["custom_capabilities"] = nil
package.loaded["custom_capabilities"] = require("custom_capabilities")

package.loaded["command_service"] = nil
local command_service = require("command_service")

recorder.clear_sent()
local dev_off = Device:new({})
function dev_off:get_latest_state() return "off" end

local ok_off = command_service.send_light_command(dev_off, {}, "ON")
assert_eq(ok_off, false, "light command should fail when grill is off")
assert_eq(#recorder.sent, 0, "no network command should be sent when grill is off")

recorder.clear_sent()
local dev_on = Device:new({})
function dev_on:get_latest_state() return "on" end
dev_on.preferences = {}

local ok_on = command_service.send_light_command(dev_on, {}, "ON")
assert_eq(ok_on, true, "light command should succeed when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent when grill is on")
assert_eq(recorder.sent[1].cmd, "set_light", "command should be 'set_light'")
assert_eq(recorder.sent[1].arg, "on", "argument should be 'on'")

recorder.clear_sent()
local ok_off_cmd = command_service.send_light_command(dev_on, {}, "OFF")
assert_eq(ok_off_cmd, true, "light OFF command should succeed when grill is on")
assert_eq(#recorder.sent, 1, "network command should be sent for OFF")
assert_eq(recorder.sent[1].arg, "off", "argument should be 'off'")
