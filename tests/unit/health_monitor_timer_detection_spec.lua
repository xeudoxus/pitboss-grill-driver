---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Health Monitor Timer Detection Tests
-- Set up package path - prioritize src over mocks for this test
package.path = "src/?.lua;tests/mocks/?.lua;tests/mocks/?/init.lua;" .. package.path

-- Clear any previously loaded health_monitor to ensure we get the real one
package.loaded["health_monitor"] = nil

local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

local function assert_true(condition, msg)
  if not condition then error(msg or "assert_true failed", 2) end
end

local function assert_false(condition, msg)
  if condition then error(msg or "assert_false failed", 2) end
end

-- Mock dependencies
package.loaded["log"] = {
  info = function() end,
  error = function() end,
  debug = function() end,
  warn = function() end
}

package.loaded["st.capabilities"] = {
  switch = {
    ID = "st.switch",
    switch = {
      NAME = "switch"
    }
  }
}

package.loaded["network_utils"] = {
  get_status = function(device, driver)
    return { grillTemp = 225, targetTemp = 250, connected = true }, nil
  end
}

-- Use real panic_manager module
package.loaded["panic_manager"] = nil

-- Use real device_status_service module
package.loaded["device_status_service"] = nil

-- Use real virtual_device_manager module
package.loaded["virtual_device_manager"] = nil

-- Track timer calls
local timer_calls = {}
local mock_device_thread = {
  call_with_delay = function(delay, callback, timer_id)
    table.insert(timer_calls, { delay = delay, timer_id = timer_id })
    return { id = timer_id }
  end
}

-- Create test device
local function create_test_device()
  local dev = Device:new({})
  dev.preferences = { refreshInterval = 30 }
  dev.thread = mock_device_thread
  dev.profile = {
    components = {
      grill = { id = "grill" }
    }
  }
  
  -- Add get_latest_state method needed by health_monitor
  dev.get_latest_state = function(self, component, capability, attribute)
    return "off" -- Default switch state
  end
  
  return dev
end

-- Load health_monitor after mocks are set up
local health_monitor = require("health_monitor")

-- Test 1: ensure_health_timer_active - No existing timer
timer_calls = {}
local device1 = create_test_device()
local driver1 = {}

local timer_started = health_monitor.ensure_health_timer_active(driver1, device1, false)
assert_true(timer_started, "should start new timer when none exists")
assert_eq(#timer_calls, 1, "should schedule one timer")
assert_true(device1:get_field("health_timer_id") ~= nil, "should set timer ID field")
assert_true(device1:get_field("last_health_scheduled") ~= nil, "should set last scheduled field")

-- Test 2: ensure_health_timer_active - Existing active timer
timer_calls = {}
local device2 = create_test_device()
device2:set_field("health_timer_id", "test_timer_123")
device2:set_field("last_health_scheduled", os.time()) -- Current time
local driver2 = {}

local timer_started2 = health_monitor.ensure_health_timer_active(driver2, device2, false)
assert_false(timer_started2, "should not start new timer when active one exists")
assert_eq(#timer_calls, 0, "should not schedule new timer")

-- Test 3: ensure_health_timer_active - Stale timer (>2 hours old)
timer_calls = {}
local device3 = create_test_device()
device3:set_field("health_timer_id", "old_timer_456")
device3:set_field("last_health_scheduled", os.time() - 7300) -- >2 hours ago
local driver3 = {}

local timer_started3 = health_monitor.ensure_health_timer_active(driver3, device3, false)
assert_true(timer_started3, "should start new timer when existing one is stale")
assert_eq(#timer_calls, 1, "should schedule new timer")

-- Test 4: ensure_health_timer_active - Force restart
timer_calls = {}
local device4 = create_test_device()
device4:set_field("health_timer_id", "active_timer_789")
device4:set_field("last_health_scheduled", os.time()) -- Current time
local driver4 = {}

local timer_started4 = health_monitor.ensure_health_timer_active(driver4, device4, true)
assert_true(timer_started4, "should start new timer when force restart is true")
assert_eq(#timer_calls, 1, "should schedule new timer")

-- Test 5: check_and_recover_timer - Missing timer recovery
timer_calls = {}
local device5 = create_test_device()
local driver5 = {}

local timer_restarted = health_monitor.check_and_recover_timer(driver5, device5)
assert_true(timer_restarted, "should restart missing timer")
assert_eq(#timer_calls, 1, "should schedule new timer")

-- Test 6: check_and_recover_timer - Active timer (no recovery needed)
timer_calls = {}
local device6 = create_test_device()
device6:set_field("health_timer_id", "active_timer_999")
device6:set_field("last_health_scheduled", os.time())
local driver6 = {}

local timer_restarted6 = health_monitor.check_and_recover_timer(driver6, device6)
assert_false(timer_restarted6, "should not restart active timer")
assert_eq(#timer_calls, 0, "should not schedule new timer")

-- Test 7: force_restart_timer
timer_calls = {}
local device7 = create_test_device()
device7:set_field("health_timer_id", "timer_to_restart")
device7:set_field("last_health_scheduled", os.time())
local driver7 = {}

health_monitor.force_restart_timer(driver7, device7)
assert_eq(#timer_calls, 1, "should schedule new timer")
assert_true(device7:get_field("health_timer_id") ~= "timer_to_restart", "should update timer ID")

-- Test 8: cleanup_monitoring clears timer tracking
local device8 = create_test_device()
device8:set_field("health_timer_id", "timer_to_cleanup")
device8:set_field("last_health_scheduled", os.time())

health_monitor.cleanup_monitoring(device8)
assert_eq(device8:get_field("health_timer_id"), nil, "should clear timer ID")
assert_eq(device8:get_field("last_health_scheduled"), nil, "should clear last scheduled time")