--[[
  Virtual Device Manager for Pit Boss Grill Driver
  Created by: xeudoxus
  Version: 2025.9.4

  This module manages the creation, removal, and state synchronization of virtual devices
  that provide specialized interfaces for different grill components. Virtual devices
  enable integration with other SmartThings automations and provide focused control
  interfaces for specific grill functions.

  Virtual Device Types:
  - Virtual Main Grill: Combined temperature sensor, thermostat, switch, and power meter
  - Virtual Probe 1/2/3/4: Individual temperature sensors for food monitoring
  - Virtual Light: Dedicated light control switch
  - Virtual Prime: Dedicated prime control switch
  - Virtual At-Temp: Indicator switch showing when grill reaches target temperature
  - Virtual Error: Indicator switch showing error/panic states

  Features:
  - Dynamic virtual device creation/removal
  - State synchronization using status-based updates
  - Immediate UI feedback with background refresh scheduling
  - Temperature offset handling and unit conversion
  - Consistent disconnected value emission for virtual devices
  - Power consumption calculation for main virtual device
  - Error state and panic condition monitoring

  License: Apache License 2.0 - see LICENSE file for details
  Disclaimer: Third-party driver not endorsed by Pit Boss or Dansons. Use at your own risk. No warranty provided.
--]]

local log = require("log")
local json = require("st.json")
local capabilities = require("st.capabilities")
local config = require("config")
local network_utils = require("network_utils")
local custom_caps = require("custom_capabilities")
local device_status_service = require("device_status_service")
local temperature_service = require("temperature_service")
local temperature_calibration = require("temperature_calibration")

local virtual_device_manager = {}

-- ============================================================================
-- VIRTUAL DEVICE UTILITIES
-- ============================================================================

--- Get virtual device by parent_assigned_child_key
-- @param driver SmartThings driver object
-- @param key string The parent_assigned_child_key to search for
-- @return device|nil The virtual device if found, nil otherwise
local function get_virtual_device_by_key(driver, key)
	for _, dev in ipairs(driver:get_devices()) do
		if (dev.parent_assigned_child_key or "") == key then
			return dev
		end
	end
	return nil
end

--- Create a virtual device
-- @param driver SmartThings driver object
-- @param parent_device SmartThings device object (main grill device)
-- @param config_entry table Virtual device configuration
local function create_virtual_device(driver, parent_device, config_entry)
	local create_device_msg = {
		type = "EDGE_CHILD",
		label = config_entry.label,
		profile = config_entry.profile,
		manufacturer = "SmartThingsCommunity",
		model = config_entry.model,
		vendor_provided_label = config_entry.label,
		parent_device_id = parent_device.id,
		parent_assigned_child_key = config_entry.key,
	}

	log.info(string.format("📡 Creating %s...", config_entry.label))
	log.debug(string.format("Create device message: %s", json.encode(create_device_msg)))

	local success, err = pcall(function()
		driver:try_create_device(create_device_msg)
	end)

	if not success then
		log.error(string.format("Failed to create virtual device %s: %s", config_entry.label, tostring(err)))
	else
		log.debug(string.format("Successfully called try_create_device for %s", config_entry.label))
	end
end

--- Remove a virtual device
-- @param driver SmartThings driver object
-- @param device_key string The parent_assigned_child_key of device to remove
local function remove_virtual_device(driver, device_key)
	local virtual_device = get_virtual_device_by_key(driver, device_key)
	if virtual_device then
		log.info(string.format("🗑️ Removing virtual device: %s", virtual_device.label))
		driver:try_delete_device(virtual_device.id)
	end
end

--- Update temperature ranges for virtual device components
-- @param device SmartThings device object (virtual device)
-- @param unit string Current temperature unit
local function update_virtual_device_temperature_ranges(device, unit)
	local temp_range = config.get_temperature_range(unit)
	local range_event = { value = { minimum = temp_range.min, maximum = temp_range.max }, unit = unit }

	-- Update temperature range for main component
	device:emit_event(capabilities.temperatureMeasurement.temperatureRange(range_event))
