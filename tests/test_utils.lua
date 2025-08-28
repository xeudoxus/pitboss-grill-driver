---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil
-- Enhanced test utilities for Pit Boss driver tests
-- Provides comprehensive mocking, fixtures, and assertion helpers

local TestUtils = {}

-- Import existing helpers to maintain compatibility
local existing_helpers = require("tests.test_helpers")

-- Re-export existing functionality
TestUtils.setup_network_recorder = existing_helpers.setup_network_recorder
TestUtils.setup_device_status_stub = existing_helpers.setup_device_status_stub
TestUtils.install_status_message_recorder = existing_helpers.install_status_message_recorder
TestUtils.assert_eq = existing_helpers.assert_eq

-- Enhanced assertion helpers
function TestUtils.assert_not_nil(value, msg)
  if value == nil then
    error((msg or "Expected non-nil value") .. " (got nil)", 2)
  end
end

function TestUtils.assert_nil(value, msg)
  if value ~= nil then
    error((msg or "Expected nil value") .. string.format(" (got: %s)", tostring(value)), 2)
  end
end

function TestUtils.assert_true(value, msg)
  if value ~= true then
    error((msg or "Expected true") .. string.format(" (got: %s)", tostring(value)), 2)
  end
end

function TestUtils.assert_false(value, msg)
  if value ~= false then
    error((msg or "Expected false") .. string.format(" (got: %s)", tostring(value)), 2)
  end
end

function TestUtils.assert_contains(table_or_string, value, msg)
  local found = false
  
  if type(table_or_string) == "table" then
    for _, v in pairs(table_or_string) do
      if v == value then
        found = true
        break
      end
    end
  elseif type(table_or_string) == "string" then
    found = string.find(table_or_string, value, 1, true) ~= nil
  end
  
  if not found then
    error((msg or "Expected to contain value") .. string.format(" (value: %s not found)", tostring(value)), 2)
  end
end

function TestUtils.assert_not_contains(table_or_string, value, msg)
  local found = false
  
  if type(table_or_string) == "table" then
    for _, v in pairs(table_or_string) do
      if v == value then
        found = true
        break
      end
    end
  elseif type(table_or_string) == "string" then
    found = string.find(table_or_string, value, 1, true) ~= nil
  end
  
  if found then
    error((msg or "Expected not to contain value") .. string.format(" (value: %s found)", tostring(value)), 2)
  end
end

function TestUtils.assert_type(value, expected_type, msg)
  local actual_type = type(value)
  if actual_type ~= expected_type then
    error((msg or "Type mismatch") .. string.format(" (expected: %s, got: %s)", expected_type, actual_type), 2)
  end
end

function TestUtils.assert_greater_than(actual, expected, msg)
  if actual <= expected then
    error((msg or "Expected greater than") .. string.format(" (got: %s, expected > %s)", tostring(actual), tostring(expected)), 2)
  end
end

function TestUtils.assert_less_than(actual, expected, msg)
  if actual >= expected then
    error((msg or "Expected less than") .. string.format(" (got: %s, expected < %s)", tostring(actual), tostring(expected)), 2)
  end
end

-- Device fixture factory
function TestUtils.create_device_fixture(options)
  options = options or {}
  local config = require("config") -- Always use REAL config from src/
  local Device = require("device")
  
  local device = Device:new({})
  device.id = options.id or ("test-device-" .. tostring(math.random(1000, 9999)))
  device.preferences = options.preferences or {
    refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL
  }
  
  -- Set up profile with components
  device.profile = device.profile or { components = {} }
  device.profile.components["Standard_Grill"] = { id = "Standard_Grill" }
  
  -- Set initial state
  device._latest_state = options.state or "off"
  device._fields = options.fields or {}
  
  -- Mock methods
  function device:get_latest_state(component, cap_id, attr)
    if component == "Standard_Grill" then
      return self._latest_state
    end
    return self._latest_state or "off"
  end
  
  function device:set_field(key, value)
    self._fields[key] = value
  end
  
  function device:get_field(key)
    return self._fields[key]
  end
  
  function device:emit_event(event)
    self._last_event = event
    if self._event_recorder then
      table.insert(self._event_recorder, event)
    end
  end
  
  -- Set up driver mock
  device.driver = options.driver or {
    get_devices = function() return {} end
  }
  
  return device
end

-- Virtual device fixture factory
function TestUtils.create_virtual_device_fixture(parent_device, child_key, options)
  options = options or {}
  
  local virtual_device = TestUtils.create_device_fixture(options)
  virtual_device.parent_device_id = parent_device.id
  virtual_device.parent_assigned_child_key = child_key
  
  return virtual_device
end

