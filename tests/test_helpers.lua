---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil
-- Shared test helper for unit specs
-- Provides common mock preloads and helpers to keep tests DRY

local M = {}

-- Ensure st.capabilities mock is loaded first, then custom capabilities
package.loaded["st.capabilities"] = package.loaded["st.capabilities"] or require("tests.mocks.st.capabilities")
package.loaded["custom_capabilities"] = package.loaded["custom_capabilities"] or require("custom_capabilities")

-- Provide a small helper to preload a simple network recorder mock
function M.setup_network_recorder(recorder_table)
  recorder_table = recorder_table or {}
  recorder_table.sent = recorder_table.sent or {}
  recorder_table.clear_sent = function()
    for i = #recorder_table, 1, -1 do table.remove(recorder_table, i) end
    for i = #recorder_table.sent, 1, -1 do table.remove(recorder_table.sent, i) end
  end
  _G.sent_commands = recorder_table
  package.loaded["network_utils"] = {
    send_command = function(device, cmd, arg, driver)
      if _G.network_should_fail then
        return false
      end
      local entry = {cmd = cmd, arg = arg, device = device}
      table.insert(recorder_table.sent, entry)
      table.insert(recorder_table, entry)
      return true
    end
    , validate_ip_address = function(ip)
      if not ip or ip == "" then return false, "Invalid IP address" end
      local a,b,c,d = ip:match('^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$')
      if not a then return false, "Invalid IP address format" end
      a,b,c,d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
      if not a or a < 1 or a > 255 then return false, "Invalid IP address segment" end
      return true, "Valid IP"
    end
  }
  return recorder_table
end

-- Convenience helper to preload device_status_service stub used in many unit tests
function M.setup_device_status_stub()
  package.loaded["device_status_service"] = {
    is_grill_on = function(device) return device and device.get_latest_state and device:get_latest_state() == "on" end,
    set_status_message = function(device, message) end
  }
end

-- Install a recorder for status messages set via `device_status_service.set_status_message`
-- Returns a recorder table with `messages` array and a `clear()` helper.
function M.install_status_message_recorder(recorder_table)
  recorder_table = recorder_table or {}
  recorder_table.messages = recorder_table.messages or {}
  recorder_table.clear = function()
    for k in pairs(recorder_table.messages) do recorder_table.messages[k] = nil end
  end

  -- Preserve existing is_grill_on if present; otherwise use the default stub
  local existing = package.loaded["device_status_service"] or {}
  local is_on = existing.is_grill_on or function(device) return device and device.get_latest_state and device:get_latest_state() == "on" end

  package.loaded["device_status_service"] = {
    is_grill_on = is_on,
    set_status_message = function(device, message)
      table.insert(recorder_table.messages, { device = device, message = message })
    end
  }

  return recorder_table
end

-- Small assert helper used by specs
function M.assert_eq(a,b,msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

return M
