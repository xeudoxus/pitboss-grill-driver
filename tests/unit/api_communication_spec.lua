---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- API Communication tests based on real grill behavior
package.path = package.path .. ";./tests/mocks/?.lua"

-- Clear the module cache for pitboss_api to ensure a fresh load
package.loaded["pitboss_api"] = nil

local config = require("config")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Mock network dependencies with realistic responses based on example_api.txt
local mock_responses = {}
local receive_call_count = 0
local network_should_fail = false
local connection_attempts = {}

package.loaded["cosock"] = {
  socket = {
    tcp = function()
      receive_call_count = 0
      return {
        settimeout = function(timeout) 
          -- Track timeout settings
        end,
        connect = function(self, ip, port)
          table.insert(connection_attempts, {ip = ip, port = port, time = os.time()})
          if network_should_fail then
            return nil, "Connection failed"
          end
          return true
        end,
        send = function(data) 
          if network_should_fail then
            return nil, "Send failed"
          end
          return #data 
        end,
        receive = function(self, pattern)
          if network_should_fail then
            return nil, "Receive failed"
          end
          
          receive_call_count = receive_call_count + 1
          if pattern == "*l" then
            if receive_call_count == 1 then
              return "HTTP/1.1 200 OK"
            elseif receive_call_count == 2 then
              return "Content-Type: application/json"
            else
              return "" -- End headers
            end
          elseif pattern == "*a" or type(pattern) == "number" then
            return mock_responses.next_response or '{"psw":"F53C2DEBCBE9EE8D21","grillTemp":81,"setTemp":160}'
          end
          return ""
        end,
        close = function() end
      }
    end
  }
}

-- Mock JSON with realistic grill data
package.loaded["dkjson"] = {
  encode = function(obj) 
    if obj.time and obj.psw then
      return '{"time":' .. obj.time .. ',"psw":"' .. obj.psw .. '"}'
    end
    return '{"test":"data"}' 
  end,
  decode = function(json_str) 
    if json_str:find('"psw"') then
      -- Return fully parsed status data for pitboss_api.lua
      return { 
        psw = "F53C2DEBCBE9EE8D21", 
        grillTemp = 81, -- Changed to 81
        setTemp = 160,
        p1Temp = 77,
        p2Temp = 77,
        p3Temp = config.CONSTANTS.DISCONNECT_VALUE,
        p4Temp = config.CONSTANTS.DISCONNECT_VALUE,
        moduleIsOn = false,
        lightState = false,
        primeState = false,
        fanState = false,
        motorState = false,
        isFahrenheit = true,
        error1 = false,
        error2 = false,
        error3 = false,
        highTempError = false,
        fanError = false,
        hotError = false,
        motorError = false,
        noPellets = false,
        erlError = false,
        sc_11 = "FE0B000707000707000706090600090600090600000801020200000000000000000000000000000100000000FF",
        sc_12 = "FE0C00070700070700070709060009060009060001060000080101FF"
      }
    elseif json_str:find('"firmwareVersion"') then
      return { firmwareVersion = "0.5.7"}
    elseif json_str:find('"system"') then
      return { system = "PitBoss", model = "Test", uptime = 37580 }
    elseif json_str:find('"time"') then
      return { time = 37580 }
    end
    return {}
  end
}

-- Now require the actual pitboss_api module
local pitboss_api = require("pitboss_api")

-- Test 1: Get grill status
local status_result, err = pitboss_api.get_status("192.168.1.100")
assert_eq(err, nil, "should not return an error for get_status")
assert_eq(status_result.grill_temp, 81, "should return correct grill temperature")
assert_eq(status_result.set_temp, 160, "should return correct set temperature")
assert_eq(status_result.module_on, false, "should return correct power state")

-- Test 2: Temperature probe readings
assert_eq(status_result.p1_temp, 77, "should return correct probe 1 temperature")
assert_eq(status_result.p2_temp, 77, "should return correct probe 2 temperature")
assert_eq(status_result.p3_temp, config.CONSTANTS.DISCONNECT_VALUE, "should show probe 3 as disconnected")
assert_eq(status_result.p4_temp, config.CONSTANTS.DISCONNECT_VALUE, "should show probe 4 as disconnected")