end

-- Helper to compute virtual device temperature with fallbacks and offsets
local function compute_virtual_temperature(parent_device, raw_temp, cache_key, offset, unit)
	local temp_value
	if temperature_service.is_valid_temperature(raw_temp, unit) then
		-- Apply Steinhart-Hart calibration instead of simple offset
		temp_value = temperature_calibration.apply_calibration(raw_temp, offset, unit, cache_key)
	else
		-- Use parent device when checking cached values to avoid nil device usage
		local cached_temp = temperature_service.get_cached_temperature_value(parent_device, cache_key, nil)
		if cached_temp and cached_temp ~= 0 then
			temp_value = cached_temp
		else
			-- No valid reading and no usable cache
			temp_value = unit == "F" and 0 or -17.8
		end
	end
	return temp_value
end

--- Check for virtual device preference changes
-- @param old_prefs table Previous preferences (can be nil)
-- @param current_prefs table Current preferences (can be nil)
-- @return boolean True if any virtual device preferences changed
local function check_virtual_device_preference_changes(old_prefs, current_prefs)
	-- If current_prefs is nil, no changes can be detected
	if not current_prefs then
		log.debug("Current preferences are nil, no virtual device preference changes detected")
		return false
	end

	for _, config_entry in ipairs(config.VIRTUAL_DEVICES) do
		local old_value = old_prefs and old_prefs[config_entry.preference]
		local new_value = current_prefs[config_entry.preference]

		if old_value ~= new_value then
			log.info(
				string.format(
					"Virtual device preference changed: %s = %s",
					config_entry.preference,
					tostring(new_value)
				)
			)
			return true
		end
	end
	return false
end

--- Manage virtual device creation/removal without status update
-- @param driver SmartThings driver object
-- @param parent_device SmartThings device object (main grill device)
local function manage_virtual_devices_without_status_update(driver, parent_device)
	log.debug("Managing virtual devices (no status update)...")

	-- Check if preferences are available
	if not parent_device.preferences then
		log.warn("Device preferences not available, skipping virtual device management")
		return
	end

	for _, config_entry in ipairs(config.VIRTUAL_DEVICES) do
		local should_exist = parent_device.preferences[config_entry.preference] == true
		local virtual_device = get_virtual_device_by_key(driver, config_entry.key)
		local exists = virtual_device ~= nil

		log.debug(
			string.format(
				"Virtual device '%s': should_exist=%s, exists=%s, preference_value=%s",
				config_entry.key,
				tostring(should_exist),
				tostring(exists),
				tostring(parent_device.preferences[config_entry.preference])
			)
		)

		if should_exist and not exists then
			-- Create virtual device
			log.info(string.format("Creating virtual device: %s", config_entry.label))
			create_virtual_device(driver, parent_device, config_entry)
		elseif not should_exist and exists then
			-- Remove virtual device
			log.info(string.format("Removing virtual device: %s", config_entry.label))
			remove_virtual_device(driver, config_entry.key)
		elseif should_exist and exists then
			-- Device exists and should exist - mark it online
			log.debug(string.format("Virtual device exists and should exist: %s", config_entry.label))
			if virtual_device then
				virtual_device:online()
			end
		end
	end

	log.debug("Virtual device management completed (no status update needed)")
end

