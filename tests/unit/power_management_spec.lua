---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Tests for command_service.send_power_command
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

local helpers = require("tests.test_helpers")
helpers.setup_device_status_stub()
local status_recorder = helpers.install_status_message_recorder()

-- Mock dependencies
-- Mock dependencies
local pitboss_api_set_power_calls = {}
package.loaded["pitboss_api"] = {
  set_power = function(ip, state)
    table.insert(pitboss_api_set_power_calls, { ip = ip, state = state })
    return true, nil
  end,
}

package.loaded["network_utils"] = {
  send_command = function(device, cmd, arg, driver)
    if cmd == "set_power" then
      local ip = device.preferences.ipAddress or device:get_field("ip_address")
      if ip then
        return package.loaded["pitboss_api"].set_power(ip, arg)
      else
        return false -- No IP address available
      end
    end
    return true
  end
}

package.loaded["st.capabilities"] = {
  switch = { 
    ID = "st.switch",
    switch = { 
      NAME = "switch", 
      on = function() return { name = "switch", value = "on" } end,
      off = function() return { name = "switch", value = "off" } end
    }
  }
}

-- Use real device_status_service for core behavior
package.loaded["device_status_service"] = nil

-- Clear any cached command_service to ensure fresh load with mocks
package.loaded["command_service"] = nil
local command_service = require("command_service")

-- If the real device_status_service is loaded by command_service, wire its set_status_message
-- to the test recorder so tests can assert on status messages while still using the real core module.
if package.loaded["device_status_service"] and status_recorder then
  package.loaded["device_status_service"].set_status_message = function(device, message)
    table.insert(status_recorder.messages, { device = device, message = message })
    if device then device.last_status_message = message end
  end
end

-- Test 1: send_power_command - Power ON
pitboss_api_set_power_calls = {}
local dev_on = Device:new({})
function dev_on:get_latest_state() return "off" end -- Grill is initially off
function dev_on:emit_event(event) end
function dev_on:emit_component_event(component, event) end
dev_on.preferences = { ipAddress = "192.168.1.100" }
dev_on.profile = { components = { [config.COMPONENTS.GRILL] = "Standard_Grill" } }

local mock_driver = {}
local success_on = command_service.send_power_command(dev_on, mock_driver, "on")
assert_eq(success_on, false, "should fail to send power ON command")
assert_eq(#pitboss_api_set_power_calls, 0, "should not call pitboss_api.set_power")

-- Test 2: send_power_command - Power OFF
pitboss_api_set_power_calls = {}
local dev_off = Device:new({})
function dev_off:get_latest_state() return "on" end -- Grill is initially on
function dev_off:emit_event(event) end
dev_off.preferences = { ipAddress = "192.168.1.100" }

local success_off = command_service.send_power_command(dev_off, mock_driver, "off")
assert_eq(success_off, true, "should successfully send power OFF command")
assert_eq(#pitboss_api_set_power_calls, 1, "should call pitboss_api.set_power once")
assert_eq(pitboss_api_set_power_calls[1].ip, "192.168.1.100", "should use correct IP")
assert_eq(pitboss_api_set_power_calls[1].state, "off", "should send 'off' for OFF state")

-- Test 3: send_power_command - pitboss_api.set_power fails
pitboss_api_set_power_calls = {}
package.loaded["pitboss_api"].set_power = function(ip, state) return false, "API Error" end
local dev_fail = Device:new({})
function dev_fail:get_latest_state() return "off" end
function dev_fail:emit_event(event)
  table.insert(status_recorder.messages, { device = self, message = event.value })
  self.last_status_message = event.value
end
dev_fail.preferences = { ipAddress = "192.168.1.100" }

local success_fail = command_service.send_power_command(dev_fail, mock_driver, "on")
assert_eq(success_fail, false, "should return false if pitboss_api.set_power fails")
assert_eq(#status_recorder.messages >= 1, true, "should have recorded at least one status message")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Grill Power On failed (Grill Off)", "should set appropriate error message")

-- Test 4: send_power_command - No IP address
pitboss_api_set_power_calls = {}
local dev_no_ip = Device:new({})
function dev_no_ip:get_latest_state() return "off" end
function dev_no_ip:emit_event(event)
  table.insert(status_recorder.messages, { device = self, message = event.value })
  self.last_status_message = event.value
end
dev_no_ip.preferences = { } -- No IP address

local success_no_ip = command_service.send_power_command(dev_no_ip, mock_driver, "on")
assert_eq(success_no_ip, false, "should return false if no IP address is available")
assert_eq(status_recorder.messages[#status_recorder.messages].message, "Grill Power On failed (Grill Off)", "should set appropriate error message")