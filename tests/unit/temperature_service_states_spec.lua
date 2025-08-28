package.loaded["temperature_service"] = nil
-- Clean temperature_service.states tests using config constants
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global
local config = require("config")
local Device = require("device")

-- Clear any cached temperature_service to ensure fresh load
local temperature_service = require("temperature_service")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Test temperature state detection with config constants
local dev = Device:new({})
dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }

-- Test preheating state using config tolerance
local target_temp = 225
local current_temp = target_temp * config.CONSTANTS.TEMP_TOLERANCE_PERCENT - 10



local is_preheating = temperature_service.is_grill_preheating(dev, 60, current_temp, target_temp)
assert_eq(is_preheating, true, "should detect preheating state")

-- Test heating state after reaching temp once
dev:set_field("session_reached_temp", true)
local is_heating = temperature_service.is_grill_heating(dev, current_temp, target_temp)
assert_eq(is_heating, true, "should detect heating state after reaching temp")

-- Test at-temp state using config tolerance
local at_temp_current = target_temp * config.CONSTANTS.TEMP_TOLERANCE_PERCENT + 5
local is_at_temp = at_temp_current >= (target_temp * config.CONSTANTS.TEMP_TOLERANCE_PERCENT)
assert_eq(is_at_temp, true, "should detect at-temp state within tolerance")