import unittest

from base_test_classes import LuaTestBase


class TestEncryptionLua(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        cls.pitboss_api = cls.lua.globals().pitboss_api
        cls.helpers = cls.lua.globals().pitboss_api.helpers

    def test_module_loaded(self):
        """Test that pitboss_api and helpers load correctly."""
        self.assertIsNotNone(self.pitboss_api, "pitboss_api module not loaded")
        self.assertIsNotNone(self.helpers, "pitboss_api.helpers is nil")

    def test_password_decryption(self):
        """Test password decryption from hex string."""
        encrypted_password = "F53C2DEBCBE9EE8D21"  # nosec B105

        # Do all binary operations in Lua to avoid UTF-8 decoding issues
        lua_code = (
            '''
        local raw = pitboss_api.helpers.fromHexStr("'''
            + encrypted_password
            + """")
        local decrypted = pitboss_api.helpers.codec(raw, pitboss_api.helpers.FILE_DECODE_KEY, 0, false)
        _G.test_result = {#decrypted, decrypted == "test"}
        """
        )
        self.lua.execute(lua_code)
        result = self.lua.globals().test_result

        # Result is a tuple: (length, is_correct_password)
        length, is_correct = result[1], result[2]
        self.assertEqual(length, 4, "decrypted password should be 4 characters")
        self.assertTrue(is_correct, "password should decrypt to 'test'")

    def test_hex_to_bytes_conversion(self):
        """Test hex to bytes conversion with real values."""
        encrypted_password = "F53C2DEBCBE9EE8D21"  # nosec B105

        # Get the binary data length and first few bytes without returning the binary string
        lua_code = (
            '''
        local bytes_result = pitboss_api.helpers.fromHexStr("'''
            + encrypted_password
            + """")
        _G.test_result = {#bytes_result, string.byte(bytes_result, 1), string.byte(bytes_result, 2), string.byte(bytes_result, 3)}
        """
        )
        self.lua.execute(lua_code)
        result = self.lua.globals().test_result

        length, byte1, byte2, byte3 = result[1], result[2], result[3], result[4]
        self.assertEqual(length, 9, "should convert hex to correct number of bytes")
        self.assertEqual(byte1, 245, "first byte should be 245 (0xF5)")
        self.assertEqual(byte2, 60, "second byte should be 60 (0x3C)")
        self.assertEqual(byte3, 45, "third byte should be 45 (0x2D)")

    def test_hex_conversion_functions(self):
        """Test toHexStr and fromHexStr functions."""
        test_string = "test"
        hex_result = self.helpers.toHexStr(test_string)
        self.assertEqual(
            hex_result,
            "74657374",
            "should convert string to hex correctly using toHexStr",
        )

        hex_string = "74657374"
        string_result = self.helpers.fromHexStr(hex_string)
        self.assertEqual(
            string_result,
            "test",
            "should convert hex to string correctly using fromHexStr",
        )

    def test_command_encryption(self):
        """Test command encryption using codec function."""
        command = "power_off"
        uptime = 37580

        # Do encryption/decryption cycle entirely in Lua
        lua_code = f"""
        local time_val = pitboss_api.helpers.getCodecTime({uptime})
        local codec_key = pitboss_api.helpers.getCodecKey(pitboss_api.helpers.RPC_AUTH_KEY_BASE, time_val)
        local encrypted = pitboss_api.helpers.codec("{command}", codec_key, 0, true)
        local decrypted = pitboss_api.helpers.codec(encrypted, codec_key, 0, false)
        _G.test_result = {{#encrypted, decrypted == "{command}"}}
        """
        self.lua.execute(lua_code)
        result = self.lua.globals().test_result

        encrypted_length, decryption_success = result[1], result[2]
        self.assertGreater(encrypted_length, 0, "encrypted command should not be empty")
        self.assertTrue(
            decryption_success, "decryption should restore original command"
        )

    def test_response_decryption(self):
        """Test response decryption using decode_status_string."""
        decoded_result = self.helpers.decode_status_string("1122334455667788990011")
        # Check that it's a Lua table with content
        self.assertIsNotNone(decoded_result, "should return decoded status")
        # Convert to Python dict to check structure
        result_dict = dict(decoded_result)
        self.assertGreaterEqual(
            len(result_dict), 2, "should return at least 2 byte arrays for parsing"
        )

    def test_grill_status_parsing(self):
        """Test grill status parsing using parse_grill_status."""
        # Convert Python lists to Lua tables
        sc_11_bytes = self.lua.table(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
        sc_12_bytes = self.lua.table(12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23)
        parsed_status = self.helpers.parse_grill_status(sc_11_bytes, sc_12_bytes)
        # Check that it's a Lua table
        self.assertIsNotNone(parsed_status, "should return parsed status")
        # Convert to Python dict to check structure
        status_dict = dict(parsed_status)
        self.assertIn("grill_temp", status_dict, "should parse grill temperature")
        self.assertIn("set_temp", status_dict, "should parse set temperature")

    def test_codec_key_generation(self):
        """Test codec key generation."""
        test_uptime = 12345
        codec_time = self.helpers.getCodecTime(test_uptime)
        self.assertIsInstance(
            codec_time, (int, float), "should return codec time as number"
        )
        codec_key = self.helpers.getCodecKey(self.helpers.RPC_AUTH_KEY_BASE, codec_time)
        # Check that it's a Lua table with content
        self.assertIsNotNone(codec_key, "should return codec key")
        key_list = list(codec_key)
        self.assertGreater(len(key_list), 0, "codec key should not be empty")

    def test_to_hex_function(self):
        """Test toHex function."""
        test_byte = 255
        hex_val = self.helpers.toHex(test_byte)
        self.assertEqual(hex_val, "FF", "should convert 255 to FF")

    def test_round_trip_conversion(self):
        """Test round-trip hex conversion."""
        original_string = "hello"
        hex_version = self.helpers.toHexStr(original_string)
        restored_string = self.helpers.fromHexStr(hex_version)
        self.assertEqual(
            restored_string,
            original_string,
            "should preserve string through hex round-trip",
        )

    def test_codec_function(self):
        """Test codec function works without errors."""
        test_data = "test_data"

        # Test encryption/decryption cycle in Lua
        lua_code = f"""
        local key = {{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}}
        local encoded = pitboss_api.helpers.codec("{test_data}", key, 0, false)
        local decoded = pitboss_api.helpers.codec(encoded, key, 0, true)
        _G.test_result = {{#encoded, decoded == "{test_data}"}}
        """
        self.lua.execute(lua_code)
        result = self.lua.globals().test_result

        encoded_length, decryption_success = result[1], result[2]
        self.assertGreater(encoded_length, 0, "codec should return non-empty result")
        self.assertTrue(decryption_success, "decryption should restore original data")

    def test_real_api_functions(self):
        """Test that we can use the real API functions successfully."""
        # Test the complete decryption process in Lua
        lua_code = """
        local result = pitboss_api.helpers.fromHexStr("F53C2DEBCBE9EE8D21")
        local decoded = pitboss_api.helpers.codec(result, pitboss_api.helpers.FILE_DECODE_KEY, 0, false)
        _G.test_result = {#decoded, decoded == "test"}
        """
        self.lua.execute(lua_code)
        result = self.lua.globals().test_result

        decoded_length, is_test = result[1], result[2]
        self.assertEqual(decoded_length, 4, "decrypted password should be 4 characters")
        self.assertTrue(is_test, "should successfully decrypt to 'test'")


if __name__ == "__main__":
    unittest.main()
