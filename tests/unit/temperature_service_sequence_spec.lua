---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

-- Ensure fresh module load
local temperature_service = require("temperature_service")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Simulate sequence: preheat -> reach at-temp -> increase setpoint slightly -> session should persist
do
  local dev = Device:new({})
  dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }

  local initial_target = 225
  local runtime = 60 -- not freshly turned on

  -- Step 1: starting below threshold => preheating
  local current_before = initial_target * config.CONSTANTS.TEMP_TOLERANCE_PERCENT - 5
  dev:set_field("session_reached_temp", false)
  local preheat = temperature_service.is_grill_preheating(dev, runtime, current_before, initial_target)
  assert_eq(preheat, true, "should be preheating before reaching temp")

  -- Step 2: reach at-temp => session flag set
  local current_at = initial_target * config.CONSTANTS.TEMP_TOLERANCE_PERCENT + 2
  temperature_service.track_session_temp_reached(dev, current_at, initial_target)
  assert_eq(dev:get_field("session_reached_temp"), true, "session_reached_temp should be true after reaching target")

  -- Step 3: small setpoint increase (less than reset threshold) should NOT reset session
  local small_increase_target = initial_target + 5 -- delta = 5 < 50
  temperature_service.track_session_temp_reached(dev, current_at, small_increase_target)
  assert_eq(dev:get_field("session_reached_temp"), true, "session should persist after small target increase")

  -- Confirm preheating/heating semantics after increase
  local still_preheating = temperature_service.is_grill_preheating(dev, runtime, current_at, small_increase_target)
  local heating = temperature_service.is_grill_heating(dev, current_at, small_increase_target)
  assert_eq(still_preheating, false, "not preheating after session reached")
  assert_eq(heating, true, "should be heating (re-heating) when below new threshold only if session reached")
end
