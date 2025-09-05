--[[
  Pit Boss Grill API - Reverse Engineered Communication Protocol
  Created by: xeudoxus
  Version: 2025.9.4

  Communication layer for time/auth based RPC to Pit Boss WiFi grills.

  Firmware: Logic expects firmware >= 0.5.7 (earlier versions untested;
  version validation occurs during initial status / info retrieval).

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
  No warranty provided. Not affiliated with Pit Boss.
--]]

local json_ok, json = pcall(require, "dkjson")
if not json_ok then
	json = {
		encode = function(_)
			return ""
		end,
		decode = function(_)
			return {}
		end,
	}
end

local cosock_ok, cosock = pcall(require, "cosock")
local socket = cosock_ok and cosock.socket or nil

local bit = require("bit32")
local config = require("config")
local language = config.STATUS_MESSAGES

local pitboss_api = {}

-- Authentication cache to minimize API calls
local auth_cache = {
	password = nil,
	last_uptime = nil,
	psw_hex = nil,
	psw_hex_plus1 = nil,
	timestamp = 0,
}

-- Protocol constants (cryptographic keys stay local to this module)
local PITBOSS_RPC_AUTH_KEY_BASE = { 0x8f, 0x80, 0x19, 0xcf, 0x77, 0x6c, 0xfe, 0xb7 }
local PITBOSS_FILE_DECODE_KEY = { 0xc3, 0x3a, 0x77, 0xf0, 0xda, 0x52, 0x6f, 0x16 }

-- Cryptographic utilities
local function chr_lua(code)
	return string.char(code)
end

local function fromHex(char_code)
	if 48 <= char_code and char_code <= 57 then
		return char_code - 48
	elseif 65 <= char_code and char_code <= 70 then
		return char_code - 55
	elseif 97 <= char_code and char_code <= 102 then
		return char_code - 87
	end
	return 0
end

local function toHex(num)
	local digits = "0123456789ABCDEF"
	local lo = (num % 256) % 16
	local hi = math.floor((num % 256) / 16)
	return digits:sub(hi + 1, hi + 1) .. digits:sub(lo + 1, lo + 1)
end

-- Convert binary string to hex representation
local function toHexStr(raw_str)
	local result = ""
	for i = 1, #raw_str do
		result = result .. toHex(string.byte(raw_str, i))
	end
	return result
end

-- Convert hex string to binary
local function fromHexStr(value)
	local len_val = #value
	if (len_val % 2) ~= 0 then
		value = value .. "0"
		len_val = len_val + 1
	end
	local rawData_str = {}
	for x = 1, len_val, 2 do
		local char_code1 = string.byte(value, x)
		local char_code2 = string.byte(value, x + 1)
		local char_val = (bit.lshift(fromHex(char_code1), 4) + fromHex(char_code2)) % 256
		table.insert(rawData_str, chr_lua(char_val))
	end
	return table.concat(rawData_str)
end

