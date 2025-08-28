---@diagnostic disable: need-check-nil, undefined-field, duplicate-set-field

-- Comprehensive panic_manager tests
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Mock dependencies
package.loaded["st.capabilities"] = {
  switch = { ID = "st.switch", switch = { NAME = "switch", on = function() return { name = "on" } end, off = function() return { name = "off" } end } },
  panicAlarm = { ID = "st.panicAlarm", panicAlarm = function(args) return { value = args.value } end },
}

package.loaded["log"] = {
  info = function() end,
  error = function() end,
  debug = function() end,
  warn = function() end
}

-- Use real config.lua instead of mocking

package.loaded["custom_capabilities"] = {} -- Not directly used by panic_manager, but might be by its dependencies

local helpers = require("tests.test_helpers")
helpers.setup_device_status_stub()
-- Override is_grill_on behavior used by panic_manager tests
package.loaded["device_status_service"].is_grill_on = function(device, status)
  if status then
    return status.motor_state or status.hot_state or status.module_on
  else
    return device:get_latest_state("Standard_Grill", package.loaded["st.capabilities"].switch.ID, package.loaded["st.capabilities"].switch.switch.NAME) == "on"
  end
end

-- Mock os.time for time-based logic
local mock_time = 1000
local original_os_time = os.time
os.time = function() return mock_time end

-- Clear any cached panic_manager to ensure fresh load with mocks
package.loaded["panic_manager"] = nil
local panic_manager = require("panic_manager")

-- Test Device Mock
local function create_test_device(initial_state, preferences)
  local dev = Device:new({})
  dev.preferences = preferences or {}
  dev.profile = {
    components = {
      Standard_Grill = { id = "Standard_Grill" },
      [config.COMPONENTS.ERROR] = { id = config.COMPONENTS.ERROR },
    }
  }
  dev.events = {}
  dev.component_events = {}
  dev.fields = {}

  function dev:get_latest_state(component, capability, attribute)
    if component == "Standard_Grill" and capability == package.loaded["st.capabilities"].switch.ID and attribute == package.loaded["st.capabilities"].switch.switch.NAME then
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

-- Test 1: update_last_active_time
local dev_active = create_test_device("on")
panic_manager.update_last_active_time(dev_active)
assert_eq(dev_active:get_field("last_active_time"), mock_time, "last_active_time should be updated")

-- Test 2: update_last_active_time_if_on
local dev_if_on = create_test_device("on")
panic_manager.update_last_active_time_if_on(dev_if_on, { motor_state = true, hot_state = false, module_on = false })
assert_eq(dev_if_on:get_field("last_active_time"), mock_time, "last_active_time should be updated if grill is on")

local dev_if_off = create_test_device("off")
dev_if_off:set_field("last_active_time", 500) -- Set a previous time
panic_manager.update_last_active_time_if_on(dev_if_off, { motor_state = false, hot_state = false, module_on = false }) -- Corrected call
assert_eq(dev_if_off:get_field("last_active_time"), 500, "last_active_time should not be updated if grill is off")

