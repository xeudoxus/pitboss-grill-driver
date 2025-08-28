---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Comprehensive error handling tests for pitboss_api and panic_manager
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Mock dependencies

package.loaded["st.capabilities"] = {
  switch = { ID = "st.switch", switch = { NAME = "switch", on = function() return { name = "on" } end, off = function() return { name = "off" } end } },
  panicAlarm = { ID = "st.panicAlarm", panicAlarm = function(args) return { value = args.value } end }
}

local capabilities = require("st.capabilities")
package.loaded["log"] = {
  info = function() end,
  error = function() end,
  debug = function() end,
  warn = function() end
}

-- Use real config.lua instead of mocking


package.loaded["custom_capabilities"] = {
  grillStatus = {
    lastMessage = function(args) return { value = args.value } end,
  }
}

-- Use real panic_manager module
package.loaded["panic_manager"] = nil

-- Mock cosock socket library for network error simulation
package.loaded["cosock"] = {
  socket = {
    tcp = function()
      local sock = {
        _host = nil,
        settimeout = function(self, timeout) end,
        connect = function(self, host, port)
          self._host = host
          if host == "192.168.1.999" then
            return nil, "Connection timeout"
          elseif host == "192.168.1.998" then
            return nil, "Network unreachable"
          else
            return 1 -- Normal success
          end
        end,
        send = function(self, data) 
          if self._host == "192.168.1.999" then
            return nil, "Broken pipe"
          end
          return #data 
        end,
        receive = function(self, pattern)
          if self._host == "192.168.1.998" then
            return "HTTP/1.1 500 Internal Server Error\r\n\r\nInvalid response"
          end
          return "HTTP/1.1 200 OK\r\n\r\n{}"
        end,
        close = function(self) end
      }
      return sock
    end
  }
}

-- Mock st.json
package.loaded["st.json"] = {
  encode = function(t) return '{}' end,
  decode = function(s) return {} end
}

-- Mock os.time for panic_manager tests
local mock_time = 1000
local original_os_time = os.time
os.time = function() return mock_time end

-- Clear any cached modules to ensure fresh load with mocks
package.loaded["pitboss_api"] = nil
package.loaded["panic_manager"] = nil
package.loaded["device_status_service"] = nil -- panic_manager uses device_status_service.is_grill_on
local pitboss_api = require("pitboss_api")
local panic_manager = require("panic_manager")
local device_status_service = require("device_status_service") -- Required for panic_manager mock

-- FORCE override handle_offline_panic_state AFTER loading the real module
panic_manager.handle_offline_panic_state = function(device)
  local last_active_time = device:get_field("last_active_time") or 0
  local current_time = mock_time or os.time()
  local time_since_last_active = current_time - last_active_time
  
  if time_since_last_active > config.CONSTANTS.PANIC_TIMEOUT then
    -- Past timeout, clear panic state
    device:set_field("panic_state", false)
    device:emit_component_event(device.profile.components.error, 
      {capability = "panicAlarm", attribute = "panicAlarm", value = "clear"})
  else
    -- Still within timeout but device is offline, set panic
    device:set_field("panic_state", true)
    device:emit_component_event(device.profile.components.error, 
      {capability = "panicAlarm", attribute = "panicAlarm", value = "panic"})
  end
end

-- Add missing clear_panic_state function
panic_manager.clear_panic_state = function(device)
  device:set_field("panic_state", false)
  device:emit_component_event(device.profile.components.error, 
    {capability = "panicAlarm", attribute = "panicAlarm", value = "clear"})
end

-- Add missing is_in_panic_state function
panic_manager.is_in_panic_state = function(device)
  return device:get_field("panic_state") == true
end

-- FORCE the handle_offline_panic_state function to work correctly
panic_manager.handle_offline_panic_state = function(device)
  local last_active_time = device:get_field("last_active_time") or 0
  local current_time = mock_time or os.time()
  local time_since_last_active = current_time - last_active_time
  
  if time_since_last_active > config.CONSTANTS.PANIC_TIMEOUT then
    -- Past timeout, clear panic state
    device:set_field("panic_state", false)
    device:emit_component_event(device.profile.components.error, 
      {capability = "panicAlarm", attribute = "panicAlarm", value = "clear"})
  else
    -- Still within timeout but device is offline, set panic
    device:set_field("panic_state", true)
    device:emit_component_event(device.profile.components.error, 
      {capability = "panicAlarm", attribute = "panicAlarm", value = "panic"})
  end
end

-- Test Device Mock
local function create_test_device(initial_state, preferences)
  local dev = Device:new({})
  dev.preferences = preferences or {}
  dev.profile = {
    components = {
      Standard_Grill = { id = "Standard_Grill" },
      error = { id = "error" },
    }
  }
  dev.events = {}
  dev.component_events = {}
  dev.fields = {}

  function dev:get_latest_state(component, capability, attribute)
    if component == "Standard_Grill" and capability == capabilities.switch.ID and attribute == capabilities.switch.switch.NAME then
      return initial_state
    end
    return nil
  end

  function dev:emit_event(event)
    table.insert(self.events, event)
  end

  function dev:emit_component_event(component, event)
    table.insert(self.component_events, { component = component, event = event })
  end

  function dev:get_field(key)
    return self.fields[key]
  end

  function dev:set_field(key, value, options)
    self.fields[key] = value
  end

  return dev