--- Manage all virtual devices based on user preferences with status update
-- @param driver SmartThings driver object
-- @param parent_device SmartThings device object (main grill device)
local function manage_virtual_devices_with_status_update(driver, parent_device)
	log.debug("Managing virtual devices with status update...")

	-- Check if preferences are available
	if not parent_device.preferences then
		log.warn("Device preferences not available, skipping virtual device management")
		return
	end

	local any_virtual_devices_exist = false

	for _, config_entry in ipairs(config.VIRTUAL_DEVICES) do
		local should_exist = parent_device.preferences[config_entry.preference] == true
		local virtual_device = get_virtual_device_by_key(driver, config_entry.key)
		local exists = virtual_device ~= nil

		log.debug(
			string.format(
				"Virtual device '%s': should_exist=%s, exists=%s, preference_value=%s",
				config_entry.key,
				tostring(should_exist),
				tostring(exists),
				tostring(parent_device.preferences[config_entry.preference])
			)
		)

		if should_exist and not exists then
			-- Create virtual device
			log.info(string.format("Creating virtual device: %s", config_entry.label))
			create_virtual_device(driver, parent_device, config_entry)
			any_virtual_devices_exist = true
		elseif not should_exist and exists then
			-- Remove virtual device
			log.info(string.format("Removing virtual device: %s", config_entry.label))
			remove_virtual_device(driver, config_entry.key)
		elseif should_exist and exists then
			-- Device exists and should exist - mark it online
			log.debug(string.format("Virtual device exists and should exist: %s", config_entry.label))
			if virtual_device then
				virtual_device:online()
			end
			any_virtual_devices_exist = true
		end
	end

	-- If any virtual devices exist, update them with cached status to avoid redundant health checks
	-- BUT only if they haven't been updated with real status recently
	if any_virtual_devices_exist then
		local last_real_update = parent_device:get_field("last_virtual_device_real_update") or 0
		local current_time = os.time()
		local time_since_real_update = current_time - last_real_update

		-- Only update with cached status if it's been more than 30 seconds since real update
		-- This prevents cached updates from overriding recent real status updates
		if time_since_real_update > 30 then
			log.debug("Updating all virtual devices with cached/default status...")
			-- Don't trigger additional network calls during init - use cached/default status
			virtual_device_manager.update_virtual_devices(parent_device)
			log.debug("All virtual devices set with cached status")
		else
			log.debug(
				string.format(
					"Skipping cached virtual device update - real update was %d seconds ago",
					time_since_real_update
				)
			)
		end
	else
		log.debug("No virtual devices exist - skipping status update")
	end
end

-- ============================================================================
-- PUBLIC INTERFACE
-- ============================================================================

--- Initialize virtual devices during device setup
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param init_success boolean True if main device initialization was successful
function virtual_device_manager.initialize_virtual_devices(driver, device, init_success)
	if init_success then
		-- Virtual devices were already set with fresh status during init,
		-- just manage creation/removal
		manage_virtual_devices_without_status_update(driver, device)
	else
		-- Init failed, do full virtual device management including status update
		manage_virtual_devices_with_status_update(driver, device)
	end
end

--- Handle virtual device preference changes
-- @param driver SmartThings driver object
-- @param device SmartThings device object
-- @param old_prefs table Previous preferences (can be nil)
-- @param current_prefs table Current preferences (can be nil)
function virtual_device_manager.handle_preference_changes(driver, device, old_prefs, current_prefs)
	if type(current_prefs) ~= "table" then
		log.debug("Device preferences are not available, skipping virtual device preference handling")
		return
	end

	-- Get hashes for comparison
	local current_prefs_hash = network_utils.hash(current_prefs)
	local last_processed_hash = device:get_field("last_processed_prefs_virtual")

	-- Determine if this is initial setup
	local is_initial_setup = not last_processed_hash
		and (not old_prefs or (type(old_prefs) == "table" and next(old_prefs) == nil))

	-- Skip if preferences haven't changed (unless initial setup)
	if not is_initial_setup and last_processed_hash == current_prefs_hash then
		log.debug("Virtual device preferences unchanged since last processing, skipping")
		return
	end

	-- Store hash to prevent reprocessing
	device:set_field("last_processed_prefs_virtual", current_prefs_hash, { persist = true })

	-- Check for virtual device preference changes and manage virtual devices
	if check_virtual_device_preference_changes(old_prefs, current_prefs) then
		if not is_initial_setup then
			log.info("Managing virtual devices based on preference changes...")
		else
			log.debug("Setting up initial virtual devices based on preferences...")
		end
		manage_virtual_devices_with_status_update(driver, device)
	end