-- Test 3: handle_offline_panic_state - No recent activity, no panic
mock_time = 1000 + config.CONSTANTS.PANIC_TIMEOUT + 1 -- Move time past timeout
local dev_no_panic = create_test_device("off")
dev_no_panic:set_field("last_active_time", 1000)
panic_manager.handle_offline_panic_state(dev_no_panic)
-- If device was never in panic state, panic_state field remains nil (which is falsy)
local panic_state = dev_no_panic:get_field("panic_state")
assert_eq(panic_state == nil or panic_state == false, true, "panic_state should be nil or false")
assert_eq(#dev_no_panic.component_events, 1, "should emit one component event")
assert_eq(dev_no_panic.component_events[1].event.value, "clear", "panicAlarm should be clear")

-- Test 4: handle_offline_panic_state - Recent activity, no panic -> panic
mock_time = 1000 + config.CONSTANTS.PANIC_TIMEOUT - 10 -- Still within timeout
local dev_to_panic = create_test_device("on")
dev_to_panic:set_field("last_active_time", 1000)
panic_manager.handle_offline_panic_state(dev_to_panic)
assert_eq(dev_to_panic:get_field("panic_state"), true, "panic_state should become true")
assert_eq(#dev_to_panic.component_events, 1, "should emit one component event")
assert_eq(dev_to_panic.component_events[1].event.value, "panic", "panicAlarm should be panic")

-- Test 5: handle_offline_panic_state - Recent activity, already in panic -> maintain panic
mock_time = 1000 + config.CONSTANTS.PANIC_TIMEOUT - 5 -- Still within timeout
local dev_maintain_panic = create_test_device("on")
dev_maintain_panic:set_field("last_active_time", 1000)
dev_maintain_panic:set_field("panic_state", true)
panic_manager.handle_offline_panic_state(dev_maintain_panic)
assert_eq(dev_maintain_panic:get_field("panic_state"), true, "panic_state should remain true")
assert_eq(#dev_maintain_panic.component_events, 1, "should emit one component event")
assert_eq(dev_maintain_panic.component_events[1].event.value, "panic", "panicAlarm should be panic")

-- Test 6: handle_offline_panic_state - Not recently active, already in panic -> clear panic
mock_time = 1000 + config.CONSTANTS.PANIC_TIMEOUT + 10 -- Move time past timeout
local dev_clear_panic_offline = create_test_device("off")
dev_clear_panic_offline:set_field("last_active_time", 1000)
dev_clear_panic_offline:set_field("panic_state", true)
panic_manager.handle_offline_panic_state(dev_clear_panic_offline)
assert_eq(dev_clear_panic_offline:get_field("panic_state"), false, "panic_state should be cleared")
assert_eq(#dev_clear_panic_offline.component_events, 1, "should emit one component event")
assert_eq(dev_clear_panic_offline.component_events[1].event.value, "clear", "panicAlarm should be clear")

-- Test 7: clear_panic_on_reconnect
local dev_reconnect_panic = create_test_device("on")
dev_reconnect_panic:set_field("panic_state", true)
panic_manager.clear_panic_on_reconnect(dev_reconnect_panic, true)
assert_eq(dev_reconnect_panic:get_field("panic_state"), false, "panic_state should be cleared on reconnect")

local dev_reconnect_no_panic = create_test_device("on")
dev_reconnect_no_panic:set_field("panic_state", false)
panic_manager.clear_panic_on_reconnect(dev_reconnect_no_panic, true)
assert_eq(dev_reconnect_no_panic:get_field("panic_state"), false, "panic_state should remain false on reconnect")

local dev_reconnect_not_offline = create_test_device("on")
dev_reconnect_not_offline:set_field("panic_state", true)
panic_manager.clear_panic_on_reconnect(dev_reconnect_not_offline, false)
assert_eq(dev_reconnect_not_offline:get_field("panic_state"), true, "panic_state should not be cleared if not offline")

-- Test 8: clear_panic_state
local dev_clear_state = create_test_device("off")
dev_clear_state:set_field("panic_state", true)
panic_manager.clear_panic_state(dev_clear_state)
assert_eq(dev_clear_state:get_field("panic_state"), false, "panic_state should be cleared")
assert_eq(#dev_clear_state.component_events, 1, "should emit one component event")
assert_eq(dev_clear_state.component_events[1].event.value, "clear", "panicAlarm should be clear")

-- Test 9: is_in_panic_state
local dev_is_panic = create_test_device("off")
dev_is_panic:set_field("panic_state", true)
assert_eq(panic_manager.is_in_panic_state(dev_is_panic), true, "should return true if in panic state")
local dev_is_not_panic = create_test_device("off")
assert_eq(panic_manager.is_in_panic_state(dev_is_not_panic), false, "should return false if not in panic state")

-- Test 10: get_panic_status_message
local dev_msg_panic = create_test_device("off")
dev_msg_panic:set_field("panic_state", true)
assert_eq(panic_manager.get_panic_status_message(dev_msg_panic), "PANIC: Lost Connection (Grill Was On!)", "should return panic message")
local dev_msg_no_panic = create_test_device("off")
assert_eq(panic_manager.get_panic_status_message(dev_msg_no_panic), nil, "should return nil if not in panic")

-- Test 11: cleanup_panic_resources
local dev_cleanup = create_test_device("off")
dev_cleanup:set_field("panic_state", true)
dev_cleanup:set_field("last_active_time", 12345)
panic_manager.cleanup_panic_resources(dev_cleanup)
assert_eq(dev_cleanup:get_field("panic_state"), nil, "panic_state should be nil after cleanup")
assert_eq(dev_cleanup:get_field("last_active_time"), nil, "last_active_time should be nil after cleanup")

-- Restore original os.time
os.time = original_os_time