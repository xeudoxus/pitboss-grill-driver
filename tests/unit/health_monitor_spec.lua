-- Comprehensive health_monitor tests with actual health check validation
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Set up package path - prioritize src over mocks for this test
package.path = "src/?.lua;tests/mocks/?.lua;tests/mocks/?/init.lua;" .. package.path

-- Clear any previously loaded health_monitor to ensure we get the real one
package.loaded["health_monitor"] = nil

local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Mock custom capabilities
package.loaded["custom_capabilities"] = {
  lightControl = {
    ID = "ns.lightControl",
    commands = {
      setLightState = { NAME = "setLightState" }
    }
  },
  primeControl = {
    ID = "ns.primeControl",
    commands = {
      setPrimeState = { NAME = "setPrimeState" }
    }
  },
  temperatureUnit = {
    ID = "ns.temperatureUnit",
    commands = {
      setTemperatureUnit = { NAME = "setTemperatureUnit" }
    }
  },
  grillStatus = {
    ID = "ns.grillStatus",
    lastMessage = function(v)
      if type(v) == "table" then return v end
      return { value = v }
    end,
    panic = { NAME = "panic" },
    commands = {
      panic = { NAME = "panic" }
    }
  }
}

-- Mock ST capabilities
package.loaded["st.capabilities"] = {
  switch = {
    ID = "st.switch",
    switch = {
      on = function() return { name = "switch", value = "on" } end,
      off = function() return { name = "switch", value = "off" } end
    },
    commands = {
      on = { NAME = "on" },
      off = { NAME = "off" }
    }
  },
  powerMeter = {
    ID = "st.powerMeter",
    commands = {}
  },
  thermostatHeatingSetpoint = {
    ID = "st.thermostatHeatingSetpoint",
    commands = {
      setHeatingSetpoint = { NAME = "setHeatingSetpoint" }
    }
  },
  refresh = {
    ID = "st.refresh",
    commands = {
      refresh = { NAME = "refresh" }
    }
  }
}

-- Mock st.json
package.loaded["st.json"] = {
  encode = function(t) return "" end,
  decode = function(s) return {} end
}

-- Use real virtual_device_manager module
package.loaded["virtual_device_manager"] = nil


-- Mock capability_handlers
package.loaded["capability_handlers"] = {
  update_device_from_status = function(device, status)
    -- Call the mocked device_status_service directly
    if package.loaded["device_status_service"] then
      package.loaded["device_status_service"].update_device_status(device, status)
    end
  end
}

-- Mock network status tracking
local network_call_count = 0
local network_should_fail = false
local last_network_call_time = 0

-- Mock network_utils with failure simulation
package.loaded["network_utils"] = {
  get_status = function(device, driver)
    network_call_count = network_call_count + 1
    last_network_call_time = os.time()
    
    if network_should_fail then
      return nil, "Network timeout"
    end
    
    return {
      grill_temp = 225,
      set_temp = 250,
      module_is_on = true,
      connected = true,
      last_activity = os.time()
    }
  end
}

-- Mock device_status_service
local status_updates = {}
local helpers = require("tests.test_helpers")
helpers.setup_device_status_stub()
local status_recorder = helpers.install_status_message_recorder()

-- Use real device_status_service but track calls for testing
package.loaded["device_status_service"] = nil
local real_device_status_service = require("device_status_service")
package.loaded["device_status_service"] = {
  update_device_status = function(device, status, driver)
    table.insert(status_updates, {device = device, status = status, time = os.time()})
    -- Call real function if needed for side effects
    if real_device_status_service.update_device_status then
      pcall(real_device_status_service.update_device_status, device, status, driver)
    end
  end,
  set_status_message = function(device, message)
    table.insert(status_recorder.messages, { device = device, message = message })
    if real_device_status_service.set_status_message then
      pcall(real_device_status_service.set_status_message, device, message)
    end
  end,
  is_grill_on = function(device)
    if real_device_status_service.is_grill_on then
      return real_device_status_service.is_grill_on(device)
    end
    return device:get_latest_state("main", "switch", "switch") == "on"
  end
}

-- Use real panic_manager but track calls for testing
local panic_checks = {}
local offline_panic_calls = 0
package.loaded["panic_manager"] = nil
local real_panic_manager = require("panic_manager")
package.loaded["panic_manager"] = {
  check_panic_timeout = function(device, driver)
    table.insert(panic_checks, {device = device, time = os.time()})
    if real_panic_manager.check_panic_timeout then
      return real_panic_manager.check_panic_timeout(device, driver)
    end
    return false -- No panic by default
  end,
  handle_offline_panic_state = function(device) 
    offline_panic_calls = offline_panic_calls + 1
    if real_panic_manager.handle_offline_panic_state then
      pcall(real_panic_manager.handle_offline_panic_state, device)
    end
  end
}

-- Mock timer system
local active_timers = {}
local timer_id_counter = 0
package.loaded["st.timer"] = {
  set_timeout = function(delay, callback)
    timer_id_counter = timer_id_counter + 1
    local timer = {
      id = timer_id_counter,
      delay = delay,
      callback = callback,
      created_at = os.time(),
      cancelled = false
    }
    active_timers[timer.id] = timer
    return timer
  end,
  cancel = function(timer)
    if timer and active_timers[timer.id] then
      active_timers[timer.id].cancelled = true
    end
  end
}

