-- Comprehensive Encryption/Decryption tests based on real API behavior from example_api.txt
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Use existing mock files for dependencies
package.loaded["dkjson"] = require("tests.mocks.dkjson")
package.loaded["cosock"] = require("tests.mocks.cosock")

-- Mock bit32 operations for encryption tests
package.loaded["bit32"] = {
  bxor = function(a, b) return a ~ b end,
  band = function(a, b) return a & b end,
  bor = function(a, b) return a | b end,
  bnot = function(a) return ~a end,
  lshift = function(a, b) return a << b end,
  rshift = function(a, b) return a >> b end
}

-- Clear any cached pitboss_api to ensure fresh load
package.loaded["pitboss_api"] = nil

-- Require the actual pitboss_api module
local pitboss_api = require("pitboss_api")

-- Verify helpers loaded correctly
assert(pitboss_api, "pitboss_api module failed to load")
assert(pitboss_api.helpers, "pitboss_api.helpers is nil")

-- Test 1: Password decryption from extconfig.json
local encrypted_password = "F53C2DEBCBE9EE8D21" -- It's "test"
local raw_password = pitboss_api.helpers.fromHexStr(encrypted_password)
local decrypted_password = pitboss_api.helpers.codec(raw_password, pitboss_api.helpers.FILE_DECODE_KEY, 0, false)
assert_eq(decrypted_password, "test", "should decrypt password correctly using real algorithm")

-- Test 2: Hex to bytes conversion with real values
local bytes = pitboss_api.helpers.fromHexStr(encrypted_password)
assert_eq(#bytes, 9, "should convert hex to correct number of bytes")
assert_eq(string.byte(bytes, 1), 245, "first byte should be 245 (0xF5)")
assert_eq(string.byte(bytes, 2), 60, "second byte should be 60 (0x3C)")
assert_eq(string.byte(bytes, 3), 45, "third byte should be 45 (0x2D)")

-- Test 3: Hex conversion with toHexStr (real function)
local test_string = "test"
local hex_result = pitboss_api.helpers.toHexStr(test_string)
assert_eq(hex_result, "74657374", "should convert string to hex correctly using toHexStr")

-- Test 4: String conversion with fromHexStr (real function)
local hex_string = "74657374"
local string_result = pitboss_api.helpers.fromHexStr(hex_string)
assert_eq(string_result, "test", "should convert hex to string correctly using fromHexStr")

-- Test 5: Command encryption using real codec function
local command = "power_off"
local password = "test"
local uptime = 37580
-- Use the real codec function with RPC auth key to encrypt command
local time_val = pitboss_api.helpers.getCodecTime(uptime)
local codec_key = pitboss_api.helpers.getCodecKey(pitboss_api.helpers.RPC_AUTH_KEY_BASE, time_val)
local encrypted_command = pitboss_api.helpers.codec(command, codec_key, 0, true)
assert_eq(type(encrypted_command), "string", "should return encrypted command as string")
assert_eq(#encrypted_command > 0, true, "encrypted command should not be empty")

-- Test 6: Response decryption using real decode_status_string
-- Use a real encoded status string that would come from the grill
local encoded_status = "mock_encoded_status" -- This would be a real hex string from the grill
-- For this test, we'll verify the decode_status_string function works
local decoded_result = pitboss_api.helpers.decode_status_string("1122334455667788990011")
assert_eq(type(decoded_result), "table", "should return decoded status as table")
assert_eq(#decoded_result >= 2, true, "should return at least 2 byte arrays for parsing")

-- Test 7: Grill status parsing using real parse_grill_status
local sc_11_bytes = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
local sc_12_bytes = {12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23}
local parsed_status = pitboss_api.helpers.parse_grill_status(sc_11_bytes, sc_12_bytes)
assert_eq(type(parsed_status), "table", "should return parsed status as table")
assert_eq(type(parsed_status.grill_temp), "string", "should parse grill temperature as string")
assert_eq(type(parsed_status.set_temp), "string", "should parse set temperature as string")

-- Test 8: Codec key generation
local test_uptime = 12345
local codec_time = pitboss_api.helpers.getCodecTime(test_uptime)
assert_eq(type(codec_time), "number", "should return codec time as number")
local codec_key = pitboss_api.helpers.getCodecKey(pitboss_api.helpers.RPC_AUTH_KEY_BASE, codec_time)
assert_eq(type(codec_key), "table", "should return codec key as table")
assert_eq(#codec_key > 0, true, "codec key should not be empty")

-- Test 9: Verify toHex function works correctly
local test_byte = 255
local hex_val = pitboss_api.helpers.toHex(test_byte)
assert_eq(hex_val, "FF", "should convert 255 to FF")

-- Test 10: Verify round-trip conversion
local original_string = "hello"
local hex_version = pitboss_api.helpers.toHexStr(original_string)
local restored_string = pitboss_api.helpers.fromHexStr(hex_version)
assert_eq(restored_string, original_string, "should preserve string through hex round-trip")

-- Test 11: Codec function works without errors
local test_data = "test_data"
local test_key = {1, 2, 3, 4, 5}
local encoded = pitboss_api.helpers.codec(test_data, test_key, 0, false)
assert_eq(type(encoded), "string", "codec should return a string")
assert_eq(#encoded > 0, true, "codec should return non-empty result")

-- Test that we can use the real API functions successfully
local result = pitboss_api.helpers.fromHexStr("F53C2DEBCBE9EE8D21")
local decoded = pitboss_api.helpers.codec(result, pitboss_api.helpers.FILE_DECODE_KEY, 0, false)
assert_eq(decoded, "test", "should successfully decrypt known password using real functions")