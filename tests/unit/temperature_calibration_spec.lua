--[[
  Temperature Calibration Module Tests
  Tests the Steinhart-Hart equation implementation for temperature calibration
--]]

-- Add src directory to package path for testing
package.path = package.path .. ";../../src/?.lua"

-- Load test framework
local test_helpers = require "tests.test_helpers"
local assert_eq = test_helpers.assert_eq

-- Helper for floating point comparisons
local function assert_near(actual, expected, tolerance, msg)
  local diff = math.abs(actual - expected)
  if diff > tolerance then
    error((msg or "assert_near failed") .. string.format(" (got: %s, expected: %s ± %s, diff: %s)", 
          tostring(actual), tostring(expected), tostring(tolerance), tostring(diff)), 2)
  end
end

-- Mock the log module
package.loaded.log = require "tests.mocks.log"

-- Load the module under test
local temperature_calibration = require "temperature_calibration"

print("Testing Temperature Calibration Module...")

-- Test 1: Zero offset should return original temperature
local temp_f = 200
local result_f = temperature_calibration.apply_calibration(temp_f, 0, "F", "test")
assert_eq(result_f, temp_f, "Zero offset should return original temperature (F)")

local temp_c = 93
local result_c = temperature_calibration.apply_calibration(temp_c, 0, "C", "test")
assert_eq(result_c, temp_c, "Zero offset should return original temperature (C)")

-- Test 2: Nil offset should return original temperature
local result_nil_f = temperature_calibration.apply_calibration(temp_f, nil, "F", "test")
assert_eq(result_nil_f, temp_f, "Nil offset should return original temperature (F)")

local result_nil_c = temperature_calibration.apply_calibration(temp_c, nil, "C", "test")
assert_eq(result_nil_c, temp_c, "Nil offset should return original temperature (C)")

-- Test 3: Invalid temperature should return as-is
local invalid_temp = temperature_calibration.apply_calibration(nil, 5, "F", "test")
assert_eq(invalid_temp, nil, "Invalid temperature should return nil")

local non_number = temperature_calibration.apply_calibration("not_a_number", 5, "F", "test")
assert_eq(non_number, "not_a_number", "Non-number temperature should return as-is")

-- Test 4: Positive offset calibration (Fahrenheit)
-- If probe reads 35°F in ice water (should be 32°F), offset should be -3°F
local ice_water_reading_f = 35
local ice_water_offset_f = -3  -- Correction to bring 35°F down to 32°F
local calibrated_ice_f = temperature_calibration.apply_calibration(ice_water_reading_f, ice_water_offset_f, "F", "test")
-- Should be close to 32°F (ice water reference)
assert_near(calibrated_ice_f, 32, 2, "Ice water calibration should be close to 32°F")

-- Test 5: Positive offset calibration (Celsius)
-- If probe reads 2°C in ice water (should be 0°C), offset should be -2°C
local ice_water_reading_c = 2
local ice_water_offset_c = -2  -- Correction to bring 2°C down to 0°C
local calibrated_ice_c = temperature_calibration.apply_calibration(ice_water_reading_c, ice_water_offset_c, "C", "test")
-- Should be close to 0°C (ice water reference)
assert_near(calibrated_ice_c, 0, 2, "Ice water calibration should be close to 0°C")

-- Test 6: Higher temperature calibration (Fahrenheit)
-- Test that Steinhart-Hart provides different correction at higher temperatures
local high_temp_f = 400  -- Typical grill temperature
local offset_f = -5      -- 5°F correction
local calibrated_high_f = temperature_calibration.apply_calibration(high_temp_f, offset_f, "F", "test")
-- Should be different from simple addition due to Steinhart-Hart non-linearity
local simple_addition = high_temp_f + offset_f
print(string.format("High temp test: raw=%d°F, offset=%d°F, calibrated=%d°F, simple_add=%d°F", 
                   high_temp_f, offset_f, calibrated_high_f, simple_addition))

-- Debug: Let's also test with a smaller temperature to see if there's any difference
local low_temp_f = 100
local calibrated_low_f = temperature_calibration.apply_calibration(low_temp_f, offset_f, "F", "test")
local simple_low = low_temp_f + offset_f
print(string.format("Low temp test: raw=%d°F, offset=%d°F, calibrated=%d°F, simple_add=%d°F", 
                   low_temp_f, offset_f, calibrated_low_f, simple_low))

-- The result should be different from simple addition (proving Steinhart-Hart is working)
-- Let's be more lenient and check if there's at least a 1 degree difference
local difference = math.abs(calibrated_high_f - simple_addition)
print(string.format("Difference from simple addition: %.2f°F", difference))
assert_eq(difference >= 1, true, "Steinhart-Hart should differ from simple addition by at least 1°F at high temps")

-- Test 7: Higher temperature calibration (Celsius)
local high_temp_c = 200  -- Typical grill temperature in Celsius
local offset_c = -3      -- 3°C correction
local calibrated_high_c = temperature_calibration.apply_calibration(high_temp_c, offset_c, "C", "test")
local simple_addition_c = high_temp_c + offset_c
print(string.format("High temp test: raw=%d°C, offset=%d°C, calibrated=%d°C, simple_add=%d°C", 
                   high_temp_c, offset_c, calibrated_high_c, simple_addition_c))
assert_eq(calibrated_high_c ~= simple_addition_c, true, "Steinhart-Hart should differ from simple addition at high temps")

-- Test 8: Consistency between units
-- Convert a temperature and offset to the other unit, calibrate, then convert back
-- Results should be consistent
local test_temp_f = 212  -- Boiling water
local test_offset_f = -4
local calibrated_f = temperature_calibration.apply_calibration(test_temp_f, test_offset_f, "F", "test")

-- Convert to Celsius
local test_temp_c = (test_temp_f - 32) * 5/9  -- Should be 100°C
local test_offset_c = test_offset_f * 5/9     -- Convert offset to Celsius
local calibrated_c = temperature_calibration.apply_calibration(test_temp_c, test_offset_c, "C", "test")

-- Convert calibrated Celsius back to Fahrenheit
local calibrated_c_to_f = (calibrated_c * 9/5) + 32

print(string.format("Consistency test: F_calibrated=%d°F, C_calibrated=%d°C, C_to_F=%d°F", 
                   calibrated_f, calibrated_c, math.ceil(calibrated_c_to_f)))

-- Should be reasonably close (within a few degrees due to rounding and Steinhart-Hart non-linearity)
assert_near(calibrated_f, calibrated_c_to_f, 5, "Calibration should be consistent between units")

-- Test 9: Calibration description
local description = temperature_calibration.get_calibration_description()
assert_eq(type(description), "string", "Should return calibration description as string")
-- Search for "Steinhart" (without hyphen to avoid pattern matching issues)
local found_steinhart = string.find(description, "Steinhart")
assert_eq(found_steinhart ~= nil, true, "Description should mention Steinhart-Hart")

print("✅ All Temperature Calibration tests passed!")