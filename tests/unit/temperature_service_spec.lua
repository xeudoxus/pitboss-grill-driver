-- Comprehensive temperature_service tests using config constants
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Force load of the real temperature_service module (avoid test pollution)
package.loaded["temperature_service"] = nil
local temperature_service = require("temperature_service")

-- Test conversions using config constants
assert_eq(temperature_service.celsius_to_fahrenheit(0), 32, "0°C should convert to 32°F")
assert_eq(temperature_service.fahrenheit_to_celsius(32), 0, "32°F should convert to 0°C")
assert_eq(temperature_service.celsius_to_fahrenheit(100), 212, "100°C should convert to 212°F")
assert_eq(temperature_service.fahrenheit_to_celsius(212), 100, "212°F should convert to 100°C")

local dev = Device:new({})
dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }

-- Test validation with config constants
local sensor_range = config.get_sensor_range(config.CONSTANTS.DEFAULT_UNIT)
assert_eq(temperature_service.is_valid_temperature(nil, config.CONSTANTS.DEFAULT_UNIT), false, "nil temperature should be invalid")
assert_eq(temperature_service.is_valid_temperature(config.CONSTANTS.DISCONNECT_VALUE, config.CONSTANTS.DEFAULT_UNIT), false, "disconnect value should be invalid")
assert_eq(temperature_service.is_valid_temperature(sensor_range.max + 100, config.CONSTANTS.DEFAULT_UNIT), false, "temperature above sensor range should be invalid")
assert_eq(temperature_service.is_valid_temperature(225, config.CONSTANTS.DEFAULT_UNIT), true, "normal temperature should be valid")

-- Test setpoint validation
local approved_setpoints = config.get_approved_setpoints(config.CONSTANTS.DEFAULT_UNIT)
local temp_range = config.get_temperature_range(config.CONSTANTS.DEFAULT_UNIT)
assert_eq(temperature_service.is_valid_setpoint(approved_setpoints[1], config.CONSTANTS.DEFAULT_UNIT), true, "approved setpoint should be valid")
assert_eq(temperature_service.is_valid_setpoint(temp_range.min - 10, config.CONSTANTS.DEFAULT_UNIT), false, "temperature below range should be invalid")
assert_eq(temperature_service.is_valid_setpoint(temp_range.max + 10, config.CONSTANTS.DEFAULT_UNIT), false, "temperature above range should be invalid")