-- Event recorder for devices
function TestUtils.setup_event_recorder(device)
  device._event_recorder = device._event_recorder or {}
  
  local recorder = {
    events = device._event_recorder,
    clear = function()
      for i = #device._event_recorder, 1, -1 do
        table.remove(device._event_recorder, i)
      end
    end,
    get_last_event = function()
      return device._event_recorder[#device._event_recorder]
    end,
    get_events_by_capability = function(capability)
      local filtered = {}
      for _, event in ipairs(device._event_recorder) do
        if event.capability and event.capability == capability then
          table.insert(filtered, event)
        end
      end
      return filtered
    end
  }
  
  return recorder
end

-- Timer mock factory
function TestUtils.create_timer_mock()
  local timers = {}
  local timer_id = 0
  
  local mock = {
    timers = timers,
    call_once = function(delay, callback)
      timer_id = timer_id + 1
      local timer = {
        id = timer_id,
        delay = delay,
        callback = callback,
        cancelled = false
      }
      timers[timer_id] = timer
      return timer
    end,
    call_with_delay = function(delay, callback)
      return mock.call_once(delay, callback)
    end,
    cancel = function(timer)
      if timer and timer.id and timers[timer.id] then
        timers[timer.id].cancelled = true
      end
    end,
    -- Test utilities
    trigger_timer = function(timer_id_or_timer)
      local timer_id = type(timer_id_or_timer) == "table" and timer_id_or_timer.id or timer_id_or_timer
      local timer = timers[timer_id]
      if timer and not timer.cancelled then
        timer.callback()
        return true
      end
      return false
    end,
    trigger_all_timers = function()
      for _, timer in pairs(timers) do
        if not timer.cancelled then
          timer.callback()
        end
      end
    end,
    clear_all_timers = function()
      for k in pairs(timers) do
        timers[k] = nil
      end
    end,
    get_active_timer_count = function()
      local count = 0
      for _, timer in pairs(timers) do
        if not timer.cancelled then
          count = count + 1
        end
      end
      return count
    end
  }
  
  return mock
end

-- Network mock with advanced features
function TestUtils.create_advanced_network_mock(options)
  options = options or {}
  
  local mock = {
    sent_commands = {},
    responses = options.responses or {},
    should_fail = options.should_fail or false,
    delay_responses = options.delay_responses or false,
    
    send_command = function(device, cmd, arg, driver)
      if mock.should_fail then
        return false
      end
      
      local entry = {
        cmd = cmd,
        arg = arg,
        device = device,
        timestamp = os.time()
      }
      
      table.insert(mock.sent_commands, entry)
      
      -- Simulate response if configured
      if mock.responses[cmd] then
        local response = mock.responses[cmd]
        if type(response) == "function" then
          response(device, cmd, arg)
        end
      end
      
      return true
    end,
    
    validate_ip_address = function(ip)
      if not ip or ip == "" then return false, "Invalid IP address" end
      local a,b,c,d = ip:match('^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$')
      if not a then return false, "Invalid IP address format" end
      a,b,c,d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
      if not a or a < 1 or a > 255 then return false, "Invalid IP address segment" end
      return true, "Valid IP"
    end,
    
    -- Test utilities
    clear_sent = function()
      for i = #mock.sent_commands, 1, -1 do
        table.remove(mock.sent_commands, i)
      end
    end,
    
    get_last_command = function()
      return mock.sent_commands[#mock.sent_commands]
    end,
    
    get_commands_by_type = function(cmd_type)
      local filtered = {}
      for _, cmd in ipairs(mock.sent_commands) do
        if cmd.cmd == cmd_type then
          table.insert(filtered, cmd)
        end
      end
      return filtered
    end,
    
    set_response = function(cmd, response)
      mock.responses[cmd] = response
    end,
    
    simulate_failure = function(should_fail)
      mock.should_fail = should_fail
    end
  }
  
  -- Install the mock
  package.loaded["network_utils"] = mock
  _G.sent_commands = mock.sent_commands
  
  return mock
end

-- Test environment setup
function TestUtils.setup_test_environment(options)
  options = options or {}
  
  local env = {
    network_mock = nil,
    timer_mock = nil,
    device_fixtures = {},
    cleanup_functions = {}
  }
  
  -- Setup network mock if requested
  if options.network ~= false then
    env.network_mock = TestUtils.create_advanced_network_mock(options.network_options)
  end
  
  -- Setup timer mock if requested
  if options.timers then
    env.timer_mock = TestUtils.create_timer_mock()
    package.loaded["st.timer"] = env.timer_mock
  end
  
  -- Setup device status service if requested
  if options.device_status ~= false then
    TestUtils.setup_device_status_stub()
  end
  
  -- Cleanup function
  env.cleanup = function()
    for _, cleanup_fn in ipairs(env.cleanup_functions) do
      cleanup_fn()
    end
    
    if env.network_mock then
      env.network_mock.clear_sent()
    end
    
    if env.timer_mock then
      env.timer_mock.clear_all_timers()
    end
  end
  
  return env
end

-- Test data generators
function TestUtils.generate_temperature_data(count, options)
  options = options or {}
  local min_temp = options.min or 70
  local max_temp = options.max or 500
  local unit = options.unit or "F"
  
  local data = {}
  for i = 1, count do
    table.insert(data, {
      temperature = math.random(min_temp, max_temp),
      unit = unit,
      timestamp = os.time() + i
    })
  end
  
  return data
end

function TestUtils.generate_device_status_data(options)
  options = options or {}
  
  return {
    power_state = options.power_state or "on",
    grill_temp = options.grill_temp or 225,
    target_temp = options.target_temp or 250,
    probe_temps = options.probe_temps or {165, 0, 0, 0},
    pellet_level = options.pellet_level or 75,
    light_state = options.light_state or "off",
    unit = options.unit or "F"
  }
end

-- Performance testing utilities
function TestUtils.measure_execution_time(func, iterations)
  iterations = iterations or 1
  
  local start_time = os.clock()
  
  for i = 1, iterations do
    func()
  end
  
  local end_time = os.clock()
  local total_time = end_time - start_time
  
  return {
    total_time = total_time,
    average_time = total_time / iterations,
    iterations = iterations
  }
end

-- Memory usage tracking (basic)
function TestUtils.get_memory_usage()
  collectgarbage("collect")
  return collectgarbage("count")
end

function TestUtils.measure_memory_usage(func)
  local before = TestUtils.get_memory_usage()
  func()
  collectgarbage("collect")
  local after = TestUtils.get_memory_usage()
  
  return {
    before = before,
    after = after,
    delta = after - before
  }
end

return TestUtils