-- Core encryption/decryption function with stateful key evolution
local function codec(data_str, key_list, paddingLen, is_rpc_auth_or_status)
	local key = {}
	for i, v in ipairs(key_list) do
		key[i] = v
	end
	local out_bytes = {}

	-- Add padding if required
	if paddingLen > 0 then
		data_str = chr_lua(0xff) .. data_str
		for _ = 1, paddingLen do
			local rndv = math.floor(math.random() * 256) % 256
			if rndv == 0xff then
				rndv = 0xfe
			end
			data_str = chr_lua(rndv) .. data_str
		end
	end

	-- Process each byte with evolving key
	for i = 1, #data_str do
		local data_byte = string.byte(data_str, i)
		local k_index = ((i - 1) % #key) + 1
		local k = key[k_index]
		local m = bit.bxor(data_byte, k) % 256
		table.insert(out_bytes, chr_lua(m))

		local k2 = (i % #key) + 1

		-- Key evolution logic
		if paddingLen > 0 or is_rpc_auth_or_status then
			-- Key evolves based on XORed output (m)
			key[k2] = (bit.bxor(key[k2], m) + (i - 1)) % 256
		else
			-- Key evolves based on ORIGINAL data byte
			key[k2] = (bit.bxor(key[k2], data_byte) + (i - 1)) % 256
		end
	end

	local out = table.concat(out_bytes)

	-- Remove padding marker
	if paddingLen < 1 then
		for i = 1, #out do
			if string.byte(out, i) == 0xff then
				out = out:sub(i + 1)
				break
			end
		end
	end

	return out
end

-- Time-based codec utilities
local function getCodecTime(uptime_seconds)
	-- Handle very large uptime values that could cause overflow issues
	-- After long sessions, uptime becomes very large and may cause authentication failures
	local safe_uptime = math.max(uptime_seconds - 5, 0)

	-- Clamp to prevent integer overflow in authentication calculations
	-- Use modulo to wrap around large values while maintaining time-based variation
	local max_safe_uptime = 2147483647 -- 2^31 - 1 (max 32-bit signed integer)
	if safe_uptime > max_safe_uptime then
		safe_uptime = safe_uptime % 86400 -- Wrap to 24-hour cycle
	end

	return math.floor(safe_uptime / 10)
end

-- Generate dynamic key from base key and time
local function getCodecKey(key_list, time_val)
	local key = {}
	for i, v in ipairs(key_list) do
		key[i] = v
	end

	local x = {}
	local l = time_val
	while #key > 1 do
		local p = (l % #key) + 1
		local v = table.remove(key, p)
		local band_result = bit.bxor(v, l) % 256
		table.insert(x, band_result)
		l = (l * v + v) % 256
	end
	table.insert(x, key[1])
	return x
end

-- HTTP request helper
local function parse_url(url_string)
	local protocol, path = "http", "/"
	local host = nil -- luacheck: ignore
	local port = 80 -- luacheck: ignore

	local proto_end = url_string:find("://")
	if proto_end then
		protocol = url_string:sub(1, proto_end - 1)
		url_string = url_string:sub(proto_end + 3)
	end

	local path_start = url_string:find("/", 1, true)
	local host_port_segment
	if path_start then
		host_port_segment = url_string:sub(1, path_start - 1)
		path = url_string:sub(path_start)
	else
		host_port_segment = url_string
	end

	local port_start = host_port_segment:find(":", 1, true)
	if port_start then
		host = host_port_segment:sub(1, port_start - 1)
		port = tonumber(host_port_segment:sub(port_start + 1)) or 80
	else
		host = host_port_segment
		port = (protocol == "https" and 443) or 80
	end

	return protocol, host, port, path
end

-- Make HTTP request with timeout
local function make_http_request(url, method, body, headers)
	local _, host, port, path = parse_url(url)
	if not host then
		return nil, "Invalid URL: " .. url
	end

	-- Check if socket is available
	if not socket then
		return nil, "Socket library not available"
	end

	local client = socket.tcp()
	if not client then
		return nil, "Failed to create TCP socket"
	end

	client:settimeout(config.CONSTANTS.REQUEST_TIMEOUT)
	local ok, err = client:connect(host, port)
	if not ok then
		client:close()
		return nil, "Connection failed: " .. (err or "unknown")
	end

	-- Build HTTP request
	local request_lines = {
		string.format("%s %s HTTP/1.1", method or "GET", path),
		string.format("Host: %s", host),
		"User-Agent: SmartThingsEdge",
		"Connection: close",
	}

	if headers then
		for key, value in pairs(headers) do
			table.insert(request_lines, string.format("%s: %s", key, value))
		end
	end

	if body then
		table.insert(request_lines, string.format("Content-Length: %d", #body))
		table.insert(request_lines, "Content-Type: application/json")
	end

	table.insert(request_lines, "")
	if body then
		table.insert(request_lines, body)
	end

	local request = table.concat(request_lines, "\r\n") .. "\r\n"

	local bytes_sent, send_err = client:send(request)
	if not bytes_sent then
		client:close()
		return nil, "Send failed: " .. (send_err or "unknown")
	end

	-- Read response
	local status_code = tonumber(0)
	local response_headers = {}

	local status_line = client:receive("*l")
	if status_line then
		status_code = tonumber(status_line:match("^HTTP/%d%.%d (%d+)"))
	end

	-- Read headers
	while true do
		local line = client:receive("*l")
		if not line or line == "" or line == "\r" then
			break
		end
		local key, value = line:match("([^:]+):%s*(.*)")
		if key and value then
			response_headers[key:lower()] = value
		end
	end

	-- Read body
	local response_body
	local content_length = tonumber(response_headers["content-length"])
	if content_length then
		response_body = client:receive(content_length) or ""
	else
		response_body = client:receive("*a") or ""
	end

	client:close()
	return {
		status = status_code,
		body = response_body,
		headers = response_headers,
	}, nil
end

-- Get device uptime for authentication
local function get_uptime(ip_address)
	local url = string.format("http://%s/rpc/PB.GetTime", ip_address)
	local response, err = make_http_request(url, "POST", "{}")

	if err or not response or response.status ~= 200 then
		return nil, err or "Failed to get uptime"
	end

	local data = json.decode(response.body)
	return data and tonumber(data.time), nil
end

-- Get encrypted device password from config
local function get_device_password(ip_address)
	local url = string.format("http://%s/extconfig.json", ip_address)
	local response, err = make_http_request(url, "GET")

	if err or not response or response.status ~= 200 then
		return nil, err or "Failed to get device config"
	end

	local data = json.decode(response.body)
	if not data or not data.psw then
		return nil, "No password found in config"
	end

	-- Decrypt password using file decode key
	local raw_password = fromHexStr(data.psw)
	local plaintext_password = codec(raw_password, PITBOSS_FILE_DECODE_KEY, 0, false)
	return plaintext_password, nil
end

-- Generate authentication tokens based on current time
local function generate_auth_tokens(uptime, password)
	local current_uptime_integer = getCodecTime(uptime)

	-- Generate primary auth token
	local dynamic_key_x = getCodecKey(PITBOSS_RPC_AUTH_KEY_BASE, current_uptime_integer)
	local raw_password_hash_x = codec(password, dynamic_key_x, 0, true)
	local psw_x_hex = toHexStr(raw_password_hash_x)

	-- Generate backup auth token (time + 1)
	local dynamic_key_x_plus_1 = getCodecKey(PITBOSS_RPC_AUTH_KEY_BASE, current_uptime_integer + 1)
	local raw_password_hash_x_plus_1 = codec(password, dynamic_key_x_plus_1, 0, true)
	local psw_x_plus_1_hex = toHexStr(raw_password_hash_x_plus_1)

	return current_uptime_integer, psw_x_hex, psw_x_plus_1_hex
end

-- Get cached or fresh authentication data
local function get_auth_data(ip_address)
	local current_time = os.time()

	-- Check cache validity with overflow protection
	if auth_cache.password and auth_cache.timestamp > 0 then
		local cache_age = current_time - auth_cache.timestamp

		-- Handle negative time differences (clock issues)
		if cache_age < 0 then
			auth_cache.password = nil
			auth_cache.timestamp = 0
			auth_cache.last_uptime = nil
		elseif cache_age < config.CONSTANTS.AUTH_CACHE_TIMEOUT then
			-- Cache is still valid
			local uptime, err = get_uptime(ip_address)
			if not uptime then
				return nil, nil, nil, err
			end

			-- Only regenerate if time changed significantly
			local uptime_integer = getCodecTime(uptime)
			if auth_cache.last_uptime and math.abs(uptime_integer - auth_cache.last_uptime) < 2 then
				return uptime_integer, auth_cache.psw_hex, auth_cache.psw_hex_plus1, nil
			end

			local time_int, psw_hex, psw_hex_plus1 = generate_auth_tokens(uptime, auth_cache.password)
			auth_cache.last_uptime = time_int
			auth_cache.psw_hex = psw_hex
			auth_cache.psw_hex_plus1 = psw_hex_plus1

			return time_int, psw_hex, psw_hex_plus1, nil
		end
	end

	-- Cache miss - get fresh data
	local password, err = get_device_password(ip_address)
	if not password then
		return nil, nil, nil, err
	end

	local uptime, err2 = get_uptime(ip_address)
	if not uptime then
		return nil, nil, nil, err2
	end

	local time_int, psw_hex, psw_hex_plus1 = generate_auth_tokens(uptime, password)

	-- Update cache
	auth_cache.password = password
	auth_cache.last_uptime = time_int
	auth_cache.psw_hex = psw_hex
	auth_cache.psw_hex_plus1 = psw_hex_plus1
	auth_cache.timestamp = current_time

	return time_int, psw_hex, psw_hex_plus1, nil
end

-- Parse hex status data into byte array
local function decode_status_string(hex_status_str)
	local byte_data = {}
	for i = 1, #hex_status_str, 2 do
		local hex_byte = hex_status_str:sub(i, i + 1)
		local byte_val = tonumber(hex_byte, 16)
		if byte_val then
			table.insert(byte_data, byte_val)
		end
	end
	return byte_data
end

-- Convert 3-byte temperature reading to meaningful value
local function convert_temperature(byte_array, offset)
	if not byte_array or #byte_array < offset + 2 then
		return language.disconnected
	end

	local hundreds = byte_array[offset]
	local tens = byte_array[offset + 1]
	local units = byte_array[offset + 2]

	-- Check for disconnected probe patterns
	if
		(hundreds == 0 and tens == 9 and units == 6)
		or (hundreds == 0 and tens == 0 and units == 0)
		or (hundreds == 255 and tens == 255 and units == 255)
	then
		return language.disconnected
	end

	local temp_val = (hundreds * 100) + (tens * 10) + units
	return temp_val == 960 and language.disconnected or temp_val
end

-- Parse complete grill status from binary data
local function parse_grill_status(sc_11_bytes, sc_12_bytes)
	local status = {}

	-- Parse sc_12 data (temperatures and preferences)
	if sc_12_bytes and #sc_12_bytes >= 27 then
		status.is_fahrenheit = (sc_12_bytes[27] == 1)
		status.p1_target = convert_temperature(sc_12_bytes, 3)
		status.p1_temp = convert_temperature(sc_12_bytes, 6)
		status.p2_temp = convert_temperature(sc_12_bytes, 9)
		status.p3_temp = convert_temperature(sc_12_bytes, 12)
		status.p4_temp = convert_temperature(sc_12_bytes, 15)
		status.set_temp = convert_temperature(sc_12_bytes, 21)
		status.grill_temp = convert_temperature(sc_12_bytes, 24)
	else
		-- Default values when data unavailable
		status.is_fahrenheit = true
		status.p1_target = language.disconnected
		status.p1_temp = language.disconnected
		status.p2_temp = language.disconnected
		status.p3_temp = language.disconnected
		status.p4_temp = language.disconnected
		status.set_temp = language.disconnected
		status.grill_temp = language.disconnected
	end

	-- Parse sc_11 data (system states and errors)
	if sc_11_bytes and #sc_11_bytes >= 24 then
		status.smoker_temp = convert_temperature(sc_11_bytes, 21)
		status.module_on = (sc_11_bytes[25] == 1)

		if #sc_11_bytes >= 34 then
			-- Error flags
			status.error_1 = (sc_11_bytes[26] == 1)
			status.error_2 = (sc_11_bytes[27] == 1)
			status.error_3 = (sc_11_bytes[28] == 1)
			status.high_temp_error = (sc_11_bytes[29] == 1)
			status.fan_error = (sc_11_bytes[30] == 1)
			status.hot_error = (sc_11_bytes[31] == 1)
			status.motor_error = (sc_11_bytes[32] == 1)
			status.no_pellets = (sc_11_bytes[33] == 1)
			status.erl_error = (sc_11_bytes[34] == 1)

			if #sc_11_bytes >= 39 then
				-- Component states
				status.fan_state = (sc_11_bytes[35] == 1)
				status.hot_state = (sc_11_bytes[36] == 1)
				status.motor_state = (sc_11_bytes[37] == 1)
				status.light_state = (sc_11_bytes[38] == 1)
				status.prime_state = (sc_11_bytes[39] == 1)
			end
		end

		-- Recipe information (if available)
		if #sc_11_bytes >= 41 then
			status.recipe_step = sc_11_bytes[41]
		end
		if #sc_11_bytes >= 44 then
			local hours = sc_11_bytes[42]
			local minutes = sc_11_bytes[43]
			local seconds = sc_11_bytes[44]
			status.recipe_time = string.format("%02d:%02d:%02d", hours, minutes, seconds)
		end
	else
		-- Default system states
		status.smoker_temp = language.disconnected
		status.module_on = false
		status.error_1 = false
		status.error_2 = false
		status.error_3 = false
		status.high_temp_error = false
		status.fan_error = false
		status.hot_error = false
		status.motor_error = false
		status.no_pellets = false
		status.erl_error = false
		status.fan_state = false
		status.hot_state = false
		status.motor_state = false
		status.light_state = false
		status.prime_state = false
	end

	return status
end

-- Helper: POST with authentication retry using primary and alternate password
local function post_with_auth(url, initial_payload, time_int_val, psw_hex2)
	local response, err = make_http_request(url, "POST", initial_payload)
	if err or not response then
		return nil, err or "Request failed"
	end

	if response.status ~= 200 then
		local payload2 = json.encode({ time = time_int_val, psw = psw_hex2 })
		response, err = make_http_request(url, "POST", payload2)
		if err or not response or response.status ~= 200 then
			return nil, "Authentication failed with both passwords"
		end
	end

	return response, nil
end

--[[
  Public API: Get complete grill status

  Retrieves the current status of the Pit Boss grill including temperatures,
  power state, errors, and component states.

  Parameters:
    ip_address (string): The IP address of the grill

  Returns:
    status (table): Complete grill status containing:
      - grill_temp: Current grill temperature (°F)
      - probe_temp: Meat probe temperature (°F) or "Disconnected"
      - set_temp: Target temperature (°F)
      - power_on: Boolean indicating if grill is powered on
      - Various error flags and component states
    error (string): Error message if operation failed, nil on success
    
  Example:
    local status, err = pitboss_api.get_status("192.168.1.100")
    if status then
      print("Grill temp: " .. status.grill_temp .. "°F")
      print("Target temp: " .. status.set_temp .. "°F")
    end
--]]
function pitboss_api.get_status(ip_address)
	local time_int, psw_hex, psw_hex_plus1, auth_err = get_auth_data(ip_address)
	if auth_err then
		return nil, "Authentication setup failed: " .. auth_err
	end

	local url = string.format("http://%s/rpc/PB.GetState", ip_address)
	local payload = json.encode({ time = time_int, psw = psw_hex })

	local response, err = post_with_auth(url, payload, time_int, psw_hex_plus1)
	if err or not response then
		return nil, err
	end

	local data = json.decode(response.body)
	if not data or not data.sc_11 or not data.sc_12 then
		return nil, "Invalid response format"
	end

	local sc_11_bytes = decode_status_string(data.sc_11)
	local sc_12_bytes = decode_status_string(data.sc_12)

	return parse_grill_status(sc_11_bytes, sc_12_bytes), nil
end

--[[
  Public API: Send raw hex command to grill
  
  Sends a raw hexadecimal command directly to the grill's microcontroller.
  This is a low-level function for advanced control operations.

  Parameters:
    ip_address (string): The IP address of the grill
    hex_command (string): Raw hex command string (e.g., "FE0101FF")

  Returns:
    success (boolean): True if command was sent successfully
    error (string): Error message if operation failed, nil on success

  Example:
    local success, err = pitboss_api.send_command("192.168.1.100", "FE0101FF")
    if success then
      print("Command sent successfully")
    end
--]]
function pitboss_api.send_command(ip_address, hex_command)
	local time_int, psw_hex, psw_hex_plus1, auth_err = get_auth_data(ip_address)
	if auth_err then
		return false, "Authentication setup failed: " .. auth_err
	end
	local url = string.format("http://%s/rpc/PB.SendMCUCommand", ip_address)
	local payload = json.encode({
		time = time_int,
		psw = psw_hex,
		command = hex_command,
	})

	local response, err = post_with_auth(url, payload, time_int, psw_hex_plus1)
	if err or not response then
		return false, err
	end

	return true, nil
end

--[[
  Convenience function: Set grill temperature
  
  Sets the target temperature for the grill. The grill will automatically
  adjust pellet feed and fan speed to maintain this temperature.
  
  Parameters:
    ip_address (string): The IP address of the grill
    temperature (number): Target temperature in Fahrenheit (typically 160-500°F)
    
  Returns:
    success (boolean): True if temperature was set successfully
    error (string): Error message if operation failed, nil on success
    
  Example:
    local success, err = pitboss_api.set_temperature("192.168.1.100", 225)
    if success then
      print("Temperature set to 225°F")
    end
--]]
function pitboss_api.set_temperature(ip_address, temperature)
	-- Validate temperature against config limits
	if
		not (
			type(temperature) == "number"
			and temperature >= config.CONSTANTS.MIN_TEMP_F
			and temperature <= config.CONSTANTS.MAX_TEMP_F
		)
	then
		return false, "Invalid temperature"
	end

	local hundreds = math.floor(temperature / 100)
	local tens = math.floor((temperature % 100) / 10)
	local units = temperature % 10
	local temp_hex = string.format("%02X%02X%02X", hundreds, tens, units)
	local command = string.format("FE0501%sFF", temp_hex)

	return pitboss_api.send_command(ip_address, command)
end

--[[
  Convenience function: Control grill light
  
  Turns the grill's internal light on or off for visibility when cooking
  in low-light conditions.
  
  Parameters:
    ip_address (string): The IP address of the grill
    state (string|boolean): "on"/true to turn light on, "off"/false to turn off
    
  Returns:
    success (boolean): True if light state was changed successfully
    error (string): Error message if operation failed, nil on success
    
  Example:
    local success, err = pitboss_api.set_light("192.168.1.100", "on")
    if success then
      print("Grill light turned on")
    end
--]]
function pitboss_api.set_light(ip_address, state)
	local command = (state == "on" or state == true) and "FE0201FF" or "FE0200FF"
	return pitboss_api.send_command(ip_address, command)
end

--[[
  Convenience function: Control grill prime on/off
  
  Controls the pellet priming system of the grill to ensure proper pellet feed.
  Prime control is only available when the grill is powered on.
  
  Parameters:
    ip_address (string): The IP address of the grill
    state (string|boolean): "on"/true to start priming, "off"/false to stop priming
    
  Returns:
    success (boolean): True if prime state was changed successfully
    error (string): Error message if operation failed, nil on success
    
  Example:
    local success, err = pitboss_api.set_prime("192.168.1.100", "on")
    if success then
      print("Grill priming started")
    end
--]]
function pitboss_api.set_prime(ip_address, state)
	local command = (state == "on" or state == true) and "FE0801FF" or "FE0800FF"
	return pitboss_api.send_command(ip_address, command)
end

--[[
  Convenience function: Power grill off
  
  Controls the main power state of the grill. When powered on, the grill
  will begin its startup sequence and heating process.
  
  Parameters:
    ip_address (string): The IP address of the grill
    state (string|boolean): "off"/false to power off
    
  Returns:
    success (boolean): True if power state was changed successfully
    error (string): Error message if operation failed, nil on success
    
  Example:
    local success, err = pitboss_api.set_power("192.168.1.100", "off")
    if success then
      print("Grill powered off")
    end
--]]
function pitboss_api.set_power(ip_address, state)
	local command = (state == "on" or state == true) and "FE0101FF" or "FE0102FF"
	return pitboss_api.send_command(ip_address, command)
end

--[[
  Convenience function: Set temperature unit
  
  Changes the temperature display unit on the grill between Fahrenheit
  and Celsius. This affects the grill's display and status reporting.
  
  Parameters:
    ip_address (string): The IP address of the grill
    unit (string): "celsius" for Celsius, "fahrenheit" for Fahrenheit
    
  Returns:
    success (boolean): True if unit was changed successfully
    error (string): Error message if operation failed, nil on success
    
  Example:
    local success, err = pitboss_api.set_unit("192.168.1.100", "celsius")
    if success then
      print("Temperature unit set to Celsius")
    end
--]]
function pitboss_api.set_unit(ip_address, unit)
	local command = (unit == "celsius") and "FE0902FF" or "FE0901FF"
	return pitboss_api.send_command(ip_address, command)
end

--[[
  Public API: Get system info (no authentication required)
  
  Retrieves basic system information from the grill's WiFi module.
  This function does not require authentication and can be used for
  connectivity testing and device identification.
  
  Parameters:
    ip_address (string): The IP address of the grill
    
  Returns:
    info (table): System information containing device details
    error (string): Error message if operation failed, nil on success
    
  Example:
    local info, err = pitboss_api.get_system_info("192.168.1.100")
    if info then
      print("Device ID: " .. (info.id or "unknown"))
      print("Uptime: " .. (info.uptime or "unknown"))
    end
--]]
function pitboss_api.get_system_info(ip_address)
	local url = string.format("http://%s/rpc/Sys.GetInfo", ip_address)
	local response, err = make_http_request(url, "POST", "{}")

	if err or not response or response.status ~= 200 then
		return nil, err or "Failed to get system info"
	end

	return json.decode(response.body), nil
end

--[[
  Public API: Get firmware version
  
  Retrieves the firmware version from the Pit Boss grill without authentication.
  This is a lightweight call that can be used for compatibility checking.
  
  Parameters:
    ip_address (string): IP address of the grill
    
  Returns:
    string, nil: Firmware version data on success
    nil, string: Error message on failure
    
  Example:
    local fw_version, err = pitboss_api.get_firmware_version("192.168.1.100")
    if fw_version then
      print("Firmware version: " .. fw_version)
    end
--]]
function pitboss_api.get_firmware_version(ip_address)
	local url = string.format("http://%s/rpc/PB.GetFirmwareVersion", ip_address)
	local response, err = make_http_request(url, "POST", "{}")

	if err or not response or response.status ~= 200 then
		return nil, err or "Failed to get firmware version"
	end

	return json.decode(response.body).firmwareVersion, nil
end

--[[
  Public API: Validate firmware version
  
  Checks if the provided firmware version meets the minimum supported version.
  Uses semantic versioning comparison (x.y.z format).
  
  Parameters:
    firmware_version (string): Firmware version to validate (e.g., "0.5.7")
    
  Returns:
    boolean: True if firmware is valid (>= minimum version), false otherwise
    
  Example:
    local is_valid = pitboss_api.is_firmware_valid("0.5.8")
    if is_valid then
      print("Firmware is supported")
    end
--]]
function pitboss_api.is_firmware_valid(firmware_version)
	if not firmware_version or firmware_version == "" then
		return false
	end

	-- Parse version strings into numeric components
	local function parse_version(version)
		local parts = {}
		for part in version:gmatch("(%d+)") do
			table.insert(parts, tonumber(part))
		end
		-- Ensure at least 3 parts (major.minor.patch)
		while #parts < 3 do
			table.insert(parts, 0)
		end
		return parts
	end

	local current_parts = parse_version(firmware_version)
	local minimum_parts = parse_version(config.CONSTANTS.MINIMUM_FIRMWARE_VERSION)

	-- Compare each component
	for i = 1, math.max(#current_parts, #minimum_parts) do
		local current_part = current_parts[i] or 0
		local minimum_part = minimum_parts[i] or 0

		if current_part > minimum_part then
			return true
		elseif current_part < minimum_part then
			return false
		end
		-- If equal, continue to next component
	end

	-- All components are equal - version meets minimum requirement
	return true
end

--[[
  Public API: Clear authentication cache
  
  Clears the cached authentication data, forcing fresh authentication
  on the next API call. This is useful when the grill's IP address
  changes or when authentication issues occur.
  
  Parameters:
    None
    
  Returns:
    None
    
  Example:
    pitboss_api.clear_auth_cache()
    print("Authentication cache cleared")
--]]
function pitboss_api.clear_auth_cache()
	auth_cache = {
		password = nil,
		last_uptime = nil,
		psw_hex = nil,
		psw_hex_plus1 = nil,
		timestamp = 0,
	}
end

-- Expose pure helper functions for deterministic unit testing
pitboss_api.helpers = {
	toHex = toHex,
	toHexStr = toHexStr,
	fromHexStr = fromHexStr,
	codec = codec,
	getCodecKey = getCodecKey,
	getCodecTime = getCodecTime,
	decode_status_string = decode_status_string,
	parse_grill_status = parse_grill_status,
	FILE_DECODE_KEY = PITBOSS_FILE_DECODE_KEY,
	RPC_AUTH_KEY_BASE = PITBOSS_RPC_AUTH_KEY_BASE,
}

return pitboss_api