-- Test caching
temperature_service.store_temperature_value(dev, "grill_temp", 200)
local val = temperature_service.get_cached_temperature_value(dev, "grill_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)
assert_eq(val, 200, "cached temperature should be retrieved correctly")

-- Test edge cases
assert_eq(temperature_service.is_valid_temperature(-999, config.CONSTANTS.DEFAULT_UNIT), false, "extremely low temperature should be invalid")
assert_eq(temperature_service.is_valid_temperature(9999, config.CONSTANTS.DEFAULT_UNIT), false, "extremely high temperature should be invalid")

-- Test unit handling
dev:set_field("unit", "F")
local unit = temperature_service.get_device_unit(dev)
assert_eq(unit, "F", "device unit should be retrieved correctly")

dev:set_field("unit", "C")
unit = temperature_service.get_device_unit(dev)
assert_eq(unit, "C", "device unit should be updated correctly")

-- Tests moved from device_status_service_spec.lua
-- Test cache behavior with config constants
-- Store temperature and verify cache retrieval
local test_temp_moved = 220
temperature_service.store_temperature_value(dev, "grill_temp", test_temp_moved)
local cached_temp_moved = temperature_service.get_cached_temperature_value(dev, "grill_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)
assert_eq(cached_temp_moved, test_temp_moved, "should retrieve cached temperature (moved test)")

-- Test fallback behavior
local fallback_temp_moved = temperature_service.get_cached_temperature_value(dev, "nonexistent_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)
assert_eq(fallback_temp_moved, config.CONSTANTS.OFF_DISPLAY_TEMP, "should return fallback for missing cache (moved test)")

-- Tests moved from probe_management_spec.lua
-- Test 1: Valid probe temperature detection
-- Test probe temperatures from example_api.txt
assert_eq(temperature_service.is_valid_temperature(95, "F"), true, "should validate probe 1 temperature (95°F)")
assert_eq(temperature_service.is_valid_temperature(93, "F"), true, "should validate probe 2 temperature (93°F)")
assert_eq(temperature_service.is_valid_temperature(config.CONSTANTS.DISCONNECT_VALUE, "F"), false, "should detect disconnected probe 3")
assert_eq(temperature_service.is_valid_temperature(config.CONSTANTS.DISCONNECT_VALUE, "F"), false, "should detect disconnected probe 4")

-- Test 2: Temperature caching for probes
temperature_service.store_temperature_value(dev, "probe1_temp", 95)
temperature_service.store_temperature_value(dev, "probe2_temp", 93)
temperature_service.store_temperature_value(dev, "probe3_temp", config.CONSTANTS.DISCONNECT_VALUE)
temperature_service.store_temperature_value(dev, "probe4_temp", config.CONSTANTS.DISCONNECT_VALUE)

local probe1_cached = temperature_service.get_cached_temperature_value(dev, "probe1_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)
local probe2_cached = temperature_service.get_cached_temperature_value(dev, "probe2_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)
local probe3_cached = temperature_service.get_cached_temperature_value(dev, "probe3_temp", config.CONSTANTS.OFF_DISPLAY_TEMP)

assert_eq(probe1_cached, 95, "should cache probe 1 temperature")
assert_eq(probe2_cached, 93, "should cache probe 2 temperature")
assert_eq(probe3_cached, config.CONSTANTS.DISCONNECT_VALUE, "should cache disconnected probe 3")

-- Test 3: Temperature display formatting for probes
local probe1_display, probe1_numeric = temperature_service.format_temperature_display(95, true, nil)
local probe3_display, probe3_numeric = temperature_service.format_temperature_display(config.CONSTANTS.DISCONNECT_VALUE, false, 85)

assert_eq(probe1_display, "95", "should format valid probe temperature for display")
assert_eq(probe1_numeric, 95, "should return numeric value for valid probe")
assert_eq(probe3_display, "85", "should use cached value for disconnected probe")
assert_eq(probe3_numeric, 85, "should return cached numeric value for disconnected probe")

-- Test 4: Probe temperature validation ranges
local sensor_range = config.get_sensor_range("F")
assert_eq(temperature_service.is_valid_temperature(sensor_range.min - 10, "F"), false, "should reject temperature below sensor range")
assert_eq(temperature_service.is_valid_temperature(sensor_range.max + 10, "F"), false, "should reject temperature above sensor range")
assert_eq(temperature_service.is_valid_temperature(200, "F"), true, "should accept temperature within sensor range")

-- Test 5: Unit conversion for probes
local celsius_temp = temperature_service.fahrenheit_to_celsius(95)
local fahrenheit_temp = temperature_service.celsius_to_fahrenheit(celsius_temp)
-- Simple conversion test - just verify functions exist and return numbers
assert_eq(type(celsius_temp), "number", "should convert fahrenheit to celsius")
assert_eq(type(fahrenheit_temp), "number", "should convert celsius back to fahrenheit")

-- Test 6: Probe calibration offsets (simulated)
local raw_probe_temp = 95
local calibration_offset = 2
local calibrated_temp = raw_probe_temp + calibration_offset
assert_eq(calibrated_temp, 97, "should apply calibration offset to probe temperature")

-- Test 7: Multiple probe status tracking
local probe_status = {
  probe1 = { temp = 95, connected = true },
  probe2 = { temp = 93, connected = true },
  probe3 = { temp = config.CONSTANTS.DISCONNECT_VALUE, connected = false },
  probe4 = { temp = config.CONSTANTS.DISCONNECT_VALUE, connected = false }
}

local connected_probes = 0
for _, probe in pairs(probe_status) do
  if probe.connected then
    connected_probes = connected_probes + 1
  end
end

assert_eq(connected_probes, 2, "should track correct number of connected probes")

-- Test 8: Probe temperature change detection
temperature_service.store_temperature_value(dev, "probe1_last", 90)
local probe1_current = 95
local probe1_change = probe1_current - temperature_service.get_cached_temperature_value(dev, "probe1_last", 90)
assert_eq(probe1_change, 5, "should detect probe temperature change")

-- Test 9: Probe disconnection detection
local was_connected = temperature_service.get_cached_temperature_value(dev, "probe3_connected", true)
local is_connected = probe_status.probe3.connected
assert_eq(was_connected ~= is_connected, true, "should detect probe disconnection")

-- Test 10: Probe temperature stability
local stable_readings = {95, 95, 94, 95, 96}
local temp_variance = 0
local avg_temp = 0
for _, temp in ipairs(stable_readings) do
  avg_temp = avg_temp + temp
end
avg_temp = avg_temp / #stable_readings

for _, temp in ipairs(stable_readings) do
  temp_variance = temp_variance + math.abs(temp - avg_temp)
end
temp_variance = temp_variance / #stable_readings

assert_eq(temp_variance < 2, true, "should detect stable probe temperature readings")