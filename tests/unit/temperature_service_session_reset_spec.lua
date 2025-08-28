---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global
local config = require("config")
local Device = require("device")

-- Ensure fresh module load
local temperature_service = require("temperature_service")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Case 1: last_target_temp stored as string, small setpoint change should NOT reset session
do
  local dev = Device:new({})
  dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }
  dev:set_field("last_target_temp", "225")
  dev:set_field("session_reached_temp", true)

  local current_temp = 225 -- above 225*0.95 threshold
  local new_target = 230 -- small change (< 50°F reset threshold)

  temperature_service.track_session_temp_reached(dev, current_temp, new_target)
  assert_eq(dev:get_field("session_reached_temp"), true, "session should persist for small change when last_target_temp was a string")
end

-- Case 2: large setpoint change should reset session
do
  local dev = Device:new({})
  dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }
  dev:set_field("last_target_temp", 200)
  dev:set_field("session_reached_temp", true)

  local current_temp = 200
  local new_target = 260 -- large change (>= 50°F)

  temperature_service.track_session_temp_reached(dev, current_temp, new_target)
  assert_eq(dev:get_field("session_reached_temp"), false, "session should reset on large target change")
end

-- Case 3: ensure last_target_temp stored as numeric after call
do
  local dev = Device:new({})
  dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }
  dev:set_field("last_target_temp", "225")
  dev:set_field("session_reached_temp", true)

  temperature_service.track_session_temp_reached(dev, 230, 230)
  local stored = dev:get_field("last_target_temp")
  assert_eq(type(stored), "number", "last_target_temp should be stored as a number")
end
