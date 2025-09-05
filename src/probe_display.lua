--[[
  Probe Display Generator for SmartThings Edge Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module generates properly spaced text for temperature probe displays
  in the SmartThings UI. It handles both 2-probe and 4-probe configurations
  with precise spacing that won't collapse in the SmartThings UI.

  Features:
  - Uses Unicode figure spaces (U+2007) to prevent space collapsing in SmartThings UI
  - Dynamically adjusts spacing based on temperature value lengths
  - Automatically detects whether to use 2-probe or 4-probe display format
  - Handles mixed temperature lengths with appropriate spacing

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

---@type Config
local config = require("config")
local M = {}

-- Module for generating properly spaced probe display text

-- ============================================================================
-- DISPLAY CONFIGURATION
-- ============================================================================

-- Unicode display constants
local UNICODE_SPACE = "\u{2007}" -- Figure space (U+2007) that won't collapse in UI
local UNICODE_F = "\u{00B0}\u{0046}" -- °F (degree sign + F)
local UNICODE_C = "\u{00B0}\u{0063}" -- °C (degree sign + c)
local REGULAR_SPACE = " " -- Regular space for specific cases

-- Default spacing patterns for 4-probe display
local FOUR_PROBE_SPACING_PATTERNS = {
	-- Pattern format: "digit1-digit2-digit3-digit4" = {spacing1, spacing2, spacing3}
	["2-2-2-2"] = {
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
	},
	["3-2-2-2"] = {
		UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
	},
	["2-3-2-2"] = {
		REGULAR_SPACE .. UNICODE_SPACE,
		UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
	},
	["2-2-3-2"] = {
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE,
		UNICODE_SPACE .. REGULAR_SPACE,
	},
	["2-2-2-3"] = {
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE,
		REGULAR_SPACE .. UNICODE_SPACE,
	},
	["3-2-2-3"] = { UNICODE_SPACE, REGULAR_SPACE .. UNICODE_SPACE, REGULAR_SPACE .. UNICODE_SPACE },
	["3-3-3-3"] = { UNICODE_SPACE, UNICODE_SPACE, UNICODE_SPACE },
	["2-3-3-2"] = { REGULAR_SPACE .. UNICODE_SPACE, UNICODE_SPACE, UNICODE_SPACE .. REGULAR_SPACE },
	["3-3-2-3"] = { UNICODE_SPACE, UNICODE_SPACE, REGULAR_SPACE .. UNICODE_SPACE },
	["2-3-3-3"] = { REGULAR_SPACE .. UNICODE_SPACE, UNICODE_SPACE, UNICODE_SPACE },
	["3-2-3-2"] = { UNICODE_SPACE .. REGULAR_SPACE, REGULAR_SPACE .. UNICODE_SPACE, UNICODE_SPACE },
	["3-3-3-2"] = { UNICODE_SPACE, UNICODE_SPACE, UNICODE_SPACE },
	["2-2-3-3"] = { REGULAR_SPACE .. UNICODE_SPACE .. REGULAR_SPACE, REGULAR_SPACE .. UNICODE_SPACE, UNICODE_SPACE },
	["3-2-3-3"] = { UNICODE_SPACE, UNICODE_SPACE, UNICODE_SPACE },
	["2-3-2-3"] = { REGULAR_SPACE .. UNICODE_SPACE, UNICODE_SPACE .. REGULAR_SPACE, REGULAR_SPACE .. UNICODE_SPACE },
}

-- Default spacing for fallback cases
local DEFAULT_SPACING = { UNICODE_SPACE, UNICODE_SPACE, UNICODE_SPACE }

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Helper for generating repeated unicode spaces
local function uspace(n)
	if n <= 0 then
		return ""
	end
	return string.rep(UNICODE_SPACE, n)
end

-- Probe labels with precise spacing
local PROBE_LABELS = {
	TWO_PROBE = uspace(2) .. "ᴘʀᴏʙᴇ¹" .. uspace(6) .. "ᴘʀᴏʙᴇ²",
	FOUR_PROBE = REGULAR_SPACE
		.. UNICODE_SPACE
		.. REGULAR_SPACE
		.. "ᴘ¹"
		.. REGULAR_SPACE
		.. uspace(3)
		.. REGULAR_SPACE
		.. "ᴘ²"
		.. REGULAR_SPACE
		.. uspace(3)
		.. REGULAR_SPACE
		.. "ᴘ³"
		.. REGULAR_SPACE
		.. uspace(3)
		.. REGULAR_SPACE
		.. "ᴘ⁴",
}

-- Format temperature with appropriate degree symbol
local function format_temperature(temp, is_fahrenheit)
	-- Handle placeholder/disconnected probe case
	if temp == config.CONSTANTS.DISCONNECT_DISPLAY or temp == 0 then
		-- Add a space before "--" for better alignment with numbers
		return is_fahrenheit and UNICODE_SPACE .. config.CONSTANTS.DISCONNECT_DISPLAY .. UNICODE_F
			or UNICODE_SPACE .. config.CONSTANTS.DISCONNECT_DISPLAY .. UNICODE_C
	end

	-- Validate temperature is a number
	if type(temp) ~= "number" then
		temp = tonumber(temp) or 0
		-- If conversion resulted in 0, treat as disconnected
		if temp == 0 then
			-- Add a space before "--" for better alignment with numbers
			return is_fahrenheit and UNICODE_SPACE .. config.CONSTANTS.DISCONNECT_DISPLAY .. UNICODE_F
				or UNICODE_SPACE .. config.CONSTANTS.DISCONNECT_DISPLAY .. UNICODE_C
		end
	end

	-- Apply correct temperature unit symbol
	local unit_symbol = is_fahrenheit and UNICODE_F or UNICODE_C
	return string.format("%d%s", temp, unit_symbol)
end

-- Get digit count for a temperature value
local function get_digit_count(temp)
	if temp == config.CONSTANTS.DISCONNECT_DISPLAY or temp == 0 then
		return 2 -- Special case for disconnected probe
	end
	return #tostring(temp)
end

-- ============================================================================
-- DISPLAY GENERATION FUNCTIONS
-- ============================================================================

--- Generate text display for 2-probe configuration
-- Based on verified SmartThings truth table data
-- @param temp1 Temperature value for probe 1
-- @param temp2 Temperature value for probe 2
-- @param is_fahrenheit Boolean indicating if temperature is in Fahrenheit (true) or Celsius (false)
-- @return Formatted string for display in SmartThings UI
function M.generate_two_probe_text(temp1, temp2, is_fahrenheit)
	-- Format temperature strings
	local temp1_str = format_temperature(temp1, is_fahrenheit)
	local temp2_str = format_temperature(temp2, is_fahrenheit)

	-- Get digit counts for both temperatures
	local temp1_digits = get_digit_count(temp1)
	local temp2_digits = get_digit_count(temp2)

	-- Spacing before first temperature based on first temp digits
	local before_temp1 = (temp1_digits == 2) and (uspace(4) .. REGULAR_SPACE) -- 2-digit case
		or uspace(4) -- 3-digit case

	-- Determine spacing between temperatures based on digit combinations
	local between_temps
	if temp1_digits == 2 and temp2_digits == 2 then
		between_temps = uspace(7) .. REGULAR_SPACE -- 2-digit to 2-digit
	elseif temp1_digits == 2 and temp2_digits == 3 then
		between_temps = uspace(7) .. REGULAR_SPACE -- 2-digit to 3-digit
	elseif temp1_digits == 3 and temp2_digits == 2 then
		between_temps = uspace(7) -- 3-digit to 2-digit
	else -- temp1_digits == 3 and temp2_digits == 3
		between_temps = REGULAR_SPACE .. uspace(6) .. REGULAR_SPACE -- 3-digit to 3-digit
	end

	-- Combine all elements with proper spacing
	return PROBE_LABELS.TWO_PROBE .. before_temp1 .. temp1_str .. between_temps .. temp2_str
end

--- Generate text display for 4-probe configuration
-- Based on verified SmartThings truth table data with all digit combinations
-- @param temp1 Temperature value for probe 1
-- @param temp2 Temperature value for probe 2
-- @param temp3 Temperature value for probe 3
-- @param temp4 Temperature value for probe 4
-- @param is_fahrenheit Boolean indicating if temperature is in Fahrenheit (true) or Celsius (false)
-- @return Formatted string for display in SmartThings UI
function M.generate_four_probe_text(temp1, temp2, temp3, temp4, is_fahrenheit)
	-- Store all temperatures in an array for easier processing
	local temps = { temp1, temp2, temp3, temp4 }

	-- Format all temperature strings
	local temp_strs = {}
	for i, t in ipairs(temps) do
		temp_strs[i] = format_temperature(t, is_fahrenheit)
	end

	-- Temperature line starts with 1x Space + first temp
	local temp_line = REGULAR_SPACE .. temp_strs[1]

	-- Get digit counts for all temperatures
	local digit_counts = {}
	for i, t in ipairs(temps) do
		digit_counts[i] = get_digit_count(t)
	end

	-- Create pattern key for spacing lookup (e.g., "2-3-2-3")
	local pattern = table.concat(digit_counts, "-")

	-- Get spacing pattern for this digit combination
	local separators = FOUR_PROBE_SPACING_PATTERNS[pattern] or DEFAULT_SPACING

	-- Apply the spacing pattern between each temperature
	for i = 2, 4 do
		temp_line = temp_line .. separators[i - 1] .. temp_strs[i]
	end

	-- Combine labels and temperatures with proper spacing
	return PROBE_LABELS.FOUR_PROBE .. temp_line
end

--- Main function for generating probe text display
-- @param probe_temps Array of temperature values for all probes
-- @param is_fahrenheit Boolean indicating if temperature is in Fahrenheit (true) or Celsius (false)
-- @return Formatted string for display in SmartThings UI
--
-- The function automatically determines whether to use 2-probe or 4-probe display
-- based on the following rule:
-- - Use 4-probe display if either probe 3 or probe 4 has any value other than DISCONNECT_DISPLAY
-- - Use 2-probe display if both probe 3 and probe 4 are either DISCONNECT_DISPLAY or nil
function M.generate_probe_text(probe_temps, is_fahrenheit)
	-- Validate inputs
	if type(probe_temps) ~= "table" then
		probe_temps = { 0, 0 }
	end

	-- Ensure boolean value for temperature unit
	is_fahrenheit = (is_fahrenheit == true)

	-- Determine if we should use 4-probe display based on probes 3 and 4
	-- Rule: Use 4-probe display if either probe 3 or probe 4 has any value other than DISCONNECT_DISPLAY or 0
	local use_four_probe = false

	-- Check if probe 3 has a valid value (not DISCONNECT_DISPLAY and not 0)
	if probe_temps[3] ~= nil and probe_temps[3] ~= config.CONSTANTS.DISCONNECT_DISPLAY and probe_temps[3] ~= 0 then
		use_four_probe = true
	end

	-- Check if probe 4 has a valid value (not DISCONNECT_DISPLAY and not 0)
	if probe_temps[4] ~= nil and probe_temps[4] ~= config.CONSTANTS.DISCONNECT_DISPLAY and probe_temps[4] ~= 0 then
		use_four_probe = true
	end

	-- Generate appropriate display based on probe configuration
	if use_four_probe then
		return M.generate_four_probe_text(
			probe_temps[1] or 0,
			probe_temps[2] or 0,
			probe_temps[3] or 0,
			probe_temps[4] or 0,
			is_fahrenheit
		)
	else
		return M.generate_two_probe_text(probe_temps[1] or 0, probe_temps[2] or 0, is_fahrenheit)
	end
end

return M