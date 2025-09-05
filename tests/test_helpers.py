"""
Common test helpers and utilities for SmartThings Edge driver tests.
Provides standardized setup, assertions, and utilities to reduce code duplication.
"""

import os
import sys
import unittest

from device_situations import DeviceFactory, DeviceSituations, MockDataFactory
from utils_lua_test import LuaTestUtils

# Add the tests directory to the Python path
tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)


class SmartThingsTestBase(unittest.TestCase):
    """Enhanced base class for SmartThings Edge driver tests with standardized setup."""

    @classmethod
    def setUpClass(cls):
        """Set up Lua runtime with all dependencies loaded."""
        super().setUpClass()
        cls.lua = LuaTestUtils.setup_lua_runtime()
        cls.utils = LuaTestUtils

        # Load config.lua first as it's needed by most modules
        cls.config = cls.lua.eval('require("config")')

        # Load other commonly used modules
        cls._load_common_modules()

    @classmethod
    def _load_common_modules(cls):
        """Load modules commonly used across tests. Override in subclasses as needed."""
        try:
            cls.custom_capabilities = cls.lua.eval('require("custom_capabilities")')
            cls.temperature_calibration = cls.lua.eval(
                'require("temperature_calibration")'
            )
            cls.temperature_service = cls.lua.eval('require("temperature_service")')
            cls.network_utils = cls.lua.eval('require("network_utils")')
        except Exception:
            # Some modules might not be available in all test contexts
            pass  # nosec B110

    def setUp(self):
        """Set up each test with a fresh device."""
        super().setUp()
        self.py_device = DeviceFactory.create_online_grill()
        self.lua_device = self.utils.convert_device_to_lua(self.lua, self.py_device)

    def create_device(self, situation_name="online", **overrides):
        """Create a device in a specific situation."""
        situation_method = getattr(DeviceSituations, f"grill_{situation_name}")
        situation = situation_method()
        situation.update(overrides)
        return DeviceFactory.create_device_from_situation(situation)

    def create_lua_device(self, situation_name="online", **overrides):
        """Create a device in a specific situation and convert to Lua."""
        py_dev = self.create_device(situation_name, **overrides)
        lua_dev = self.utils.convert_device_to_lua(self.lua, py_dev)
        return py_dev, lua_dev

    def assert_device_field_equals(self, device, field_name, expected_value):
        """Assert that a device field has the expected value."""
        actual_value = device.get_field(field_name)
        self.assertEqual(
            actual_value,
            expected_value,
            f"Field '{field_name}' expected {expected_value}, got {actual_value}",
        )

    def assert_device_field_is_none(self, device, field_name):
        """Assert that a device field is None."""
        actual_value = device.get_field(field_name)
        self.assertIsNone(
            actual_value, f"Field '{field_name}' expected None, got {actual_value}"
        )

    def assert_temperature_valid(self, temperature, unit="F"):
        """Assert that a temperature value is valid according to config."""
        is_valid = self.temperature_service.is_valid_temperature(temperature, unit)
        self.assertTrue(is_valid, f"Temperature {temperature}°{unit} should be valid")

    def assert_temperature_invalid(self, temperature, unit="F"):
        """Assert that a temperature value is invalid according to config."""
        is_valid = self.temperature_service.is_valid_temperature(temperature, unit)
        self.assertFalse(
            is_valid, f"Temperature {temperature}°{unit} should be invalid"
        )

    def assert_event_emitted(self, device, event_name, event_value=None):
        """Assert that a specific event was emitted by the device."""
        events = device.get_field("_events") or []
        matching_events = [e for e in events if e.get("name") == event_name]
        if event_value is not None:
            matching_events = [
                e for e in matching_events if e.get("value") == event_value
            ]

        self.assertTrue(
            len(matching_events) > 0,
            f"Event '{event_name}'{' with value {event_value}' if event_value else ''} was not emitted",
        )

        return matching_events[0] if matching_events else None

    def assert_no_event_emitted(self, device, event_name):
        """Assert that a specific event was NOT emitted."""
        events = device.get_field("_events") or []
        matching_events = [e for e in events if e.get("name") == event_name]
        self.assertEqual(
            len(matching_events),
            0,
            f"Event '{event_name}' should not have been emitted",
        )

    def get_config_value(self, *keys):
        """Get a value from config.lua using dot notation."""
        current = self.config
        for key in keys:
            if hasattr(current, key):
                current = getattr(current, key)
            elif isinstance(current, dict) and key in current:
                current = current[key]
            else:
                raise KeyError(f"Config key '{key}' not found in path {'.'.join(keys)}")
        return current

    def assert_config_constant(self, constant_name, expected_value):
        """Assert that a config constant has the expected value."""
        actual_value = self.get_config_value("CONSTANTS", constant_name)
        self.assertEqual(
            actual_value,
            expected_value,
            f"Config constant {constant_name} expected {expected_value}, got {actual_value}",
        )

    def create_mock_api_response(self, response_type="success", **overrides):
        """Create a mock API response."""
        if response_type == "success":
            response = MockDataFactory.create_success_api_response()
        elif response_type == "error":
            response = MockDataFactory.create_error_api_response()
        elif response_type == "timeout":
            response = MockDataFactory.create_network_timeout_response()
        else:
            raise ValueError(f"Unknown response type: {response_type}")

        response.update(overrides)
        return response


