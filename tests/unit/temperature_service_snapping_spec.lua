package.loaded["temperature_service"] = nil
-- Clean temperature_service.snapping tests using config constants
---@diagnostic disable: redundant-parameter
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global
local config = require("config")
local Device = require("device")
local temperature_service = require("temperature_service")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Test snapping with config-provided setpoints
local devF = Device:new({})
devF:set_field("unit", config.CONSTANTS.DEFAULT_UNIT, {persist = true})

local devC = Device:new({})
devC:set_field("unit", "C", {persist = true})

-- Test Fahrenheit snapping using config setpoints
local f_setpoints = config.get_approved_setpoints(config.CONSTANTS.DEFAULT_UNIT)
assert_eq(type(f_setpoints), "table", "should get Fahrenheit setpoints from config")

local snapped_f1 = temperature_service.snap_to_approved_setpoint(201, config.CONSTANTS.DEFAULT_UNIT)
local snapped_f2 = temperature_service.snap_to_approved_setpoint(220, config.CONSTANTS.DEFAULT_UNIT)
assert_eq(snapped_f1, 200, "should snap 201F to 200F")
assert_eq(snapped_f2, 225, "should snap 220F to 225F (closer to 225 than 200)")

-- Test Celsius snapping using config setpoints
local c_setpoints = config.get_approved_setpoints("C")
assert_eq(type(c_setpoints), "table", "should get Celsius setpoints from config")

local snapped_c1 = temperature_service.snap_to_approved_setpoint(94, "C")
local snapped_c2 = temperature_service.snap_to_approved_setpoint(108, "C")
assert_eq(snapped_c1, 93, "should snap 94C to 93C")
assert_eq(snapped_c2, 107, "should snap 108C to 107C")

-- Test boundary conditions with config ranges
local temp_range = config.get_temperature_range(config.CONSTANTS.DEFAULT_UNIT)
local min_snap = temperature_service.snap_to_approved_setpoint(temp_range.min - 10, config.CONSTANTS.DEFAULT_UNIT)
local max_snap = temperature_service.snap_to_approved_setpoint(temp_range.max + 10, config.CONSTANTS.DEFAULT_UNIT)
assert_eq(min_snap, f_setpoints[1], "should snap below minimum to first setpoint")
assert_eq(max_snap, f_setpoints[#f_setpoints], "should snap above maximum to last setpoint")
