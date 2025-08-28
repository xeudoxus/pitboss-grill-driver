---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil
-- Shared test helper for unit specs
-- Provides common mock preloads and helpers to keep tests DRY

local M = {}

-- Ensure st.capabilities mock is loaded first, then custom capabilities
package.loaded["st.capabilities"] = package.loaded["st.capabilities"] or require("tests.mocks.st.capabilities")
package.loaded["custom_capabilities"] = package.loaded["custom_capabilities"] or require("custom_capabilities")

-- Provide a small helper to preload a simple network recorder mock
function M.setup_network_recorder(recorder_table)
	-- If running under Python test (recorder_table is a Python-provided table with .sent), use it for isolation
	if
		recorder_table
		and type(recorder_table) == "table"
		and recorder_table.sent
		and type(recorder_table.clear_sent) == "function"
	then
		_G.PYTHON_TEST_RECORDER = recorder_table
		-- Always ensure a global recorder exists for Lua-only tests
		if not _G.GLOBAL_NETWORK_RECORDER then
			_G.GLOBAL_NETWORK_RECORDER = { sent = {} }
			_G.GLOBAL_NETWORK_RECORDER.clear_sent = function()
				for i = #_G.GLOBAL_NETWORK_RECORDER, 1, -1 do
					table.remove(_G.GLOBAL_NETWORK_RECORDER, i)
				end
				for i = #_G.GLOBAL_NETWORK_RECORDER.sent, 1, -1 do
					table.remove(_G.GLOBAL_NETWORK_RECORDER.sent, i)
				end
			end
		end
		package.loaded["network_utils"] = {
			send_command = function(device, cmd, arg, driver)
				if _G.network_should_fail then
					return false
				end
				local entry = { cmd = cmd, arg = arg, device = device }
				-- Always insert into both the Python-provided recorder and the global Lua recorder
				if recorder_table and recorder_table.sent then
					table.insert(recorder_table.sent, entry)
				end
				if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
					table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
				end
				return true
			end,
			validate_ip_address = function(ip)
				if not ip or ip == "" then
					return false, "Invalid IP address"
				end
				local a, b, c, d = ip:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
				if not a then
					return false, "Invalid IP address format"
				end
				a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
				if not a or a < 1 or a > 255 then
					return false, "Invalid IP address segment"
				end
				return true, "Valid IP"
			end,
			call_on_schedule = function(...)
				return true
			end, -- stub for tests
		}
		return recorder_table
	end
	-- Otherwise, use the global recorder for Lua-only tests
	if not _G.GLOBAL_NETWORK_RECORDER then
		_G.GLOBAL_NETWORK_RECORDER = { sent = {} }
		_G.GLOBAL_NETWORK_RECORDER.clear_sent = function()
			for i = #_G.GLOBAL_NETWORK_RECORDER, 1, -1 do
				table.remove(_G.GLOBAL_NETWORK_RECORDER, i)
			end
			for i = #_G.GLOBAL_NETWORK_RECORDER.sent, 1, -1 do
				table.remove(_G.GLOBAL_NETWORK_RECORDER.sent, i)
			end
		end
	end
	recorder_table = _G.GLOBAL_NETWORK_RECORDER
	_G.sent_commands = recorder_table
	package.loaded["network_utils"] = {
		send_command = function(device, cmd, arg, driver)
			if _G.network_should_fail then
				return false
			end
			local entry = { cmd = cmd, arg = arg, device = device }
			if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
				table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
			end
			table.insert(recorder_table, entry)
			return true
		end,
		validate_ip_address = function(ip)
			if not ip or ip == "" then
				return false, "Invalid IP address"
			end
			local a, b, c, d = ip:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
			if not a then
				return false, "Invalid IP address format"
			end
			a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
			if not a or a < 1 or a > 255 then
				return false, "Invalid IP address segment"
			end
			return true, "Valid IP"
		end,
		call_on_schedule = function(...)
			return true
		end, -- stub for tests
	}
	return recorder_table
end

-- Convenience helper to preload device_status_service stub used in many unit tests
function M.setup_device_status_stub()
	package.loaded["device_status_service"] = {
		is_grill_on = function(device)
			if device and device.get_latest_state then
				return device:get_latest_state("Standard_Grill", "st.switch", "switch") == "on"
			end
			return false
		end,
		set_status_message = function(device, message) end,
	}
end

-- Install a recorder for status messages set via `device_status_service.set_status_message`
-- Returns a recorder table with `messages` array and a `clear()` helper.
function M.install_status_message_recorder(recorder_table)
	recorder_table = recorder_table or {}
	recorder_table.messages = recorder_table.messages or {}
	recorder_table.clear = function()
		for k in pairs(recorder_table.messages) do
			recorder_table.messages[k] = nil
		end
	end

	-- Preserve existing is_grill_on if present; otherwise use the default stub
	local existing = package.loaded["device_status_service"] or {}
	local is_on = existing.is_grill_on
		or function(device)
			return device and device.get_latest_state and device:get_latest_state() == "on"
		end

	package.loaded["device_status_service"] = {
		is_grill_on = is_on,
		set_status_message = function(device, message)
			table.insert(recorder_table.messages, { device = device, message = message })
		end,
	}

	return recorder_table
end

-- Small assert helper used by specs
function M.assert_eq(a, b, msg)
	if a ~= b then
		error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2)
	end
end

return M
