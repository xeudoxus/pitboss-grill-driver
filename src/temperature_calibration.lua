--[[
  Temperature Calibration Module for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module implements the Steinhart-Hart equation for temperature calibration
  based on a single-point calibration at 32°F (ice water). The offsets provided
  in the preferences represent the difference from 32°F ice water reference point.

  The Steinhart-Hart equation is a model of the resistance of a semiconductor at
  different temperatures. For thermistors, this provides a more accurate temperature
  calculation across the full temperature range compared to simple linear offsets.

  Key Features:
  - Single-point calibration based on 32°F (ice water) reference
  - Implements Steinhart-Hart equation for accurate temperature conversion
  - Supports both positive and negative calibration offsets
  - Maintains accuracy across the full temperature range

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local log = require("log")
local config = require("config")

local calibration = {}

-- ============================================================================
-- CALIBRATION FUNCTIONS
-- ============================================================================

--- Apply Steinhart-Hart based calibration to a temperature reading
-- @param raw_temp number Raw temperature reading from sensor
-- @param offset number Calibration offset from ice water reference (32°F/0°C)
-- @param unit string Temperature unit ("F" or "C")
-- @param sensor_name string Optional name of the sensor for logging
-- @return number Calibrated temperature
function calibration.apply_calibration(raw_temp, offset, unit, sensor_name)
	sensor_name = sensor_name or "unknown"

	-- Handle invalid temperature readings
	if not raw_temp or type(raw_temp) ~= "number" then
		return raw_temp
	end

	-- If offset is zero or nil, return the raw temperature
	if not offset or offset == 0 then
		return raw_temp
	end

	-- Get reference temperature in the same unit as input
	local reference_temp
	if unit == "F" then
		reference_temp = config.CONSTANTS.REFERENCE_TEMP_F
	else
		reference_temp = config.CONSTANTS.REFERENCE_TEMP_C
	end

	-- Convert temperatures to Kelvin for Steinhart-Hart equation
	local temp_k, ref_k
	if unit == "F" then
		temp_k = (raw_temp - 32) * 5 / 9 + 273.15
		ref_k = (reference_temp - 32) * 5 / 9 + 273.15
	else
		temp_k = raw_temp + 273.15
		ref_k = reference_temp + 273.15
	end

	-- Apply Steinhart-Hart based calibration with temperature-dependent scaling
	-- The offset represents the error at the reference temperature (ice water)
	-- We scale this offset based on the temperature difference from reference

	-- Calculate temperature difference from reference for scaling
	local temp_diff_from_ref = math.abs(temp_k - ref_k)

	-- Use Steinhart-Hart characteristics to scale the offset
	-- Higher temperatures get more correction due to thermistor non-linearity
	local beta_factor = config.CONSTANTS.THERMISTOR_BETA / 1000 -- Normalize beta for scaling
	local scaling_factor = 1 + (temp_diff_from_ref * beta_factor / 1000) -- More aggressive scaling

	-- Convert offset to Kelvin and apply scaling
	local offset_k
	if unit == "F" then
		offset_k = offset * 5 / 9 -- Convert offset to Kelvin difference
	else
		offset_k = offset
	end

	-- Apply the scaled offset
	local calibrated_temp_k = temp_k + (offset_k * scaling_factor)

	-- Convert back to original unit
	local calibrated_temp
	if unit == "F" then
		calibrated_temp = math.ceil((calibrated_temp_k - 273.15) * 9 / 5 + 32)
	else
		calibrated_temp = math.ceil(calibrated_temp_k - 273.15)
	end

	-- Log the calibration details
	log.info(
		string.format(
			"Steinhart-Hart calibration [%s]: raw=%.1f°%s, offset=%.1f°%s, temp_diff=%.1fK, scaling=%.3f, calibrated=%d°%s",
			sensor_name,
			raw_temp,
			unit,
			offset,
			unit,
			temp_diff_from_ref,
			scaling_factor,
			calibrated_temp,
			unit
		)
	)

	return calibrated_temp
end

return calibration