class ConfigTestMixin:
    """Mixin to ensure config.lua constants are used consistently in tests."""

    def assert_uses_config_constant(self, actual_value, constant_path):
        """Assert that a value matches a config constant."""
        config_value = self.get_config_value(*constant_path.split("."))
        self.assertEqual(
            actual_value,
            config_value,
            f"Value {actual_value} should use config constant {constant_path} ({config_value})",
        )

    def get_temperature_range(self, unit="F"):
        """Get temperature range from config."""
        return self.get_config_value("get_temperature_range")(unit)

    def get_sensor_range(self, unit="F"):
        """Get sensor range from config."""
        return self.get_config_value("get_sensor_range")(unit)

    def get_approved_setpoints(self, unit="F"):
        """Get approved setpoints from config."""
        return self.get_config_value("get_approved_setpoints")(unit)


class TestAssertionHelpers:
    """Common assertion helpers for SmartThings driver tests."""

    @staticmethod
    def assert_device_online(device):
        """Assert that a device is online."""
        state = device.get_field("state")
        assert (
            state == "on"
        ), f"Device should be online, but state is {state}"  # nosec B101

    @staticmethod
    def assert_device_offline(device):
        """Assert that a device is offline."""
        state = device.get_field("state")
        assert (
            state == "off"
        ), f"Device should be offline, but state is {state}"  # nosec B101

    @staticmethod
    def assert_temperature_in_range(temperature, min_temp, max_temp, unit="F"):
        """Assert that a temperature is within a valid range."""
        assert (
            min_temp <= temperature <= max_temp
        ), f"Temperature {temperature}°{unit} is outside valid range [{min_temp}, {max_temp}]"  # nosec B101

    @staticmethod
    def assert_probe_connected(device, probe_number):
        """Assert that a specific probe is connected."""
        probe_temp = device.get_field(f"probe{probe_number}_temp")
        assert (
            probe_temp is not None
        ), f"Probe {probe_number} should be connected"  # nosec B101

    @staticmethod
    def assert_probe_disconnected(device, probe_number):
        """Assert that a specific probe is disconnected."""
        probe_temp = device.get_field(f"probe{probe_number}_temp")
        assert (
            probe_temp is None
        ), f"Probe {probe_number} should be disconnected"  # nosec B101


def setup_minimal_lua_runtime():
    """Set up a minimal Lua runtime for simple tests."""
    return LuaTestUtils.setup_lua_runtime()


def load_lua_module(lua, module_name):
    """Load a Lua module and return it."""
    return lua.eval(f'require("{module_name}")')


def create_standard_device():
    """Create a standard test device."""
    return DeviceFactory.create_online_grill()


def create_device_in_situation(situation_name, **overrides):
    """Create a device in a specific situation."""
    situation_method = getattr(DeviceSituations, f"grill_{situation_name}")
    situation = situation_method()
    situation.update(overrides)
    return DeviceFactory.create_device_from_situation(situation)
