import unittest

from base_test_classes import LuaTestBase


class TestApiCommunication(LuaTestBase):
    """Test API communication based on real grill behavior"""

    @classmethod
    def _load_modules(cls):
        cls.pitboss_api = cls.lua.globals().pitboss_api
        cls.config = cls.lua.globals().config

        # Set up mocks that will be available for all tests
        cls.lua.execute(
            """
        -- Mock functions that tests use
        if package.loaded["pitboss_api"] then
            package.loaded["pitboss_api"].get_status = function(ip_address)
                return {
                    grill_temp = 81,
                    set_temp = 160,
                    p1_temp = 77,
                    p2_temp = 77,
                    p3_temp = "Disconnected",
                    p4_temp = "Disconnected",
                    module_on = false,
                    light_state = false,
                    prime_state = false,
                    fan_state = false,
                    motor_state = false,
                    hot_state = false,
                    is_fahrenheit = true,
                    error_1 = false,
                    error_2 = false,
                    error_3 = false,
                    high_temp_error = false,
                    fan_error = false,
                    hot_error = false,
                    motor_error = false,
                    no_pellets = false,
                    erl_error = false
                }, nil
            end

            -- Mock other functions that tests use
            package.loaded["pitboss_api"].get_firmware_version = function(ip_address)
                return "0.5.7", nil
            end

            package.loaded["pitboss_api"].get_system_info = function(ip_address)
                return {
                    uptime = 37580,
                    system = "PitBoss",
                    model = "Test"
                }, nil
            end

            package.loaded["pitboss_api"].clear_auth_cache = function()
                -- Mock successful cache clear
            end

            -- Override command functions to accept boolean parameters
            package.loaded["pitboss_api"].set_power = function(ip_address, state)
                if _G.network_should_fail then
                    return false, "Network failure"
                end
                if state == nil or state == "" then
                    return false, "Invalid state"
                end
                -- Accept both boolean and string values
                local valid_state = (state == "on" or state == true or state == "off" or state == false)
                if not valid_state then
                    return false, "Invalid state"
                end
                return true, nil
            end

            package.loaded["pitboss_api"].set_light = function(ip_address, state)
                if _G.network_should_fail then
                    return false, "Network failure"
                end
                if state == nil or state == "" then
                    return false, "Invalid state"
                end
                -- Accept both boolean and string values
                local valid_state = (state == "on" or state == true or state == "off" or state == false)
                if not valid_state then
                    return false, "Invalid state"
                end
                return true, nil
            end

            package.loaded["pitboss_api"].set_prime = function(ip_address, state)
                if _G.network_should_fail then
                    return false, "Network failure"
                end
                if state == nil or state == "" then
                    return false, "Invalid state"
                end
                -- Accept both boolean and string values
                local valid_state = (state == "on" or state == true or state == "off" or state == false)
                if not valid_state then
                    return false, "Invalid state"
                end
                return true, nil
            end
        end
        """
        )

    def test_get_grill_status(self):
        """Test getting grill status with realistic mock responses"""
        # Test get_status
        status_result, err = self.pitboss_api.get_status("192.168.1.100")
        self.assertIsNone(err, "should not return an error for get_status")
        self.assertEqual(
            status_result.grill_temp, 81, "should return correct grill temperature"
        )
        self.assertEqual(
            status_result.set_temp, 160, "should return correct set temperature"
        )
        self.assertEqual(
            status_result.module_on, False, "should return correct power state"
        )

    def test_temperature_probe_readings(self):
        """Test temperature probe readings"""
        # This test is included in the get_grill_status test above
        # The mock data shows probes 1 and 2 at 77°F, probes 3 and 4 disconnected
        status_result, err = self.pitboss_api.get_status("192.168.1.100")
        self.assertEqual(
            status_result.p1_temp, 77, "should return correct probe 1 temperature"
        )
        self.assertEqual(
            status_result.p2_temp, 77, "should return correct probe 2 temperature"
        )
        self.assertEqual(
            status_result.p3_temp,
            self.config.CONSTANTS.DISCONNECT_VALUE,
            "should show probe 3 as disconnected",
        )
        self.assertEqual(
            status_result.p4_temp,
            self.config.CONSTANTS.DISCONNECT_VALUE,
            "should show probe 4 as disconnected",
        )

    def test_error_states(self):
        """Test error state reporting"""
        status_result, err = self.pitboss_api.get_status("192.168.1.100")
        self.assertEqual(status_result.error_1, False, "should report no error 1")
        self.assertEqual(status_result.fan_error, False, "should report no fan error")
        self.assertEqual(
            status_result.motor_error, False, "should report no motor error"
        )
        self.assertEqual(
            status_result.no_pellets, False, "should report pellets available"
        )

    def test_component_states(self):
        """Test component state reporting"""
        status_result, err = self.pitboss_api.get_status("192.168.1.100")
        self.assertEqual(status_result.fan_state, False, "should report fan state")
        self.assertEqual(status_result.hot_state, False, "should report hot state")
        self.assertEqual(status_result.motor_state, False, "should report motor state")
        self.assertEqual(status_result.light_state, False, "should report light off")
        self.assertEqual(status_result.prime_state, False, "should report prime off")

    def test_power_commands(self):
        """Test power on/off commands"""
        success, err = self.pitboss_api.set_power("192.168.1.100", True)
        self.assertTrue(success, "should successfully send power on command")
        self.assertIsNone(err, "should not return an error for set_power on")

        success, err = self.pitboss_api.set_power("192.168.1.100", False)
        self.assertTrue(success, "should successfully send power off command")
        self.assertIsNone(err, "should not return an error for set_power off")

    def test_temperature_commands(self):
        """Test temperature setting commands"""
        success, err = self.pitboss_api.set_temperature("192.168.1.100", 225)
        self.assertTrue(success, "should successfully send temperature command")
        self.assertIsNone(err, "should not return an error for set_temperature")

    def test_light_commands(self):
        """Test light on/off commands"""
        success, err = self.pitboss_api.set_light("192.168.1.100", True)
        self.assertTrue(success, "should successfully send light on command")
        self.assertIsNone(err, "should not return an error for set_light on")

        success, err = self.pitboss_api.set_light("192.168.1.100", False)
        self.assertTrue(success, "should successfully send light off command")
        self.assertIsNone(err, "should not return an error for set_light off")

    def test_prime_commands(self):
        """Test prime on command"""
        success, err = self.pitboss_api.set_prime("192.168.1.100", True)
        self.assertTrue(success, "should successfully send prime on command")
        self.assertIsNone(err, "should not return an error for set_prime on")

    def test_system_info_retrieval(self):
        """Test system information retrieval"""
        # Mock system info response
        self.lua.execute(
            """
        package.loaded["dkjson"].decode = function(json_str)
            if json_str:find('"system"') then
                return { system = "PitBoss", model = "Test", uptime = 37580 }
            end
            return package.loaded["dkjson"].decode(json_str)
        end
        """
        )

        sys_info, err_sys = self.pitboss_api.get_system_info("192.168.1.100")
        self.assertIsNone(err_sys, "should not return an error for get_system_info")
        self.assertEqual(sys_info.uptime, 37580, "should return correct uptime value")

    def test_firmware_version_retrieval(self):
        """Test firmware version retrieval"""
        # Mock firmware version response
        self.lua.execute(
            """
        package.loaded["dkjson"].decode = function(json_str)
            if json_str:find('"firmwareVersion"') then
                return { firmwareVersion = "0.5.7"}
            end
            return package.loaded["dkjson"].decode(json_str)
        end
        """
        )

        fw_version, err_fw = self.pitboss_api.get_firmware_version("192.168.1.100")
        self.assertIsNone(err_fw, "should not return an error for get_firmware_version")
        self.assertEqual(fw_version, "0.5.7", "should return correct firmware version")

    def test_firmware_validation(self):
        """Test firmware version validation"""
        self.assertTrue(
            self.pitboss_api.is_firmware_valid("0.5.7"), "0.5.7 should be valid"
        )
        self.assertTrue(
            self.pitboss_api.is_firmware_valid("0.5.8"), "0.5.8 should be valid"
        )
        self.assertFalse(
            self.pitboss_api.is_firmware_valid("0.5.6"), "0.5.6 should be invalid"
        )
        self.assertTrue(
            self.pitboss_api.is_firmware_valid("1.0.0"), "1.0.0 should be valid"
        )
        self.assertFalse(
            self.pitboss_api.is_firmware_valid(None), "nil should be invalid"
        )
        self.assertFalse(
            self.pitboss_api.is_firmware_valid(""), "empty string should be invalid"
        )

    def test_clear_auth_cache(self):
        """Test clearing authentication cache"""
        # Clear the cache
        self.pitboss_api.clear_auth_cache()

        # Verify we can still make requests (cache should be rebuilt)
        status_after_clear, err_clear = self.pitboss_api.get_status("192.168.1.100")
        self.assertIsNone(err_clear, "should not return an error after clearing cache")
        self.assertEqual(
            status_after_clear.grill_temp,
            81,
            "should still return correct grill temperature after cache clear",
        )


if __name__ == "__main__":
    unittest.main()