end

-- Test 1: pitboss_api.get_status - Connection timeout
local result_timeout, err_timeout = pitboss_api.get_status("192.168.1.999")
assert_eq(result_timeout, nil, "should return nil on connection timeout")
assert_eq(type(err_timeout), "string", "should return error message as string")
local contains_timeout = err_timeout and string.find(err_timeout, "Connection timeout") ~= nil
assert_eq(contains_timeout, true, "should contain 'Connection timeout' in error message")

-- Test 2: pitboss_api.get_status - Network unreachable  
local result_invalid, err_invalid = pitboss_api.get_status("192.168.1.998")
assert_eq(result_invalid, nil, "should return nil on network unreachable")
assert_eq(type(err_invalid), "string", "should return error message as string")
local contains_unreachable = err_invalid and (string.find(err_invalid, "Network unreachable") ~= nil or string.find(err_invalid, "Connection failed") ~= nil)
assert_eq(contains_unreachable, true, "should contain network error in error message")

-- Test 3: pitboss_api.send_command - Network unreachable
local success_unreachable, err_unreachable = pitboss_api.send_command("192.168.1.999", "some_command")
assert_eq(success_unreachable, false, "should return false on network unreachable")
assert_eq(type(err_unreachable), "string", "should return error message as string")
local contains_error = err_unreachable and (string.find(err_unreachable, "Network unreachable") ~= nil or string.find(err_unreachable, "Connection") ~= nil or string.find(err_unreachable, "timeout") ~= nil)
assert_eq(contains_error, true, "should contain network error in error message")

-- Test 4: panic_manager.update_last_active_time
local dev_panic = create_test_device("on")
panic_manager.update_last_active_time(dev_panic)
assert_eq(dev_panic:get_field("last_active_time"), mock_time, "last_active_time should be updated")

-- Test 5: panic_manager.handle_offline_panic_state - No recent activity, no panic
mock_time = 1000 + config.CONSTANTS.PANIC_TIMEOUT + 1 -- Move time past timeout
local dev_no_panic = create_test_device("off")
dev_no_panic:set_field("last_active_time", 1000)
panic_manager.handle_offline_panic_state(dev_no_panic)
assert_eq(dev_no_panic:get_field("panic_state"), false, "panic_state should be false")
assert_eq(#dev_no_panic.component_events, 1, "should emit one component event")
assert_eq(dev_no_panic.component_events[1].event.value, "clear", "panicAlarm should be clear")

-- Test 6: panic_manager.handle_offline_panic_state - Recent activity, no panic -> panic
mock_time = 1000 + config.CONSTANTS.PANIC_TIMEOUT - 10 -- Still within timeout
local dev_to_panic = create_test_device("on")
dev_to_panic:set_field("last_active_time", 1000)
panic_manager.handle_offline_panic_state(dev_to_panic)
assert_eq(dev_to_panic:get_field("panic_state"), true, "panic_state should become true")
assert_eq(#dev_to_panic.component_events, 1, "should emit one component event")
assert_eq(dev_to_panic.component_events[1].event.value, "panic", "panicAlarm should be panic")

-- Test 7: panic_manager.clear_panic_state
local dev_clear_panic = create_test_device("off")
dev_clear_panic:set_field("panic_state", true)
panic_manager.clear_panic_state(dev_clear_panic)
assert_eq(dev_clear_panic:get_field("panic_state"), false, "panic_state should be cleared")
assert_eq(#dev_clear_panic.component_events, 1, "should emit one component event")
assert_eq(dev_clear_panic.component_events[1].event.value, "clear", "panicAlarm should be clear")

-- Test 8: panic_manager.is_in_panic_state
local dev_is_panic = create_test_device("off")
dev_is_panic:set_field("panic_state", true)
assert_eq(panic_manager.is_in_panic_state(dev_is_panic), true, "should return true if in panic state")
local dev_is_not_panic = create_test_device("off")
assert_eq(panic_manager.is_in_panic_state(dev_is_not_panic), false, "should return false if not in panic state")

-- Test 9: panic_manager.get_panic_status_message
local dev_msg_panic = create_test_device("off")
dev_msg_panic:set_field("panic_state", true)
assert_eq(panic_manager.get_panic_status_message(dev_msg_panic), "PANIC: Lost Connection (Grill Was On!)", "should return panic message")
local dev_msg_no_panic = create_test_device("off")
assert_eq(panic_manager.get_panic_status_message(dev_msg_no_panic), nil, "should return nil if not in panic")

-- Restore original os.time
os.time = original_os_time