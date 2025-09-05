---@diagnostic disable: duplicate-set-field, different-requires, undefined-field
---@diagnostic disable: lowercase-global, undefined-global, need-check-nil
-- Shared test helper for unit specs
-- Provides common mock preloads and helpers to keep tests DRY

local M = {}

-- Ensure st.capabilities mock is loaded first, then custom capabilities
package.loaded["st.capabilities"] = package.loaded["st.capabilities"] or require("tests.mocks.st.capabilities")
package.loaded["custom_capabilities"] = package.loaded["custom_capabilities"] or require("custom_capabilities")

-- Helper function to create a clear_sent function for network recorders
local function create_clear_sent_function(recorder)
	return function()
		for i = #recorder, 1, -1 do
			table.remove(recorder, i)
		end
		for i = #recorder.sent, 1, -1 do
			table.remove(recorder.sent, i)
		end
	end
end

-- Helper function to create a wrapped send_command function
local function create_send_command_wrapper(recorder_table, use_global_recorder, network_utils)
	return function(device, cmd, arg, _driver)
		-- Use the real network_utils.send_command but wrap it for recording
		local net_utils = network_utils or require("network_utils")

		-- Record the command attempt
		local entry = { cmd = cmd, arg = arg, device = device }
		if recorder_table and recorder_table.sent then
			table.insert(recorder_table.sent, entry)
		end
		if use_global_recorder and _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
			table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
		end

		-- Handle test failure flag
		if _G.network_should_fail then
			return false
		end

		-- Call the real function
		return net_utils.send_command(device, cmd, arg)
	end
end

-- Helper function to create network_utils mock with common functions
local function create_network_utils_mock(recorder_table, use_global_recorder)
	local network_utils = require("network_utils")
	return {
		send_command = create_send_command_wrapper(recorder_table, use_global_recorder, network_utils),
		validate_ip_address = function(ip)
			-- Use the real network_utils.validate_ip_address function instead of reimplementing
			return network_utils.validate_ip_address(ip)
		end,
		call_on_schedule = function(_)
			return true
		end, -- stub for tests
	}
end

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
			_G.GLOBAL_NETWORK_RECORDER.clear_sent = create_clear_sent_function(_G.GLOBAL_NETWORK_RECORDER)
		end
		package.loaded["network_utils"] = create_network_utils_mock(recorder_table, true)
		return recorder_table
	end
	-- Otherwise, use the global recorder for Lua-only tests
	if not _G.GLOBAL_NETWORK_RECORDER then
		_G.GLOBAL_NETWORK_RECORDER = { sent = {} }
		_G.GLOBAL_NETWORK_RECORDER.clear_sent = create_clear_sent_function(_G.GLOBAL_NETWORK_RECORDER)
	end
	recorder_table = _G.GLOBAL_NETWORK_RECORDER
	_G.sent_commands = recorder_table
	package.loaded["network_utils"] = create_network_utils_mock(recorder_table, false)
	return recorder_table
end

-- Convenience helper to preload device_status_service stub used in many unit tests
function M.setup_device_status_stub()
	-- Use the real device_status_service instead of mocking
	local device_status_service = require("device_status_service")
	package.loaded["device_status_service"] = device_status_service
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

	-- Load the real device_status_service
	local device_status_service = require("device_status_service")

	-- Wrap the real set_status_message to record messages
	local original_set_status_message = device_status_service.set_status_message
	device_status_service.set_status_message = function(device, message)
		-- Record the message
		table.insert(recorder_table.messages, { device = device, message = message })
		-- Call the original function
		return original_set_status_message(device, message)
	end

	-- Update package.loaded to use our wrapped version
	package.loaded["device_status_service"] = device_status_service

	return recorder_table
end

-- Small assert helper used by specs
function M.assert_eq(a, b, msg)
	if a ~= b then
		error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2)
	end
end

return M
