import unittest

from base_test_classes import LuaTestBase


class TestNetworkUtils(LuaTestBase):
    """Covers all logic from network_utils_spec.lua using real Lua code and shared helpers."""

    @classmethod
    def _load_modules(cls):
        # Load network_utils module
        cls.network_utils = cls.lua.globals().network_utils
        # Load config module to access constants
        cls.config = cls.lua.globals().config

    def test_module_structure(self):
        self.assertIsNotNone(
            self.network_utils,
            "network_utils module not loaded or not returned as a table",
        )
        self.assertTrue(
            self.network_utils.validate_ip_address is not None,
            "validate_ip_address should be present",
        )

    def test_config_constants_loaded(self):
        """Test that config constants are properly loaded."""
        self.assertIsNotNone(self.config, "config module not loaded")
        self.assertIsNotNone(self.config.CONSTANTS, "config.CONSTANTS not loaded")
        self.assertIsNotNone(
            self.config.CONSTANTS.DEFAULT_IP_ADDRESS, "DEFAULT_IP_ADDRESS not loaded"
        )

    def test_validate_ip_address_valid(self):
        result = self.network_utils.validate_ip_address("192.168.1.100")
        # Handle both single return value (true) and tuple return (true, message)
        if isinstance(result, tuple):
            valid_ip, valid_msg = result
        else:
            valid_ip = result
        self.assertTrue(valid_ip, "should validate correct IP address")

    def test_validate_ip_address_invalid_segment(self):
        result = self.network_utils.validate_ip_address("999.999.999.999")
        # Handle both single return value (false) and tuple return (false, message)
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with segments > 255")

    def test_validate_ip_address_invalid_format(self):
        result = self.network_utils.validate_ip_address("not.an.ip")
        # Handle both single return value (false) and tuple return (false, message)
        if isinstance(result, tuple):
            invalid_format, format_msg = result
        else:
            invalid_format = result
        self.assertFalse(invalid_format, "should reject non-numeric format")

    def test_validate_ip_address_octet_255_fails(self):
        """Test that IP addresses with any octet = 255 fail validation (1-254 range)."""
        # Test first octet = 255
        result = self.network_utils.validate_ip_address("255.168.1.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with first octet = 255")

        # Test second octet = 255
        result = self.network_utils.validate_ip_address("192.255.1.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with second octet = 255")

        # Test third octet = 255
        result = self.network_utils.validate_ip_address("192.168.255.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with third octet = 255")

        # Test fourth octet = 255
        result = self.network_utils.validate_ip_address("192.168.1.255")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with fourth octet = 255")

    def test_validate_ip_address_octet_0_fails(self):
        """Test that IP addresses with any octet = 0 fail validation (1-254 range)."""
        # Test first octet = 0
        result = self.network_utils.validate_ip_address("0.168.1.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with first octet = 0")

        # Test second octet = 0
        result = self.network_utils.validate_ip_address("192.0.1.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with second octet = 0")

        # Test third octet = 0
        result = self.network_utils.validate_ip_address("192.168.0.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with third octet = 0")

        # Test fourth octet = 0
        result = self.network_utils.validate_ip_address("192.168.1.0")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with fourth octet = 0")

    def test_validate_ip_address_octet_above_254_fails(self):
        """Test that IP addresses with any octet > 254 fail validation."""
        # Test first octet > 254
        result = self.network_utils.validate_ip_address("255.168.1.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with first octet > 254")

        # Test second octet > 254
        result = self.network_utils.validate_ip_address("192.255.1.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with second octet > 254")

        # Test third octet > 254
        result = self.network_utils.validate_ip_address("192.168.255.100")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with third octet > 254")

        # Test fourth octet > 254
        result = self.network_utils.validate_ip_address("192.168.1.255")
        if isinstance(result, tuple):
            invalid_ip, invalid_msg = result
        else:
            invalid_ip = result
        self.assertFalse(invalid_ip, "should reject IP with fourth octet > 254")

    def test_validate_ip_address_valid_range(self):
        """Test that IP addresses with all octets in 1-254 range pass validation."""
        # Test minimum valid values
        result = self.network_utils.validate_ip_address("1.1.1.1")
        if isinstance(result, tuple):
            valid_ip, valid_msg = result
        else:
            valid_ip = result
        self.assertTrue(valid_ip, "should accept IP with minimum valid octets")

        # Test maximum valid values
        result = self.network_utils.validate_ip_address("254.254.254.254")
        if isinstance(result, tuple):
            valid_ip, valid_msg = result
        else:
            valid_ip = result
        self.assertTrue(valid_ip, "should accept IP with maximum valid octets")

        # Test mixed valid values
        result = self.network_utils.validate_ip_address("192.168.1.100")
        if isinstance(result, tuple):
            valid_ip, valid_msg = result
        else:
            valid_ip = result
        self.assertTrue(valid_ip, "should accept typical valid IP")

    def test_hash_function(self):
        """Test the hash function for table change detection."""
        # Test with valid table
        test_table = self.lua.eval('{temp = 225, status = "on", probe1 = 180}')
        hash_result = self.network_utils.hash(test_table)
        self.assertIsInstance(hash_result, str)
        self.assertIn("temp=225", hash_result)
        self.assertIn("status=on", hash_result)

        # Test with invalid input
        invalid_hash = self.network_utils.hash(None)
        self.assertEqual(invalid_hash, "invalid_table")

    def test_subnet_prefix_extraction(self):
        """Test subnet prefix extraction from IP addresses."""
        subnet = self.network_utils.get_subnet_prefix("192.168.1.100")
        self.assertEqual(subnet, "192.168.1")

        subnet2 = self.network_utils.get_subnet_prefix("10.0.0.50")
        self.assertEqual(subnet2, "10.0.0")

    def test_hub_ip_finding(self):
        """Test finding hub IP from driver."""
        # Create mock driver with hub IP
        mock_driver = self.lua.eval('{environment_info = {hub_ipv4 = "192.168.1.50"}}')
        hub_ip = self.network_utils.find_hub_ip(mock_driver)
        self.assertEqual(hub_ip, "192.168.1.50")

    def test_rediscovery_ip_check(self):
        """Test rediscovery IP detection."""
        # Test with default IP (should trigger rediscovery)
        default_ip = self.config.CONSTANTS.DEFAULT_IP_ADDRESS
        is_rediscovery = self.network_utils.is_rediscovery_ip(default_ip)
        self.assertTrue(is_rediscovery)

        # Test with debug IP (should trigger rediscovery)
        debug_ip = self.config.CONSTANTS.DEBUG_IP_ADDRESS
        is_debug = self.network_utils.is_rediscovery_ip(debug_ip)
        self.assertTrue(is_debug)

        # Test with empty IP (should trigger rediscovery)
        is_empty = self.network_utils.is_rediscovery_ip("")
        self.assertTrue(is_empty)

        # Test with normal IP (should not trigger rediscovery)
        is_normal = self.network_utils.is_rediscovery_ip("192.168.1.100")
        self.assertFalse(is_normal)

    def test_device_profile_building(self):
        """Test building device profile from grill data."""
        grill_data = self.lua.eval(
            """{
            id = "test-grill-123",
            ip = "192.168.1.100",
            firmware_version = "1.2.3",
            name = "Test Grill"
        }"""
        )

        profile = self.network_utils.build_device_profile(grill_data)
        self.assertIsNotNone(profile)
        self.assertEqual(profile.device_network_id, "test-grill-123")
        self.assertEqual(profile.type, "LAN")
        # The label format is "Pit Boss Grill (last-6-chars-of-id)"
        self.assertIn("Pit Boss Grill", profile.label)
        self.assertIn("ll-123", profile.label)  # Last 6 chars of "test-grill-123"

    def test_update_device_ip(self):
        """Test updating device IP with validation."""
        # Test with valid IP
        success = self.network_utils.update_device_ip(
            self.lua_device, "192.168.1.101"
        )
        self.assertTrue(success)

        # Test with invalid IP
        failure = self.network_utils.update_device_ip(
            self.lua_device, "invalid.ip.address"
        )
        self.assertFalse(failure)

    def test_network_cache_cleanup(self):
        """Test network cache cleanup."""
        # Should complete without error
        self.network_utils.cleanup_network_cache()

    def test_find_device_by_network_id(self):
        """Test finding device by network ID."""
        # Create mock driver with device list
        mock_driver = self.lua.eval(
            """{
            get_devices = function(self)
                return {{network_id = "test-device-123"}}
            end
        }"""
        )

        found_device = self.network_utils.find_device_by_network_id(
            mock_driver, "test-device-123"
        )
        self.assertIsNotNone(found_device)

    def test_should_attempt_rediscovery(self):
        """Test rediscovery decision logic."""
        # Set up device with preferences
        self.py_device.preferences = {
            "refreshInterval": 30,
            "ipAddress": "192.168.1.100",
        }

        # Mock get_field to return last rediscovery time
        original_get_field = self.lua_device.get_field

        def mock_get_field(key):
            if key == "last_rediscovery":
                return 1000  # Some time in the past
            elif key == "ip_address":
                return "192.168.1.100"
            return original_get_field(key) if original_get_field else None

        self.lua_device.get_field = mock_get_field

        should_rediscover = self.network_utils.should_attempt_rediscovery(
            self.lua_device
        )
        self.assertIsInstance(should_rediscover, bool)

    def test_health_check(self):
        """Test device health check."""
        # Create mock driver
        mock_driver = self.lua.eval('{environment_info = {hub_ipv4 = "192.168.1.50"}}')

        # Set device IP
        self.py_device.set_field("ip_address", "192.168.1.100")

        health_result = self.network_utils.health_check(self.lua_device, mock_driver)
        self.assertIsInstance(health_result, bool)

    def test_test_grill_at_ip(self):
        """Test grill testing at specific IP."""
        # This will likely fail due to no actual grill, but should return None gracefully
        grill_test = self.network_utils.test_grill_at_ip(
            "192.168.1.100", "test-device-id"
        )
        # Should return None or a table, not throw an error
        self.assertTrue(grill_test is None or isinstance(grill_test, dict))

    def test_resolve_device_ip(self):
        """Test IP resolution from multiple sources."""
        # Use a valid IP that's not a system IP
        test_ip = "192.168.1.100"

        # Set up device with IP in preferences and stored field
        self.py_device.preferences = {"ipAddress": test_ip}
        self.py_device.set_field("ip_address", test_ip)

        # Update the Lua device to reflect the changes
        self.lua_device = self.utils.convert_device_to_lua(self.lua, self.py_device)

        resolved_ip = self.network_utils.resolve_device_ip(self.lua_device, False)
        self.assertEqual(resolved_ip, test_ip)

    def test_schedule_cache_cleanup(self):
        """Test cache cleanup scheduling."""
        # Should complete without error
        self.network_utils.schedule_cache_cleanup(self.lua_device, 5)


if __name__ == "__main__":
    unittest.main()