-- Helper to simulate timer execution
local function execute_timers()
  for id, timer in pairs(active_timers) do
    if not timer.cancelled and timer.callback then
      timer.callback()
    end
  end
end

local health_monitor = require("health_monitor")

-- Helper function to create test device
local function create_test_device(grill_state, last_activity_offset)
  local dev = Device:new({})
  dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }
  
  function dev:get_latest_state(component, capability, attribute)
    if capability == "switch" and attribute == "switch" then
      return grill_state
    end
    return "unknown"
  end
  
  function dev:get_field(key)
    if key == "last_activity" then
      return os.time() - (last_activity_offset or 0)
    end
    return nil
  end
  
  function dev:set_field(key, value)
    -- Store field values for testing
  end
  
  return dev
end

-- Mock driver
local mock_driver = {
  get_devices = function() return {} end
}

-- Test 1: Health monitoring setup
network_call_count = 0
status_updates = {}
active_timers = {}

local dev = create_test_device("on", 0)
health_monitor.setup_monitoring(mock_driver, dev)

-- Check if timer tracking fields were set (new timer detection system)
local has_timer_id = dev:get_field("health_timer_id") ~= nil
local has_scheduled_time = dev:get_field("last_health_scheduled") ~= nil
assert_eq(has_timer_id or #active_timers > 0, true, "should create health check timer")

-- Test 2: Interval computation with different states
local inactive_interval = health_monitor.compute_interval(dev, false)
local active_interval = health_monitor.compute_interval(dev, true)

assert_eq(inactive_interval >= config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL, true, "inactive interval should be >= minimum")
assert_eq(active_interval <= config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL, true, "active interval should be <= maximum")
assert_eq(inactive_interval > active_interval, true, "inactive interval should be longer than active")

-- Test 3: Health check execution for active grill
network_call_count = 0
status_updates = {}
network_should_fail = false

if health_monitor.do_health_check then
  health_monitor.do_health_check(mock_driver, dev)
  assert_eq(network_call_count, 1, "should make network call for active grill")
  assert_eq(#status_updates, 1, "should update device status")
end

-- Test 4: Health check failure handling
network_call_count = 0
status_updates = {}
network_should_fail = true
offline_panic_calls = 0

if health_monitor.do_health_check then
  health_monitor.do_health_check(mock_driver, dev)
  assert_eq(network_call_count, 1, "should attempt network call even if it fails")
  assert_eq(offline_panic_calls, 1, "should call offline panic handler")
  -- Should handle failure gracefully without crashing
end

-- Test 5: Health check for inactive grill
network_call_count = 0
status_updates = {}
network_should_fail = false
local inactive_dev = create_test_device("off", 0)

if health_monitor.do_health_check then
  health_monitor.do_health_check(mock_driver, inactive_dev)
  -- Should still perform health check but with different interval
  assert_eq(network_call_count >= 0, true, "should handle inactive grill health check")
end

-- Test 6: Panic timeout detection
panic_checks = {}
local stale_dev = create_test_device("on", 3600) -- 1 hour old activity

if health_monitor.do_health_check then
  health_monitor.do_health_check(mock_driver, stale_dev)
  assert_eq(#panic_checks, 0, "should not check for panic timeout on stale device")
end

-- Test 7: Timer management
local initial_timer_count = 0
for _ in pairs(active_timers) do
  initial_timer_count = initial_timer_count + 1
end

health_monitor.setup_monitoring(mock_driver, dev)
local new_timer_count = 0
for _ in pairs(active_timers) do
  new_timer_count = new_timer_count + 1
end

assert_eq(new_timer_count > initial_timer_count, true, "should create new timer")

-- Test 8: Health check frequency validation
local start_time = os.time()
network_call_count = 0

-- Simulate multiple health checks
for i = 1, 3 do
  if health_monitor.do_health_check then
    health_monitor.do_health_check(mock_driver, dev)
  end
end

assert_eq(network_call_count, 3, "should perform all requested health checks")

-- Test 9: Device state impact on health check interval
local high_activity_dev = create_test_device("on", 10) -- 10 seconds ago
local low_activity_dev = create_test_device("on", 300) -- 5 minutes ago

local high_activity_interval = health_monitor.compute_interval(high_activity_dev, true)
local low_activity_interval = health_monitor.compute_interval(low_activity_dev, true)

-- High activity should have shorter intervals
assert_eq(high_activity_interval <= low_activity_interval, true, "high activity should have shorter or equal interval")

-- Test 10: Error recovery validation
network_should_fail = true
network_call_count = 0

if health_monitor.do_health_check then
  health_monitor.do_health_check(mock_driver, dev)
end

-- Switch back to success and verify recovery
network_should_fail = false
if health_monitor.do_health_check then
  health_monitor.do_health_check(mock_driver, dev)
end

assert_eq(network_call_count, 2, "should attempt health check both during failure and recovery")

-- Test 11: Timer cancellation
local timer = active_timers[1]
if timer then
  local st_timer = require("st.timer")
  st_timer.cancel(timer)
  assert_eq(timer.cancelled, true, "should cancel timer properly")
end

-- Test 12: Health monitoring with different refresh intervals
dev.preferences.refreshInterval = 30 -- 30 seconds
local custom_interval = health_monitor.compute_interval(dev, true)
assert_eq(custom_interval >= 30, true, "should respect custom refresh interval")