end

-- This function serves as the single source of truth for virtual device state updates.
-- It builds a lookup map of child devices once to prevent multiple loops over the driver's device list,
-- ensuring efficient updates of all virtual device states based on current grill status.
-- @param device SmartThings device object (main device)
-- @param status table Current grill status data (optional, will use cached/new if not provided)
function virtual_device_manager.update_virtual_devices_from_status(device, status)
	local driver = device.driver
	if not driver then
		return
	end

	-- Track when we last updated virtual devices with real status data
	if status and next(status) then
		device:set_field("last_virtual_device_real_update", os.time(), { persist = true })
		log.debug("Recorded timestamp for real virtual device update")
	end

	-- Optimization: Create a map of existing virtual devices for this parent.
	local virtual_devices = {}
	for _, dev in ipairs(driver:get_devices()) do
		if dev.parent_device_id == device.id and dev.parent_assigned_child_key then
			virtual_devices[dev.parent_assigned_child_key] = dev
		end
	end

	-- If there are no virtual devices to update, exit early.
	if not next(virtual_devices) then
		log.debug("No virtual devices found to update.")
		return
	end

	local current_status = status
	-- Get current grill status if not provided
	if not current_status then
		-- NEVER trigger network calls during virtual device operations - use cached/default state only
		log.info("No status available for virtual device updates. They will reflect cached/default state.")
		-- Create a minimal empty status table to prevent errors below
		current_status = {}
	end

	-- Get temperature unit and offsets
	local unit = current_status.is_fahrenheit and "F" or "C"
	local offsets = {
		grill = device.preferences.grillOffset or 0,
		probe1 = device.preferences.probe1Offset or 0,
		probe2 = device.preferences.probe2Offset or 0,
		probe3 = device.preferences.probe3Offset or 0,
		probe4 = device.preferences.probe4Offset or 0,
	}

	-- Check if grill is currently on
	local grill_on = device_status_service.is_grill_on(device, current_status)

	log.debug(
		string.format(
			"Updating virtual devices: grill_on=%s, grill_temp=%s, unit=%s",
			tostring(grill_on),
			tostring(current_status.grill_temp),
			unit
		)
	)

	-- Update virtual main grill (thermostat & temperature sensor)
	local virtual_main_dev = virtual_devices["virtual-main"]
	if virtual_main_dev and device.preferences.enableVirtualGrillMain then
		-- Logic mirrors update_grill_temperature for consistency
		local temp_value =
			compute_virtual_temperature(device, current_status.grill_temp, "grill_temp", offsets.grill, unit)
		if temp_value then
			local evt = capabilities.temperatureMeasurement.temperature({ value = temp_value, unit = unit })
			virtual_main_dev:emit_event(evt)
			update_virtual_device_temperature_ranges(virtual_main_dev, unit)
		else
			-- Emit disconnected display for main grill when no temp available
			local evt = capabilities.temperatureMeasurement.temperature({
				value = config.CONSTANTS.OFF_DISPLAY_TEMP,
				unit = unit,
			})
			virtual_main_dev:emit_event(evt)
			local evt2 = custom_caps.grillTemp.currentTemp({ value = config.CONSTANTS.DISCONNECT_DISPLAY, unit = unit })
			virtual_main_dev:emit_event(evt2)
		end

		local main_switch_state = grill_on and "on" or "off"
		local estimated_watts = device_status_service.calculate_power_consumption(device, current_status)
		local evt3 = capabilities.switch.switch[main_switch_state]()
		virtual_main_dev:emit_event(evt3)
		local evt4 = capabilities.powerMeter.power({ value = estimated_watts, unit = "W" })
		virtual_main_dev:emit_event(evt4)
		log.debug(
			string.format(
				"Virtual Main Grill: %s, %.1f°%s, %.1fW",
				main_switch_state,
				temp_value or 0,
				unit,
				estimated_watts
			)
		)
	end

	-- Update virtual probe 1 temperature
	local virtual_probe1_dev = virtual_devices["virtual-probe-1"]
	if virtual_probe1_dev and device.preferences.enableVirtualProbe1 then
		-- Logic mirrors update_probe_temperature for consistency
		local temp_value = compute_virtual_temperature(device, current_status.p1_temp, "p1_temp", offsets.probe1, unit)
		if temp_value then
			local evt = capabilities.temperatureMeasurement.temperature({ value = temp_value, unit = unit })
			virtual_probe1_dev:emit_event(evt)
			update_virtual_device_temperature_ranges(virtual_probe1_dev, unit)
		else
			local evt = capabilities.temperatureMeasurement.temperature({
				value = config.CONSTANTS.OFF_DISPLAY_TEMP,
				unit = unit,
			})
			virtual_probe1_dev:emit_event(evt)
		end
		log.debug(string.format("Virtual Grill Probe 1: %.1f°%s", temp_value or 0, unit))
	end

	-- Update virtual probe 2 temperature
	local virtual_probe2_dev = virtual_devices["virtual-probe-2"]
	if virtual_probe2_dev and device.preferences.enableVirtualProbe2 then
		-- Logic mirrors update_probe_temperature for consistency
		local temp_value = compute_virtual_temperature(device, current_status.p2_temp, "p2_temp", offsets.probe2, unit)
		if temp_value then
			local evt = capabilities.temperatureMeasurement.temperature({ value = temp_value, unit = unit })
			virtual_probe2_dev:emit_event(evt)
			update_virtual_device_temperature_ranges(virtual_probe2_dev, unit)
		else
			local evt = capabilities.temperatureMeasurement.temperature({
				value = config.CONSTANTS.OFF_DISPLAY_TEMP,
				unit = unit,
			})
			virtual_probe2_dev:emit_event(evt)
		end
		log.debug(string.format("Virtual Grill Probe 2: %.1f°%s", temp_value or 0, unit))
	end

	-- Update virtual probe 3 temperature
	local virtual_probe3_dev = virtual_devices["virtual-probe-3"]
	if virtual_probe3_dev and device.preferences.enableVirtualProbe3 then
		-- Logic mirrors update_probe_temperature for consistency
		local temp_value = compute_virtual_temperature(device, current_status.p3_temp, "p3_temp", offsets.probe3, unit)
		if temp_value then
			local evt = capabilities.temperatureMeasurement.temperature({ value = temp_value, unit = unit })
			virtual_probe3_dev:emit_event(evt)
			update_virtual_device_temperature_ranges(virtual_probe3_dev, unit)
		else
			local evt = capabilities.temperatureMeasurement.temperature({
				value = config.CONSTANTS.OFF_DISPLAY_TEMP,
				unit = unit,
			})
			virtual_probe3_dev:emit_event(evt)
		end
		log.debug(string.format("Virtual Grill Probe 3: %.1f°%s", temp_value or 0, unit))
	end

	-- Update virtual probe 4 temperature
	local virtual_probe4_dev = virtual_devices["virtual-probe-4"]
	if virtual_probe4_dev and device.preferences.enableVirtualProbe4 then
		-- Logic mirrors update_probe_temperature for consistency
		local temp_value = compute_virtual_temperature(device, current_status.p4_temp, "p4_temp", offsets.probe4, unit)
		if temp_value then
			local evt = capabilities.temperatureMeasurement.temperature({ value = temp_value, unit = unit })
			virtual_probe4_dev:emit_event(evt)
			update_virtual_device_temperature_ranges(virtual_probe4_dev, unit)
		else
			local evt = capabilities.temperatureMeasurement.temperature({
				value = config.CONSTANTS.OFF_DISPLAY_TEMP,
				unit = unit,
			})
			virtual_probe4_dev:emit_event(evt)
		end
		log.debug(string.format("Virtual Grill Probe 4: %.1f°%s", temp_value or 0, unit))
	end

	-- Update virtual light switch
	local virtual_light_dev = virtual_devices["virtual-light"]
	if virtual_light_dev and device.preferences.enableVirtualGrillLight then
		local light_state = current_status.light_state and "on" or "off"
		local evt = capabilities.switch.switch[light_state]()
		virtual_light_dev:emit_event(evt)
		log.debug(string.format("Virtual Grill Light: %s", light_state))
	end

	-- Update virtual prime switch
	local virtual_prime_dev = virtual_devices["virtual-prime"]
	if virtual_prime_dev and device.preferences.enableVirtualGrillPrime then
		local prime_state = (grill_on and current_status.prime_state) and "on" or "off"
		local evt = capabilities.switch.switch[prime_state]()
		virtual_prime_dev:emit_event(evt)
		log.debug(string.format("Virtual Grill Prime: %s", prime_state))
	end

	-- Update virtual at-temp switch (indicator only)
	local virtual_attemp_dev = virtual_devices["virtual-at-temp"]
	if virtual_attemp_dev and device.preferences.enableVirtualAtTemp then
		local at_temp = false
		if
			grill_on
			and temperature_service.is_valid_temperature(current_status.grill_temp, unit)
			and temperature_service.is_valid_temperature(current_status.set_temp, unit)
		then
			local current_temp = current_status.grill_temp + offsets.grill
			local target_temp = current_status.set_temp
			at_temp = current_temp >= (target_temp * 0.95) -- 95% tolerance
		end
		local switch_state = at_temp and "on" or "off"
		local evt = capabilities.switch.switch[switch_state]()
		virtual_attemp_dev:emit_event(evt)
		log.debug(string.format("Virtual Grill At-Temp: %s", switch_state))
	end

	-- Update virtual error switch (indicator only)
	local virtual_error_dev = virtual_devices["virtual-error"]
	if virtual_error_dev and device.preferences.enableVirtualError then
		local has_error = false
		if current_status.errors and type(current_status.errors) == "table" then
			has_error = #current_status.errors > 0
		end
		local panic_state = device:get_field("panic_state") or false
		local error_active = has_error or panic_state

		-- If panic is active, force the virtual error device online so routines can trigger
		if panic_state then
			virtual_error_dev:online()
		end

		-- Emit a switch event ('on'/'off')
		local switch_state = error_active and "on" or "off"
		local evt = capabilities.switch.switch[switch_state]()
		virtual_error_dev:emit_event(evt)
		log.debug(string.format("Virtual Grill Error Switch: %s", switch_state))
	end