-- Test 3: Error states
assert_eq(status_result.error_1, false, "should report no error 1")
assert_eq(status_result.fan_error, false, "should report no fan error")
assert_eq(status_result.motor_error, false, "should report no motor error")
assert_eq(status_result.no_pellets, false, "should report pellets available")

-- Test 4: Component states
assert_eq(status_result.fan_state, false, "should report fan running")
assert_eq(status_result.hot_state, false, "should report hot state")
assert_eq(status_result.motor_state, false, "should report motor stopped")
assert_eq(status_result.light_state, false, "should report light off")
assert_eq(status_result.prime_state, false, "should report prime off")

-- Test 5: Power commands
local success, err = pitboss_api.set_power("192.168.1.100", true)
assert_eq(success, true, "should successfully send power on command")
assert_eq(err, nil, "should not return an error for set_power on")

success, err = pitboss_api.set_power("192.168.1.100", false)
assert_eq(success, true, "should successfully send power off command")
assert_eq(err, nil, "should not return an error for set_power off")

-- Test 6: Temperature commands
success, err = pitboss_api.set_temperature("192.168.1.100", 225)
assert_eq(success, true, "should successfully send temperature command")
assert_eq(err, nil, "should not return an error for set_temperature")

-- Test 7: Light commands
success, err = pitboss_api.set_light("192.168.1.100", true)
assert_eq(success, true, "should successfully send light on command")
assert_eq(err, nil, "should not return an error for set_light on")

success, err = pitboss_api.set_light("192.168.1.100", false)
assert_eq(success, true, "should successfully send light off command")
assert_eq(err, nil, "should not return an error for set_light off")

-- Test 8: Prime commands
success, err = pitboss_api.set_prime("192.168.1.100", true)
assert_eq(success, true, "should successfully send prime on command")
assert_eq(err, nil, "should not return an error for set_prime on")

-- Test 9: Uptime retrieval (via get_system_info or get_status which calls get_uptime internally)
-- Note: get_uptime is an internal function, so we test its effect through public API
mock_responses.next_response = '{"system":"PitBoss","model":"Test","uptime":37580}'
local sys_info, err_sys = pitboss_api.get_system_info("192.168.1.100")
assert_eq(err_sys, nil, "should not return an error for get_system_info")
assert_eq(sys_info.uptime, 37580, "should return correct uptime value from mock")

-- Test 10: Firmware version retrieval
mock_responses.next_response = '{"firmwareVersion":"0.5.7"}'
local fw_version, err_fw = pitboss_api.get_firmware_version("192.168.1.100")
assert_eq(err_fw, nil, "should not return an error for get_firmware_version")
assert_eq(fw_version, "0.5.7", "should return correct firmware version from mock")

-- Test 11: Firmware validation
assert_eq(pitboss_api.is_firmware_valid("0.5.7"), true, "0.5.7 should be valid")
assert_eq(pitboss_api.is_firmware_valid("0.5.8"), true, "0.5.8 should be valid")
assert_eq(pitboss_api.is_firmware_valid("0.5.6"), false, "0.5.6 should be invalid")
assert_eq(pitboss_api.is_firmware_valid("1.0.0"), true, "1.0.0 should be valid")
assert_eq(pitboss_api.is_firmware_valid(nil), false, "nil should be invalid")
assert_eq(pitboss_api.is_firmware_valid(""), false, "empty string should be invalid")

-- Test 12: Clear auth cache
pitboss_api.clear_auth_cache()
-- Re-request status to ensure cache is cleared and re-authentication happens
-- This implicitly tests that get_auth_data works after cache clear
mock_responses.next_response = '{"psw": "F53C2DEBCBE9EE8D21"}'
local status_after_clear, err_clear = pitboss_api.get_status("192.168.1.100")
assert_eq(err_clear, nil, "should not return an error after clearing cache")
assert_eq(status_after_clear.grill_temp, 81, "should still return correct grill temperature after cache clear")