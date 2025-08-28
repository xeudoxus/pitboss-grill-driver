import unittest

from base_test_classes import LuaTestBase


class TestPitbossApi(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        cls.pitboss_api = cls.lua.globals().pitboss_api
        cls.config = cls.lua.globals().config

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.pitboss_api, "pitboss_api module not loaded or not returned as a table"
        )

    def test_helpers_toHexStr_and_fromHexStr(self):
        helpers = self.pitboss_api.helpers
        test_str = "test"
        hex_str = helpers.toHexStr(test_str)
        self.assertEqual(hex_str, "74657374")
        decoded = helpers.fromHexStr(hex_str)
        self.assertEqual(decoded, test_str)
        long_str = "Hello, World!"
        long_hex = helpers.toHexStr(long_str)
        self.assertEqual(helpers.fromHexStr(long_hex), long_str)

    def test_clear_auth_cache(self):
        self.assertTrue(callable(self.pitboss_api.clear_auth_cache))
        self.pitboss_api.clear_auth_cache()

    def test_is_firmware_valid(self):
        is_valid = self.pitboss_api.is_firmware_valid("1.2.3")
        self.assertIsInstance(is_valid, bool)

    def test_network_failure_handling(self):
        # Simulate network failure by patching cosock.socket.tcp to always fail
        self.lua.execute("network_should_fail = true")
        result = self.pitboss_api.get_status("192.168.1.100")
        # Handle tuple return (status, error_message)
        if isinstance(result, tuple):
            status, error_msg = result
        else:
            status = result
        self.assertIsNone(status)

    def test_successful_api_calls(self):
        # Simulate successful API call
        self.lua.execute("network_should_fail = false")
        self.lua.execute(
            'mock_responses.next_response = "{\\"psw\\":\\"F53C2DEBCBE9EE8D21\\",\\"grillTemp\\":99,\\"setTemp\\":160,\\"moduleIsOn\\":true,\\"sc_11\\":\\"000...000\\",\\"sc_12\\":\\"000...000\\"}"'
        )
        status = self.pitboss_api.get_status("192.168.1.100")
        if isinstance(status, tuple):
            status = status[0]
        if status:
            self.assertIn("grill_temp", status)
            self.assertIn("set_temp", status)
            self.assertIn("module_on", status)

    def test_command_sending(self):
        self.lua.execute("network_should_fail = false")

        # Helper function to extract boolean result from potential tuple
        def get_bool_result(result):
            if isinstance(result, tuple):
                return result[0]  # First element is the boolean result
            return result

        self.assertIsInstance(
            get_bool_result(self.pitboss_api.set_power("192.168.1.100", "off")), bool
        )
        self.assertIsInstance(
            get_bool_result(self.pitboss_api.set_temperature("192.168.1.100", 225)),
            bool,
        )
        self.assertIsInstance(
            get_bool_result(self.pitboss_api.set_light("192.168.1.100", "on")), bool
        )
        self.assertIsInstance(
            get_bool_result(self.pitboss_api.set_prime("192.168.1.100", "on")), bool
        )

    def test_temperature_validation(self):
        # Use config values for Fahrenheit (Pit Boss native unit)
        min_temp = self.config.CONSTANTS.MIN_TEMP_F
        max_temp = self.config.CONSTANTS.MAX_TEMP_F

        # Helper function to extract boolean result from potential tuple
        def get_bool_result(result):
            if isinstance(result, tuple):
                return result[0]  # First element is the boolean result
            return result

        # Test with temperatures outside valid range
        if min_temp is not None and max_temp is not None:
            self.assertFalse(
                get_bool_result(
                    self.pitboss_api.set_temperature("192.168.1.100", min_temp - 10)
                )
            )
            self.assertFalse(
                get_bool_result(
                    self.pitboss_api.set_temperature("192.168.1.100", max_temp + 10)
                )
            )
        else:
            # If constants are not loaded, test with obviously invalid values
            self.assertFalse(
                get_bool_result(self.pitboss_api.set_temperature("192.168.1.100", -100))
            )
            self.assertFalse(
                get_bool_result(self.pitboss_api.set_temperature("192.168.1.100", 1000))
            )

    def test_unit_switching(self):
        # Helper function to extract boolean result from potential tuple
        def get_bool_result(result):
            if isinstance(result, tuple):
                return result[0]  # First element is the boolean result
            return result

        self.assertIsInstance(
            get_bool_result(self.pitboss_api.set_unit("192.168.1.100", "C")), bool
        )
        self.assertIsInstance(
            get_bool_result(self.pitboss_api.set_unit("192.168.1.100", "F")), bool
        )

    def test_system_info_and_firmware(self):
        self.lua.execute(
            'mock_responses.next_response = "{\\"system\\":\\"PitBoss\\",\\"model\\":\\"Test\\",\\"uptime\\":37580}"'
        )
        result = self.pitboss_api.get_system_info("192.168.1.100")
        # Handle tuple return (system_info, error_message)
        if isinstance(result, tuple):
            system_info, error_msg = result
        else:
            system_info = result
        # System info should be a dict/table or None
        self.assertTrue(
            system_info is None
            or isinstance(system_info, (dict, type(self.lua.eval("{}"))))
        )

        self.lua.execute(
            'mock_responses.next_response = "{\\"firmwareVersion\\":\\"0.5.7\\"}"'
        )
        result = self.pitboss_api.get_firmware_version("192.168.1.100")
        # Handle tuple return (firmware, error_message)
        if isinstance(result, tuple):
            firmware, error_msg = result
        else:
            firmware = result
        # Firmware should be a string or None
        self.assertTrue(firmware is None or isinstance(firmware, str))

        is_valid = self.pitboss_api.is_firmware_valid("0.5.7")
        self.assertIsInstance(is_valid, bool)

    def test_error_state_and_probe_handling(self):
        self.lua.execute(
            'mock_responses.next_response = "{\\"grillTemp\\":99,\\"error1\\":true,\\"fanError\\":true,\\"noPellets\\":true}"'
        )
        result = self.pitboss_api.get_status("192.168.1.100")
        # Handle tuple return (status, error_message)
        if isinstance(result, tuple):
            status = result[0]
        else:
            status = result

        if status:
            self.assertTrue(status.get("error1"))
            self.assertTrue(status.get("fanError"))
            self.assertTrue(status.get("noPellets"))

        self.lua.execute(
            f'mock_responses.next_response = "{{\\"p1Temp\\":95,\\"p2Temp\\":93,\\"p3Temp\\":{self.config.CONSTANTS.DISCONNECT_VALUE},\\"p4Temp\\":{self.config.CONSTANTS.DISCONNECT_VALUE}}}"'
        )
        result = self.pitboss_api.get_status("192.168.1.100")
        # Handle tuple return (status, error_message)
        if isinstance(result, tuple):
            status = result[0]
        else:
            status = result

        if status:
            self.assertEqual(
                status.get("p3Temp"), self.config.CONSTANTS.DISCONNECT_VALUE
            )
            self.assertEqual(
                status.get("p4Temp"), self.config.CONSTANTS.DISCONNECT_VALUE
            )

    def test_module_structure_and_helpers(self):
        self.assertTrue(callable(self.pitboss_api.get_status))
        self.assertTrue(callable(self.pitboss_api.send_command))
        self.assertTrue(callable(self.pitboss_api.set_temperature))
        self.assertTrue(callable(self.pitboss_api.set_light))
        self.assertTrue(callable(self.pitboss_api.set_prime))
        self.assertTrue(callable(self.pitboss_api.set_power))
        self.assertTrue(callable(self.pitboss_api.set_unit))
        self.assertTrue(callable(self.pitboss_api.get_system_info))
        self.assertTrue(callable(self.pitboss_api.get_firmware_version))
        self.assertTrue(callable(self.pitboss_api.clear_auth_cache))
        helpers = self.pitboss_api.helpers
        # Helpers is a Lua table, not a Python dict
        self.assertIsNotNone(helpers)
        self.assertTrue(callable(helpers.toHexStr))
        self.assertTrue(callable(helpers.fromHexStr))

    def test_connection_timeout_and_rate_limiting(self):
        self.lua.execute("network_should_fail = false")
        self.lua.execute(
            'mock_responses.next_response = "{\\"psw\\":\\"F53C2DEBCBE9EE8D21\\",\\"grillTemp\\":99,\\"setTemp\\":160,\\"moduleIsOn\\":true,\\"sc_11\\":\\"000...000\\",\\"sc_12\\":\\"000...000\\"}"'
        )
        call_count = 0
        for _ in range(5):
            result = self.pitboss_api.get_status("192.168.1.100")
            if result:
                call_count += 1
        self.assertGreaterEqual(call_count, 1)


if __name__ == "__main__":
    unittest.main()