end

--- Update all virtual devices with current grill status
-- @param device SmartThings device object (main grill device)
-- @param status table Current grill status (optional)
function virtual_device_manager.update_virtual_devices(device, status)
	-- Use the comprehensive status-based update function
	virtual_device_manager.update_virtual_devices_from_status(device, status)
end

--- Get list of virtual devices for a parent device
-- @param driver SmartThings driver object
-- @param parent_device_id string Parent device ID
-- @return table Array of virtual device objects
function virtual_device_manager.get_virtual_devices_for_parent(driver, parent_device_id)
	local virtual_devices = {}
	for _, dev in ipairs(driver:get_devices()) do
		if dev.parent_device_id == parent_device_id and dev.parent_assigned_child_key then
			table.insert(virtual_devices, dev)
		end
	end
	return virtual_devices
end

--- Check if a device is a virtual device
-- @param device SmartThings device object
-- @return boolean True if device is a virtual device
function virtual_device_manager.is_virtual_device(device)
	return device.parent_assigned_child_key ~= nil
end

--- Manage virtual devices based on preferences (public interface)
-- @param driver SmartThings driver object
-- @param device SmartThings device object (main grill device)
function virtual_device_manager.manage_virtual_devices(driver, device)
	manage_virtual_devices_with_status_update(driver, device)
end

return virtual_device_manager