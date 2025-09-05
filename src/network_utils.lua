--[[
  Network Utilities for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module provides comprehensive network communication services for Pit Boss grills,
  including intelligent discovery, health monitoring, command transmission, and connection
  management with automatic recovery capabilities.

  Key Features:
  - Efficient network discovery with concurrent scanning
  - Intelligent health checking with minimal overhead
  - Automatic device rediscovery with smart retry logic
  - Robust command sending with failure recovery
  - Optimized IP validation and subnet management
  - Connection state management and caching
  - Concurrent network scanning using cosock threads
  - Cached subnet calculations and IP validation
  - Smart health check intervals based on device state
  - Efficient IP range scanning with early termination

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local cosock = require("cosock") -- ESP32 grills require this specific cosock version
local socket = cosock.socket
local log = require("log")
local json = require("st.json")
local config = require("config")
local pitboss_api = require("pitboss_api")

local network_utils = {}

-- In-memory locks to prevent concurrent rediscovery attempts per device
local _rediscovery_locks = {}

-- ============================================================================
-- IP ADDRESS RESOLUTION AND MANAGEMENT
-- ============================================================================

-- Simple caches for IP management with cleanup
local ip_management_cache = {
	validated_ips = {}, -- ip -> {device_id, timestamp}
	metadata_cache = {}, -- device_id -> parsed metadata
	last_cleanup = 0, -- last cleanup timestamp
}

--- Clean up expired cache entries to prevent memory leaks
local function cleanup_ip_cache()
	local current_time = os.time()

	-- Only cleanup if enough time has passed
	if (current_time - ip_management_cache.last_cleanup) < config.CONSTANTS.IP_CACHE_CLEANUP_INTERVAL then
		return
	end

	-- Clear expired validated IP cache - SAFE iteration
	local cleaned_ips = 0
	local expired_ips = {}

	-- First pass: identify expired entries
	for ip, cache_entry in pairs(ip_management_cache.validated_ips) do
		local cache_age = current_time - cache_entry.timestamp
		if cache_age > (config.CONSTANTS.IP_CACHE_VALIDATION_MINUTES * 60) then
			table.insert(expired_ips, ip)
		end
	end

	-- Second pass: safely remove expired entries
	for _, ip in ipairs(expired_ips) do
		ip_management_cache.validated_ips[ip] = nil
		cleaned_ips = cleaned_ips + 1
	end

	-- Limit metadata cache size
	local metadata_count = 0
	for _ in pairs(ip_management_cache.metadata_cache) do
		metadata_count = metadata_count + 1
	end

	if metadata_count > config.CONSTANTS.IP_METADATA_CACHE_SIZE then
		ip_management_cache.metadata_cache = {}
		log.debug("Cleared device metadata cache due to size limit")
	end

	ip_management_cache.last_cleanup = current_time
	if cleaned_ips > 0 then
		log.debug(string.format("IP cache cleanup completed: %d expired entries removed", cleaned_ips))
	end
end

--- Creates a deterministic string hash from a table for change detection
-- Generates consistent "key=value|key=value" format, sorted by key
-- @param tbl table The table to hash
-- @return string Hash string or "invalid_table" if not a table
function network_utils.hash(tbl)
	if not tbl or type(tbl) ~= "table" then
		return "invalid_table"
	end

	local parts = {}
	local keys = {}

	-- Get all keys
	for k in pairs(tbl) do
		if type(k) == "string" or type(k) == "number" then
			table.insert(keys, tostring(k))
		end
	end

	-- Sort for consistent ordering
	table.sort(keys)

	-- Build hash string
	for _, k in ipairs(keys) do
		local v = tbl[k]
		local v_type = type(v)
		if v_type == "string" or v_type == "number" or v_type == "boolean" then
			table.insert(parts, k .. "=" .. tostring(v))
		elseif v_type == "table" then
			table.insert(parts, k .. "=table")
		else
			table.insert(parts, k .. "=" .. v_type)
		end
	end

	-- Return pipe-separated hash
	return table.concat(parts, "|")
end

--- Update device IP address with validation and caching
-- @param device SmartThings device object
-- @param new_ip string New IP address
-- @return boolean True if successful
function network_utils.update_device_ip(device, new_ip)
	if not device or not new_ip or new_ip == "" then
		return false
	end

	-- Trigger cache cleanup on IP updates
	cleanup_ip_cache()

	local is_valid, err = network_utils.validate_ip_address(new_ip)
	if not is_valid then
		log.warn(string.format("IP update rejected (%s): %s", new_ip, err or "invalid"))
		return false
	end

	local current = device:get_field("ip_address")
	if current == new_ip then
		log.debug(string.format("IP unchanged for %s (%s)", device.id or "device", new_ip))
		return true
	end

	device:set_field("ip_address", new_ip, { persist = true })
	device:set_field("ip_last_updated", os.time(), { persist = true })
	ip_management_cache.validated_ips[new_ip] = { device_id = device.id, timestamp = os.time() }
	log.info(string.format("Device %s IP updated to %s (was %s)", device.id or "device", new_ip, current or "nil"))

	-- If old IP and new IP are different, trigger a health check
	if current and current ~= new_ip then
		log.info(
			string.format("Triggering health check due to IP change: %s -> %s", tostring(current), tostring(new_ip))
		)
		network_utils.health_check(device)
	end
	return true
end

--- Resolve device IP from multiple prioritized sources with validation
-- @param device SmartThings device object
-- @param retest boolean Optional revalidation via network test
-- @return string|nil Valid IP address or nil
function network_utils.resolve_device_ip(device, retest)
	if not device then
		return nil
	end

	-- Trigger cache cleanup on resolution attempts
	cleanup_ip_cache()

	-- 1. User preferences (non-default)
	local prefs = device.preferences or {}
	local pref_ip = prefs.ipAddress or prefs["ipAddress"]

	if pref_ip == nil or pref_ip == "" then
		-- Preference is explicitly unset/blank - continue to other resolution methods
		log.debug("IP preference is unset or blank - using other resolution methods")
	elseif pref_ip ~= config.CONSTANTS.DEFAULT_IP_ADDRESS and pref_ip ~= config.CONSTANTS.DEBUG_IP_ADDRESS then
		-- Preference explicitly set, not default/debug
		log.debug(string.format("Preference IP set and not default: using only %s", pref_ip))
		local valid, msg = network_utils.validate_ip_address(pref_ip)
		if valid then
			device:set_field("ip_address", pref_ip, { persist = true })
			return pref_ip
		else
			log.warn(string.format("Preference IP is set but invalid: %s (%s)", pref_ip, msg or "invalid"))
			return nil
		end
	end

	-- 2. Stored field
	local candidates = {}
	local stored = device:get_field("ip_address")
	if stored then
		table.insert(candidates, { ip = stored, source = "Stored", priority = 2 })
	end

	-- 3. Temporary IP
	if device.temp_ip then
		table.insert(candidates, { ip = device.temp_ip, source = "Temp", priority = 3 })
	end

	-- 4. Device metadata (with caching)
	if device.metadata and device.metadata ~= "" then
		local meta = ip_management_cache.metadata_cache[device.id]
		if not meta then
			local ok, decoded = pcall(json.decode, device.metadata)
			if ok and decoded then
				meta = decoded
				ip_management_cache.metadata_cache[device.id] = decoded
			end
		end
		if meta and meta.ip then
			table.insert(candidates, { ip = meta.ip, source = "Metadata", priority = 4 })
		end
	end

	-- 5. Vendor label
	if device.vendor_provided_label and device.vendor_provided_label ~= "" then
		local vendor_ip = device.vendor_provided_label:match("Pit Boss Grill at (%d+%.%d+%.%d+%.%d+)")
		if vendor_ip then
			table.insert(candidates, { ip = vendor_ip, source = "Vendor Label", priority = 5 })
		end
	end

	table.sort(candidates, function(a, b)
		return a.priority < b.priority
	end)

	-- Remove duplicates and system IPs
	local seen_ips = {}
	local filtered_candidates = {}
	for _, candidate in ipairs(candidates) do
		-- Skip system IPs that should not be validated
		if
			candidate.ip ~= config.CONSTANTS.DEFAULT_IP_ADDRESS
			and candidate.ip ~= config.CONSTANTS.DEBUG_IP_ADDRESS
			and not seen_ips[candidate.ip]
		then
			seen_ips[candidate.ip] = true
			table.insert(filtered_candidates, candidate)
		else
			if seen_ips[candidate.ip] then
				log.debug(string.format("Skipping duplicate IP candidate %s from %s", candidate.ip, candidate.source))
			else
				log.debug(string.format("Skipping system IP candidate %s from %s", candidate.ip, candidate.source))
			end
		end
	end
	candidates = filtered_candidates

	if #candidates == 0 then
		return nil
	end
	log.debug(string.format("Found %d unique IP candidates for validation (device: %s)", #candidates, device.id))

	-- Test candidates with caching and early termination
	for i, c in ipairs(candidates) do
		local valid, msg = network_utils.validate_ip_address(c.ip)
		if not valid then
			log.debug(string.format("Skipping invalid candidate %s (%s): %s", c.ip, c.source, msg or "invalid"))
		else
			-- Check cache first to avoid redundant network calls
			local cache = ip_management_cache.validated_ips[c.ip]
			local cache_ok = cache
				and cache.device_id == device.id
				and (os.time() - cache.timestamp) < (config.CONSTANTS.IP_CACHE_VALIDATION_MINUTES * 60)
			if cache_ok and not retest then
				log.debug(string.format("Using cached validation for IP from %s: %s", c.source, c.ip))
				device:set_field("ip_address", c.ip, { persist = true })
				return c.ip
			end

			-- Network validation with progress logging
			if retest or not cache_ok then
				log.debug(string.format("Validating IP candidate %d/%d from %s: %s", i, #candidates, c.source, c.ip))
				local grill_info = network_utils.test_grill_at_ip(c.ip, nil)
				if grill_info then
					log.info(string.format("Successfully validated IP from %s: %s", c.source, c.ip))
					ip_management_cache.validated_ips[c.ip] = { device_id = device.id, timestamp = os.time() }
					device:set_field("ip_address", c.ip, { persist = true })
					return c.ip
				else
					log.debug(string.format("Validation failed for %s (%s)", c.ip, c.source))
				end
			end
		end
	end

	log.warn(
		string.format("No valid IP address found for device %s after testing %d candidates", device.id, #candidates)
	)
	return nil
end

-- ============================================================================
-- DEVICE DISCOVERY UTILITIES
-- ============================================================================

--- Find existing device by network ID
-- @param driver any SmartThings driver
-- @param network_id string
-- @return any|nil
function network_utils.find_device_by_network_id(driver, network_id)
	if not driver or type(driver.get_devices) ~= "function" then
		return nil
	end
	if not network_id or network_id == "" then
		return nil
	end
	for _, dev in ipairs(driver:get_devices()) do
		local dev_network_id = dev.network_id or dev.device_network_id or dev:get_field("device_network_id")
		if dev_network_id == network_id then
			return dev
		end
	end
	return nil
end

--- Build device creation profile for discovered grill
-- @param grill_data table
-- @return table
function network_utils.build_device_profile(grill_data)
	if not grill_data or not grill_data.id or not grill_data.ip then
		return nil
	end
	local metadata = {
		ip = grill_data.ip,
		mac = grill_data.mac or "unknown",
		name = grill_data.name or "Pit Boss Grill",
		discovery_time = os.time(),
		firmware_version = grill_data.firmware_version or grill_data.fw or "unknown",
		hardware_version = grill_data.hw or "unknown",
	}
	return {
		type = "LAN",
		device_network_id = grill_data.id,
		label = string.format("Pit Boss Grill (%s)", grill_data.id:sub(-6)),
		profile = config.CONSTANTS.DEVICE_PROFILE_NAME,
		manufacturer = "Pit Boss",
		model = grill_data.model or "WiFi Grill",
		vendor_provided_label = string.format("Pit Boss Grill at %s", grill_data.ip),
		metadata = json.encode(metadata),
	}
end

-- ============================================================================
-- IP ADDRESS VALIDATION
-- ============================================================================

--- Validate IP address format and range
-- @param ip string IP address to validate
-- @return boolean, string True if valid, otherwise false and error message
function network_utils.validate_ip_address(ip)
	log.debug("Validating IP address: " .. tostring(ip))

	if not ip or ip == "" then
		log.debug("IP validation failed: IP address is empty")
		return false, "IP address cannot be empty"
	end

	if ip == config.CONSTANTS.DEBUG_IP_ADDRESS then
		return true
	end

	-- Check for valid IPv4 format
	local pattern = "^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$"
	local a, b, c, d = ip:match(pattern)

	if not a then
		log.debug("IP validation failed: Invalid format - " .. tostring(ip))
		return false, "Invalid IP address format. Must be xxx.xxx.xxx.xxx"
	end

	-- Convert to numbers and validate ranges (stricter validation: 1-254 for all octets)
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)

	if a < 1 or a > 254 or b < 1 or b > 254 or c < 1 or c > 254 or d < 1 or d > 254 then
		log.debug(
			string.format("IP validation failed: Invalid segment ranges (must be 1-254) - %d.%d.%d.%d", a, b, c, d)
		)
		return false, "IP address segments must be between 1-254"
	end

	log.debug("IP validation passed: " .. ip)
	return true, nil
end

--- Check if IP triggers rediscovery behavior
-- @param ip string IP address to check
-- @return boolean True if IP should trigger rediscovery
function network_utils.is_rediscovery_ip(ip)
	return ip == config.CONSTANTS.DEFAULT_IP_ADDRESS or ip == config.CONSTANTS.DEBUG_IP_ADDRESS or ip == "" or ip == nil
end

-- ============================================================================
-- CACHE AND CONFIGURATION
-- ============================================================================

-- Cache for network operations to improve performance
local network_cache = {
	subnet_cache = {}, -- Cached subnet calculations
	last_hub_ip = nil, -- Last known hub IP address
	hub_ip_timestamp = nil, -- When hub IP was cached
	connection_pool = {}, -- Reusable connection pool
}

--- Check if device should attempt network rediscovery based on user preferences
-- @param device SmartThings device object
-- @return boolean True if rediscovery should be attempted
function network_utils.should_attempt_rediscovery(device)
	-- Check if auto-rediscovery is enabled in preferences
	local auto_rediscovery = device.preferences and device.preferences.autoRediscovery
	if not auto_rediscovery then
		log.debug("Auto-rediscovery disabled in preferences, skipping network scan")
		return false
	end

	-- Check if IP preference is set to default (indicating auto-discovery mode)
	local ip_preference = device.preferences and device.preferences.ipAddress

	if ip_preference and not network_utils.is_rediscovery_ip(ip_preference) then
		log.debug(string.format("Custom IP address set (%s), skipping network rediscovery", ip_preference))
		return false
	end

	log.debug("Auto-rediscovery enabled and IP is default, allowing network scan")
	return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get current timestamp for cache management
-- @return number Current Unix timestamp
local function get_current_time()
	return os.time()
end

--- Clear expired entries from network cache to prevent memory leaks
-- @return number Number of entries cleaned
function network_utils.cleanup_network_cache()
	local current_time = get_current_time()
	local cleaned_count = 0

	-- Clean subnet cache - SAFE iteration
	local expired_entries = {}

	-- First pass: identify expired entries
	for ip, cache_entry in pairs(network_cache.subnet_cache) do
		if (current_time - cache_entry.timestamp) > config.CONSTANTS.SUBNET_CACHE_TIMEOUT then
			table.insert(expired_entries, ip)
		end
	end

	-- Second pass: safely remove expired entries
	for _, ip in ipairs(expired_entries) do
		network_cache.subnet_cache[ip] = nil
		cleaned_count = cleaned_count + 1
		log.debug(string.format("Cleaned expired subnet cache entry for: %s", ip))
	end

	if cleaned_count > 0 then
		log.info(string.format("Network cache cleanup completed: %d entries removed", cleaned_count))
	end

	return cleaned_count
end

--- Extract subnet prefix from hub IP with caching for performance
-- Caches subnet calculations to avoid repeated string parsing operations
-- @param hub_ipv4 string Hub IP address (e.g., "192.168.1.100")
-- @return string|nil Subnet prefix (e.g., "192.168.1") or nil if parsing fails
function network_utils.get_subnet_prefix(hub_ipv4)
	if not hub_ipv4 or hub_ipv4 == "" then
		log.warn("Invalid hub IP provided for subnet extraction")
		return nil
	end

	-- Check cache first
	local cache_entry = network_cache.subnet_cache[hub_ipv4]
	if cache_entry and (get_current_time() - cache_entry.timestamp) < config.CONSTANTS.SUBNET_CACHE_TIMEOUT then
		log.debug(string.format("Using cached subnet for %s: %s", hub_ipv4, cache_entry.subnet))
		return cache_entry.subnet
	end

	-- Parse subnet from IP address
	local a, b, c = hub_ipv4:match("(%d+)%.(%d+)%.(%d+)%..+")
	if a and b and c then
		local subnet = string.format("%s.%s.%s", a, b, c)

		-- Cache the result
		network_cache.subnet_cache[hub_ipv4] = {
			subnet = subnet,
			timestamp = get_current_time(),
		}

		log.debug(string.format("Parsed and cached subnet for %s: %s", hub_ipv4, subnet))
		return subnet
	else
		log.warn(string.format("Failed to parse subnet from hub IP: %s", hub_ipv4))
		return nil
	end
end

--- Find hub IP address with intelligent fallback mechanisms
-- Uses multiple methods to determine the hub's IP address with caching for efficiency
-- @param driver SmartThings driver object
-- @return string|nil Hub IP address or nil if detection fails
function network_utils.find_hub_ip(driver)
	-- Method 1: Use driver environment info (most reliable)
	if driver and driver.environment_info and driver.environment_info.hub_ipv4 then
		local hub_ip = driver.environment_info.hub_ipv4
		network_cache.last_hub_ip = hub_ip
		network_cache.hub_ip_timestamp = get_current_time()
		log.debug(string.format("Hub IP from driver environment: %s", hub_ip))
		return hub_ip
	end

	-- Method 2: Use cached value if recent (max 5 minutes)
	local cache_age = network_cache.hub_ip_timestamp and (get_current_time() - network_cache.hub_ip_timestamp) or 9999
	if network_cache.last_hub_ip and cache_age < 300 then
		log.debug(string.format("Using cached hub IP: %s (age: %ds)", network_cache.last_hub_ip, cache_age))
		return network_cache.last_hub_ip
	elseif network_cache.last_hub_ip then
		log.debug(string.format("Hub IP cache expired (age: %ds), refreshing", cache_age))
	end

	-- Method 3: Fallback using UDP socket method
	log.debug("Attempting hub IP detection via UDP socket method")
	local success, result = pcall(function()
		local s = socket:udp()
		if not s then
			return nil
		end

		-- Connect to a non-routable address to determine local interface
		local ok = s:setpeername("192.168.0.0", 0)
		if not ok then
			s:close()
			return nil
		end

		local localip, _, _ = s:getsockname()
		s:close()
		return localip
	end)

	if success and result then
		network_cache.last_hub_ip = result
		network_cache.hub_ip_timestamp = get_current_time()
		log.info(string.format("Hub IP detected via socket method: %s", result))
		return result
	else
		log.error("Failed to determine hub IP address using all available methods")
		return nil
	end
end

-- ============================================================================
-- HEALTH MONITORING AND DEVICE VALIDATION
-- ============================================================================

--- Perform lightweight health check using system info call
-- Uses the fastest available API call to verify device connectivity without authentication
-- @param device SmartThings device object
-- @return boolean True if device is reachable and responding
function network_utils.health_check(device)
	-- Resolve IP via centralized service (preference > stored > temp > metadata > vendor label)
	local ip = network_utils.resolve_device_ip(device, false)

	-- Skip fallback to system IPs for health checks - they should never be tested
	if not ip or ip == "" then
		log.warn("Health check aborted: no resolvable IP")
		return false
	end

	-- Don't health check system IPs - they're placeholders, not real devices
	if ip == config.CONSTANTS.DEFAULT_IP_ADDRESS or ip == config.CONSTANTS.DEBUG_IP_ADDRESS then
		log.debug(string.format("Skipping health check for system IP: %s", ip))
		return false -- trigger rediscovery logic
	end

	log.debug(string.format("Performing health check for device at: %s", ip))

	local start_time = get_current_time()
	local sys_info, err = pitboss_api.get_system_info(ip)
	local elapsed_time = get_current_time() - start_time

	if sys_info then
		log.debug(string.format("Health check successful for %s (response time: %ds)", ip, elapsed_time))
		-- Store additional device info if available
		if sys_info.id then
			device:set_field("device_network_id", sys_info.id, { persist = true })
		end

		-- Track successful health check timestamp for temperature sensor grace period
		device:set_field("last_successful_health_check", os.time(), { persist = true })

		return true
	else
		log.warn(string.format("Health check failed for %s after %ds: %s", ip, elapsed_time, err or "unknown error"))
		return false
	end
end

--- Test if IP address hosts a Pit Boss grill with optional ID matching
-- Performs system info query to identify Pit Boss devices and optionally validates device ID
-- @param ip string IP address to test
-- @param device_network_id_to_match string|nil Optional device ID to match for validation
-- @return table|nil Grill system information if found and matched, nil otherwise
function network_utils.test_grill_at_ip(ip, device_network_id_to_match)
	if not ip or ip == "" then
		log.warn("Invalid IP address provided for grill testing")
		return nil
	end

	log.debug(string.format("Testing for Pit Boss grill at: %s", ip))

	-- Query system information with comprehensive error handling
	local start_time = get_current_time()
	local sys_info, err

	-- Wrap the API call in pcall for additional safety
	local success, result = pcall(function()
		return pitboss_api.get_system_info(ip)
	end)

	if success then
		sys_info, err = result, nil
	else
		sys_info, err = nil, result or "API call failed"
	end

	local elapsed_time = get_current_time() - start_time

	-- Check if response indicates a Pit Boss grill
	if sys_info and type(sys_info) == "table" and sys_info.app == config.CONSTANTS.PITBOSS_APP_IDENTIFIER then
		-- Get firmware version for logging and validation
		local firmware_version, fw_err = pitboss_api.get_firmware_version(ip)
		local firmware_valid = false

		if firmware_version then
			firmware_valid = pitboss_api.is_firmware_valid(firmware_version)
			log.info(
				string.format("Grill firmware Version: %s (valid: %s)", firmware_version, tostring(firmware_valid))
			)
		else
			log.warn(string.format("Could not retrieve firmware version from %s: %s", ip, fw_err or "unknown error"))
		end

		-- If specific device ID matching is required
		if device_network_id_to_match then
			if sys_info.id == device_network_id_to_match then
				log.info(
					string.format(
						"Grill FOUND and MATCHED at IP: %s (ID: %s, FW: %s, response time: %ds)",
						ip,
						sys_info.id,
						firmware_version,
						elapsed_time
					)
				)
				sys_info.ip = ip
				sys_info.firmware_version = firmware_version
				sys_info.firmware_valid = firmware_valid
				return sys_info
			else
				log.debug(
					string.format(
						"Grill found at %s but ID %s does not match expected ID %s",
						ip,
						sys_info.id or "unknown",
						device_network_id_to_match
					)
				)
				return nil
			end
		else
			-- No ID matching required, return any Pit Boss grill found
			log.info(
				string.format(
					"Grill DISCOVERED at IP: %s (ID: %s, FW: %s, response time: %ds)",
					ip,
					sys_info.id or "unknown",
					firmware_version,
					elapsed_time
				)
			)
			sys_info.ip = ip
			sys_info.firmware_version = firmware_version
			sys_info.firmware_valid = firmware_valid
			return sys_info
		end
	else
		-- Not a Pit Boss grill or connection failed
		if err then
			log.debug(string.format("No grill at %s after %ds: %s", ip, elapsed_time, err))
		else
			log.debug(string.format("Device at %s is not a Pit Boss grill (response time: %ds)", ip, elapsed_time))
		end
	end

	return nil
end

-- ============================================================================
-- NETWORK DISCOVERY AND SCANNING
-- ============================================================================

--- Scan IP range for Pit Boss grills using efficient concurrent threads
-- Performs parallel network scanning with thread management and callback processing
-- @param driver SmartThings driver object
-- @param subnet string Network subnet prefix (e.g., "192.168.1")
-- @param start_ip number Starting IP address in range (e.g., 10)
-- @param end_ip number Ending IP address in range (e.g., 250)
-- @param callback function Callback function to process discovered grills
function network_utils.scan_for_grills(driver, subnet, start_ip, end_ip, callback)
	if not subnet or subnet == "" then
		log.error("No subnet provided for grill scan")
		return
	end

	if not callback or type(callback) ~= "function" then
		log.error("No valid callback function provided for grill scan")
		return
	end

	start_ip = tonumber(start_ip) or config.CONSTANTS.DEFAULT_SCAN_START_IP
	end_ip = tonumber(end_ip) or config.CONSTANTS.DEFAULT_SCAN_END_IP

	if start_ip > end_ip or start_ip < 1 or end_ip > 254 then
		log.error(string.format("Invalid IP range: %d to %d", start_ip, end_ip))
		return
	end

	-- Balanced approach: limited concurrency with robust error handling
	local max_concurrent = config.CONSTANTS.MAX_CONCURRENT_CONNECTIONS
	local running = 0
	local queue = {}
	local completed = 0
	local found_grills = 0
	local total_ips = end_ip - start_ip + 1
	local scan_cancelled = false

	local function run_next()
		if #queue == 0 or scan_cancelled then
			-- Don't check completion here - thread can't reliably detect if it's the last one
			return
		end
		if running >= max_concurrent then
			return
		end

		running = running + 1
		local ip = table.remove(queue, 1)

		cosock.spawn(function()
			if scan_cancelled then
				running = running - 1
				return
			end

			-- Wrap each scan in multiple layers of protection
			local success, grill_data = pcall(function()
				return network_utils.test_grill_at_ip(ip)
			end)

			completed = completed + 1

			if success and grill_data then
				found_grills = found_grills + 1
				-- Found a grill, call the callback
				local cb_success, err = pcall(callback, grill_data, driver)
				if not cb_success then
					log.error(string.format("Callback failed for grill at %s: %s", ip, err or "unknown error"))
				else
					log.info(string.format("Successfully processed grill at %s (%d found so far)", ip, found_grills))
				end

				-- Cancel remaining scans after finding first grill to speed up discovery (if SCAN_CONTINUE is false)
				if not config.CONSTANTS.SCAN_CONTINUE then
					scan_cancelled = true
					queue = {}
				end
			elseif not success then
				-- Log scan errors at debug level to avoid spam
				log.debug(string.format("Scan error for %s: %s", ip, grill_data or "unknown error"))
			end

			running = running - 1

			-- Continue with next scan immediately (no artificial delay)
			run_next()
		end, "grill-scan-" .. ip:gsub("%.", "-"))
	end

	-- Prepare queue of IPs
	for i = start_ip, end_ip do
		local ip = string.format("%s.%d", subnet, i)
		table.insert(queue, ip)
	end

	log.info(
		string.format(
			"Starting balanced grill scan with max %d concurrent connections: %s.%d to %s.%d (%d total)",
			max_concurrent,
			subnet,
			start_ip,
			subnet,
			end_ip,
			total_ips
		)
	)

	-- Start initial batch
	for _ = 1, math.min(max_concurrent, #queue) do
		run_next()
	end
end

-- ============================================================================
-- DEVICE REDISCOVERY AND CONNECTION RECOVERY
-- ============================================================================

--- Rediscover device IP address when health check fails
-- Performs targeted network scan to locate device that has changed IP address
-- @param device SmartThings device object
-- @param driver SmartThings driver object
-- @param bypass_flood_protection boolean Optional flag to bypass flood protection
-- @return boolean True if device was successfully rediscovered
function network_utils.rediscover_device(device, driver, bypass_flood_protection)
	-- Flood protection: Prevent multiple concurrent scans
	local scan_in_progress = device:get_field("rediscovery_in_progress") or false
	local scan_start_time = device:get_field("rediscovery_start_time") or 0
	local current_time = get_current_time()

	-- Skip flood protection if bypass flag is set (for preference changes)
	if not bypass_flood_protection then
		-- CHECK REDISCOVERY_COOLDOWN - Short term flood protection (3x refresh interval)
		local rediscovery_cooldown = config.get_refresh_interval(device) * 3
		local last_rediscovery_attempt = device:get_field("last_rediscovery_attempt") or 0
		local time_since_last_attempt = current_time - last_rediscovery_attempt

		if time_since_last_attempt < rediscovery_cooldown then
			local remaining_cooldown = rediscovery_cooldown - time_since_last_attempt
			log.info(
				string.format(
					"Rediscovery blocked by cooldown (3x refresh interval) - %ds remaining until next allowed attempt",
					remaining_cooldown
				)
			)
			return false
		end

		-- CHECK PERIODIC REDISCOVERY INTERVAL - Long term flood protection (24 hours)
		-- First check if device has gone offline recently and we should wait 24 hours
		local first_offline_time = device:get_field("first_offline_time") or 0
		local last_rediscovery_time = device:get_field("last_successful_rediscovery") or 0

		-- If device just went offline, set the first offline timestamp
		if first_offline_time == 0 then
			device:set_field("first_offline_time", current_time, { persist = true })
			first_offline_time = current_time
			log.info("Device first went offline - starting 24-hour wait period before allowing rediscovery")
		end

		-- Check if 24 hours have passed since device first went offline
		local time_since_first_offline = current_time - first_offline_time
		if time_since_first_offline < config.CONSTANTS.PERIODIC_REDISCOVERY_INTERVAL then
			local remaining_time = config.CONSTANTS.PERIODIC_REDISCOVERY_INTERVAL - time_since_first_offline
			log.info(
				string.format(
					"Rediscovery blocked by PERIODIC_REDISCOVERY_INTERVAL - %ds remaining since device first went offline",
					remaining_time
				)
			)
			return false
		end

		-- If we had a successful rediscovery recently, also check that interval
		local time_since_last_rediscovery = current_time - last_rediscovery_time
		if
			last_rediscovery_time > 0
			and time_since_last_rediscovery < config.CONSTANTS.PERIODIC_REDISCOVERY_INTERVAL
		then
			local remaining_time = config.CONSTANTS.PERIODIC_REDISCOVERY_INTERVAL - time_since_last_rediscovery
			log.info(
				string.format(
					"Rediscovery blocked by PERIODIC_REDISCOVERY_INTERVAL - %ds remaining since last successful rediscovery",
					remaining_time
				)
			)
			return false
		end
	else
		log.info("Bypassing flood protection for preference-triggered rediscovery")
	end

	-- Zombie thread detection: If scan has been "in progress" for too long, force reset
	if scan_in_progress and (current_time - scan_start_time) > 300 then -- 5 minutes max
		log.warn(
			string.format(
				"Detected stale rediscovery flag (running for %ds) - force resetting",
				current_time - scan_start_time
			)
		)
		device:set_field("rediscovery_in_progress", false, { persist = true })
		device:set_field("rediscovery_start_time", nil, { persist = true })
		scan_in_progress = false
	end

	if scan_in_progress then
		local elapsed = current_time - scan_start_time
		log.info(
			string.format(
				"Rediscovery already in progress (%ds elapsed) - ignoring request to prevent flooding",
				elapsed
			)
		)
		return false
	end

	log.info(string.format("Starting IP rediscovery for device: %s", device.id))

	-- Track rediscovery attempt for REDISCOVERY_COOLDOWN enforcement
	device:set_field("last_rediscovery_attempt", current_time, { persist = true })

	-- Mark scan as in progress (flood protection flag)
	device:set_field("rediscovery_in_progress", true, { persist = true })
	device:set_field("rediscovery_start_time", current_time, { persist = true })

	-- Function to ensure flags are always cleared
	local function cleanup_and_return(result)
		device:set_field("rediscovery_in_progress", false, { persist = true })
		device:set_field("rediscovery_start_time", nil, { persist = true })

		-- Track successful rediscovery for PERIODIC_REDISCOVERY_INTERVAL enforcement
		if result then
			device:set_field("last_successful_rediscovery", current_time, { persist = true })
			device:set_field("first_offline_time", nil, { persist = true }) -- Clear offline timer on success
			log.info(
				string.format("Successful rediscovery timestamp saved and offline timer cleared: %d", current_time)
			)
		end

		return result
	end

	-- Determine network subnet for scanning
	local hub_ipv4 = network_utils.find_hub_ip(driver)
	if not hub_ipv4 then
		log.error("Cannot determine hub IP for rediscovery")
		return cleanup_and_return(false)
	end

	local subnet = network_utils.get_subnet_prefix(hub_ipv4)
	if not subnet then
		log.error("Cannot determine subnet for rediscovery")
		return cleanup_and_return(false)
	end

	-- Get device network ID for targeted matching
	local device_network_id = device.network_id or device.device_network_id or device:get_field("device_network_id")
	if not device_network_id then
		log.warn("No device network ID available for targeted rediscovery, scanning for any Pit Boss grill")
	end

	log.info(string.format("Scanning subnet %s for device %s", subnet, device_network_id or "unknown"))

	local rediscovery_start_time = get_current_time()

	-- Proper flood protection with thread-safe cleanup
	local found_device = false
	local max_concurrent = config.CONSTANTS.MAX_CONCURRENT_CONNECTIONS
	local running = 0
	local queue = {}
	local completed = 0
	local scan_cancelled = false
	local cleanup_called = false

	-- Build IP queue with resume capability
	local start_ip = config.CONSTANTS.DEFAULT_SCAN_START_IP
	local end_ip = config.CONSTANTS.DEFAULT_SCAN_END_IP

	-- Check for saved scan position from previous interrupted scan
	local saved_scan_position = device:get_field("last_scan_position")
	if saved_scan_position then
		local last_ip_num = tonumber(saved_scan_position:match("%.(%d+)$"))
		if last_ip_num and last_ip_num >= start_ip and last_ip_num < end_ip then
			-- Resume from where we left off (next IP after the last scanned one)
			start_ip = last_ip_num + 1
			log.info(
				string.format(
					"Resuming IP scan from %s.%d (previous scan reached %s)",
					subnet,
					start_ip,
					saved_scan_position
				)
			)
		else
			-- Invalid saved position, start from beginning
			device:set_field("last_scan_position", nil, { persist = true })
			log.info("Invalid saved scan position, starting from beginning")
		end
	else
		log.info(string.format("Starting fresh IP scan from %s.%d", subnet, start_ip))
	end

	-- Build the IP queue
	for i = start_ip, end_ip do
		table.insert(queue, string.format("%s.%d", subnet, i))
	end

	local total_ips = #queue
	log.info(
		string.format(
			"Starting rediscovery scan: %d IPs with max %d concurrent connections (range: %s.%d to %s.%d)",
			total_ips,
			max_concurrent,
			subnet,
			start_ip,
			subnet,
			end_ip
		)
	)

	-- Thread-safe cleanup function that can only be called once
	local function safe_cleanup_and_return(result, reason)
		if cleanup_called then
			return result
		end
		cleanup_called = true

		-- Cancel any remaining scans immediately
		scan_cancelled = true

		local elapsed = get_current_time() - rediscovery_start_time
		log.info(
			string.format(
				"Rediscovery completed: %s (%s, %d/%d IPs, %ds)",
				tostring(result),
				reason,
				completed,
				total_ips,
				elapsed
			)
		)

		return cleanup_and_return(result)
	end

	local function run_next()
		-- Double-check cancellation at entry
		if scan_cancelled or found_device or cleanup_called then
			return
		end

		if #queue == 0 then
			-- Queue is empty - check completion in main thread, not here
			return
		end

		if running >= max_concurrent then
			return
		end

		running = running + 1
		local ip = table.remove(queue, 1)

		cosock.spawn(function()
			-- Check cancellation at thread start
			if scan_cancelled or found_device or cleanup_called then
				running = running - 1
				return
			end

			local success, grill_data = pcall(function()
				return network_utils.test_grill_at_ip(ip, device_network_id)
			end)

			completed = completed + 1
			running = running - 1

			-- Check if we found the device
			if success and grill_data and not found_device and not cleanup_called then
				local is_target_device = true
				if device_network_id and grill_data.id and grill_data.id ~= device_network_id then
					is_target_device = false
					log.debug(
						string.format(
							"Found grill at %s but ID mismatch: %s != %s",
							ip,
							grill_data.id,
							device_network_id
						)
					)
				end

				if is_target_device then
					found_device = true

					-- Update device IP immediately
					network_utils.update_device_ip(device, ip)
					pitboss_api.clear_auth_cache()
					device:set_field("last_rediscovery_success", get_current_time(), { persist = true })
					-- Clear saved scan position on successful discovery
					device:set_field("last_scan_position", nil, { persist = true })

					-- Cleanup and return success
					safe_cleanup_and_return(true, "device_found")
					return
				end
			end

			-- Progress logging
			if completed % 20 == 0 then
				log.debug(string.format("Rediscovery progress: %d/%d IPs scanned", completed, total_ips))
			end

			-- Continue scanning only if not cancelled
			if not scan_cancelled and not found_device and not cleanup_called then
				run_next()
			end

			-- Don't check for scan completion here - thread can't reliably check if it's the last one
		end, "rediscover-" .. ip:gsub("%.", "-"))
	end

	-- Start initial concurrent scans
	for _ = 1, math.min(max_concurrent, #queue) do
		run_next()
	end

	-- Wait for actual completion with proper termination detection
	local timeout = config.CONSTANTS.REDISCOVERY_TIMEOUT
	local wait_start = get_current_time()

	-- Wait until found device, cleanup called, timeout, OR natural completion (no threads + empty queue)
	while not found_device and not cleanup_called and (get_current_time() - wait_start) < timeout do
		cosock.socket.sleep(0.1)

		-- Check for natural completion: no threads running AND queue is empty
		if running == 0 and #queue == 0 and not found_device and not cleanup_called then
			break -- Scan completed naturally
		end
	end

	-- Handle completion - force cleanup if not already done
	if not cleanup_called then
		if found_device then
			-- Clear saved scan position on successful discovery
			device:set_field("last_scan_position", nil, { persist = true })
			return safe_cleanup_and_return(true, "success_before_timeout")
		elseif running == 0 and #queue == 0 then
			-- Natural completion - all IPs scanned, no device found
			-- Clear saved scan position since we completed the full scan
			device:set_field("last_scan_position", nil, { persist = true })
			device:set_field("last_rediscovery_failure", get_current_time(), { persist = true })
			return safe_cleanup_and_return(false, "scan_completed_no_device")
		else
			-- Timeout occurred - save current position for resume
			if #queue > 0 then
				local last_scanned_ip = queue[1] -- The next IP that would have been scanned
				local last_ip_num = tonumber(last_scanned_ip:match("%.(%d+)$"))
				if last_ip_num then
					local actual_last_scanned = string.format("%s.%d", subnet, last_ip_num - 1)
					device:set_field("last_scan_position", actual_last_scanned, { persist = true })
					log.info(string.format("Scan timed out, saving position: %s", actual_last_scanned))
				end
			end
			scan_cancelled = true
			device:set_field("last_rediscovery_failure", get_current_time(), { persist = true })

			-- Wait a brief moment for threads to notice cancellation
			local force_wait = 0
			while running > 0 and force_wait < 20 do -- Max 2 seconds
				cosock.socket.sleep(0.1)
				force_wait = force_wait + 1
			end

			return safe_cleanup_and_return(false, "timeout_reached")
		end
	end

	-- Fallback - should never reach here due to safe_cleanup_and_return calls above
	return cleanup_and_return(found_device)
end

-- ============================================================================
-- COMMAND TRANSMISSION AND COMMUNICATION
-- ============================================================================

--- Send command to device with automatic recovery and retry logic
-- Handles command transmission with health checking, rediscovery, and retry mechanisms
-- @param device SmartThings device object
-- @param command string Command type to execute
-- @param args any Command arguments (varies by command type)
-- @return boolean True if command was sent successfully
function network_utils.send_command(device, command, args)
	local ip = network_utils.resolve_device_ip(device, false)
	if not ip or ip == "" then
		log.error(string.format("No valid IP address available for command '%s' (device: %s)", command, device.id))
		return false
	end

	log.info(string.format("Sending command '%s' to device at: %s", command, ip))

	-- Pre-flight health check
	if not network_utils.health_check(device) then
		log.warn("Device health check failed before command")
		network_utils.mark_device_offline(device)
		return false
	end

	-- Command execution with retry logic
	local success, err
	local retry_count = 0

	repeat
		-- Execute command based on type
		if command == "set_temperature" and args then
			success, err = pitboss_api.set_temperature(ip, args)
		elseif command == "set_light" and args then
			success, err = pitboss_api.set_light(ip, args)
		elseif command == "set_prime" and args then
			success, err = pitboss_api.set_prime(ip, args)
		elseif command == "set_power" and args then
			success, err = pitboss_api.set_power(ip, args)
		elseif command == "set_unit" and args then
			success, err = pitboss_api.set_unit(ip, args)
		elseif command == "custom_hex" and args then
			success, err = pitboss_api.send_command(ip, args)
		else
			log.error(string.format("Unknown command type: %s", command))
			return false
		end

		-- Handle command result
		if success then
			log.info(
				string.format(
					"Command '%s' sent successfully%s",
					command,
					retry_count > 0 and string.format(" (after %d retries)", retry_count) or ""
				)
			)
			return true
		else
			retry_count = retry_count + 1
			log.warn(
				string.format(
					"Command '%s' failed (attempt %d/%d): %s",
					command,
					retry_count,
					config.CONSTANTS.COMMAND_RETRY_COUNT + 1,
					err or "unknown error"
				)
			)

			-- Brief delay before retry
			if retry_count <= config.CONSTANTS.COMMAND_RETRY_COUNT then
				cosock.socket.sleep(1)
			end
		end
	until retry_count > config.CONSTANTS.COMMAND_RETRY_COUNT

	log.error(string.format("Command '%s' failed after %d attempts", command, retry_count))
	return false
end

-- Get device status with automatic rediscovery on failure
function network_utils.get_status(device, driver)
	local ip = device:get_field("ip_address")
	if not ip then
		log.error("No IP address for get_status")
		-- If in auto-discovery mode, attempt rediscovery
		local auto_rediscovery = device.preferences and device.preferences.autoRediscovery
		local ip_pref = device.preferences and device.preferences.ipAddress
		if
			auto_rediscovery
			and (
				not ip_pref
				or ip_pref == config.CONSTANTS.DEFAULT_IP_ADDRESS
				or ip_pref == config.CONSTANTS.DEBUG_IP_ADDRESS
			)
		then
			log.info("Attempting rediscovery because device is in auto-discovery mode and has no IP")
			network_utils.attempt_rediscovery(device, driver, "get_status_no_ip", true)
		end

		network_utils.mark_device_offline(device)
		return nil
	end

	log.debug("Getting status from device at: " .. ip)

	if not network_utils.health_check(device) then
		log.warn("Device health check failed during get_status")
		network_utils.mark_device_offline(device)
		return nil
	end

	-- Get status using Pit Boss API
	local status, err = pitboss_api.get_status(ip)

	if status then
		log.debug("Status retrieved successfully")
		-- Clear any previous error on successful status retrieval
		device:set_field("last_network_error", nil)
		return status
	else
		log.error("Failed to get status: " .. (err or "unknown error"))
		-- Store the error for the health monitor to analyze
		device:set_field("last_network_error", err or "unknown error")
		return nil
	end
end

-- ============================================================================
-- MODULE CLEANUP AND EXPORT
-- ============================================================================

--- Perform final cleanup of network resources
-- Called when module is being unloaded or system is shutting down
local function cleanup_module()
	-- Clear all caches
	network_cache.subnet_cache = {}
	network_cache.last_cleanup = 0

	log.debug("Network utils module cleanup completed")
end

-- Register cleanup function for graceful shutdown
if not _G.cleanup_handlers then
	_G.cleanup_handlers = {}
end
table.insert(_G.cleanup_handlers, cleanup_module)

--- Schedule periodic network cache cleanup
-- @param device SmartThings device object with thread for scheduling
-- @param interval_minutes Optional interval in minutes (default: 30)
function network_utils.schedule_cache_cleanup(device, interval_minutes)
	if not device or not device.thread then
		log.warn("Cannot schedule network cache cleanup: device or thread not available")
		return false
	end

	interval_minutes = interval_minutes or 30 -- Default to 30 minutes

	device.thread:call_on_schedule(60 * interval_minutes, function()
		network_utils.cleanup_network_cache()
		return true -- Keep the schedule active
	end, "network_cache_cleanup")

	log.info(string.format("Scheduled network cache cleanup every %d minutes", interval_minutes))
	return true
end

-- ============================================================================
-- DEVICE STATE MANAGEMENT
-- ============================================================================

--- Mark device as online and clear offline tracking
-- @param device SmartThings device object
function network_utils.mark_device_online(device)
	if not device then
		return
	end

	device:online()
	device:set_field("first_offline_time", nil, { persist = true })
	device:set_field("is_connected", true, { persist = true }) -- Ensure is_connected field is always set
	log.debug("Device marked online and offline timer cleared")
end

--- Mark device as offline and start offline tracking
-- @param device SmartThings device object
function network_utils.mark_device_offline(device)
	if not device then
		return
	end

	device:offline()
	device:set_field("is_connected", false, { persist = true }) -- Ensure is_connected field is always set
	-- Set offline time if not already set
	if not device:get_field("first_offline_time") then
		device:set_field("first_offline_time", os.time(), { persist = true })
	end
	log.debug("Device marked offline and offline timer started")
end

-- ============================================================================
-- CENTRALIZED REDISCOVERY MANAGEMENT
-- ============================================================================

--- Centralized rediscovery function to prevent duplicate calls and scan loops
-- @param device table The device to rediscover
-- @param driver table The driver instance
-- @param reason string Optional reason for rediscovery (for logging)
-- @param bypass_flood_protection boolean Optional flag to bypass flood protection (for preference changes)
-- @return boolean True if rediscovery was successful
function network_utils.attempt_rediscovery(device, driver, reason, bypass_flood_protection)
	if not device or not driver then
		log.error("attempt_rediscovery called with nil device or driver")
		return false
	end
	log.info(
		string.format(
			"Rediscovery requested for device %s (reason: %s, bypass: %s)",
			device.id,
			reason or "unknown",
			tostring(bypass_flood_protection)
		)
	)

	-- Prevent concurrent rediscovery attempts within the same driver process
	if _rediscovery_locks[device.id] then
		log.info(
			string.format("Rediscovery for device %s blocked by in-memory lock (another scan is running)", device.id)
		)
		return false
	end

	_rediscovery_locks[device.id] = true
	local ok, success = pcall(function()
		return network_utils.rediscover_device(device, driver, bypass_flood_protection)
	end)

	-- Ensure lock is always cleared
	_rediscovery_locks[device.id] = nil

	if not ok then
		log.error(string.format("Rediscovery crashed for device %s: %s", device.id, tostring(success)))
		return false
	end

	-- success holds the boolean returned by rediscover_device

	if success then
		log.info(string.format("Rediscovery successful for device %s", device.id))
	else
		log.info(string.format("Rediscovery failed for device %s", device.id))
	end

	return success
end

return network_utils