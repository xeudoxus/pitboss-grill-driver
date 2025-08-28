"""
Base test class for SmartThings Edge driver Python tests.
Provides common setup and utilities for testing Lua modules from Python.
"""

import json
import os
import sys

from device_situations import DeviceFactory, DeviceSituations
from mock_device import (
    PyDevice,
    create_default_grill_status,
    create_default_preferences,
)
from test_helpers import ConfigTestMixin, SmartThingsTestBase

# Add the tests directory to the Python path so imports work from both project root and tests directory
tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)


class LuaTestBase(SmartThingsTestBase, ConfigTestMixin):
    """Base class for Lua-Python integration tests."""

    @classmethod
    def setUpClass(cls):
        """Set up Lua runtime and load all dependencies."""
        super().setUpClass()

        # Initialize Lua coverage if enabled
        cls._setup_lua_coverage()

        # Store commonly used Lua modules as class attributes
        cls.config = cls.lua.globals().config

        # Store any other commonly used modules
        # Subclasses can override this to add their specific modules
        cls._load_modules()

    @classmethod
    def _setup_lua_coverage(cls):
        """Set up Lua coverage tracking if enabled via environment variable."""
        cls.lua_coverage_enabled = os.environ.get("LUA_COVERAGE", "").lower() in (
            "1",
            "true",
            "yes",
        )

        if cls.lua_coverage_enabled:
            try:
                # Load the Lua coverage module
                coverage_path = os.path.join(tests_dir, "lua_coverage.lua").replace(
                    "\\", "/"
                )
                cls.lua.execute(
                    f"""
local coverage = dofile("{coverage_path}")
coverage.init()
coverage.start()
_G.coverage = coverage
                """
                )

                # Store coverage module reference
                cls.lua_coverage = cls.lua.globals().coverage

                print("Lua coverage tracking enabled")
            except Exception as e:
                print(f"Warning: Failed to initialize Lua coverage: {e}")
                cls.lua_coverage_enabled = False
        else:
            cls.lua_coverage = None

    def start_lua_coverage(self):
        """Start Lua coverage tracking for this test."""
        if self.lua_coverage_enabled and self.lua_coverage:
            self.lua_coverage.start()

    def stop_lua_coverage(self):
        """Stop Lua coverage tracking and return coverage data."""
        if self.lua_coverage_enabled and self.lua_coverage:
            self.lua_coverage.stop()
            return dict(self.lua_coverage.get_data())
        return {}

    def export_lua_coverage(self, output_file="lua_coverage.json"):
        """Export Lua coverage data to a file."""
        if self.lua_coverage_enabled and self.lua_coverage:
            coverage_data = self.stop_lua_coverage()

            # Convert Lua tables to Python dicts for JSON serialization
            def convert_lua_table(obj):
                if hasattr(obj, "_obj"):  # Lupa Lua table
                    try:
                        return dict(obj)
                    except Exception:
                        return str(obj)
                elif isinstance(obj, dict):
                    return {k: convert_lua_table(v) for k, v in obj.items()}
                elif isinstance(obj, (list, tuple)):
                    return [convert_lua_table(item) for item in obj]
                else:
                    return obj

            converted_data = convert_lua_table(coverage_data)

            with open(output_file, "w") as f:
                json.dump(converted_data, f, indent=2)
            print(f"Lua coverage data exported to {output_file}")
            return converted_data
        return {}

    @classmethod
    def _load_modules(cls):
        """Load modules using proper Lua loading mechanism."""
        try:
            # Load capability_handlers using the utils method
            cls.capability_handlers = cls.utils.require_lua_table(
                cls.lua, "capability_handlers"
            )
        except Exception:
            # Fallback to direct require if the utils method fails
            try:
                result = cls.lua.eval('require("capability_handlers")')
                if isinstance(result, tuple):
                    cls.capability_handlers = (
                        result[1] if len(result) > 1 else result[0]
                    )
                else:
                    cls.capability_handlers = result
            except Exception as e2:
                print(f"Failed to load capability_handlers: {e2}")
                cls.capability_handlers = None

    def setUp(self):
        """Set up each test."""
        # Create a fresh device for each test
        self.py_device = PyDevice()
        self.lua_device = self.utils.convert_device_to_lua(self.lua, self.py_device)

    def tearDown(self):
        """Clean up after each test."""
        if hasattr(self, "py_device"):
            self.py_device.reset()

    def create_device(self, situation_name="grill_online_basic", preferences=None):
        """Create a new PyDevice using DeviceFactory with a specific situation."""
        if preferences is None:
            preferences = create_default_preferences()

        # Handle backward compatibility for "on"/"off" strings
        if situation_name == "on":
            situation_dict = DeviceSituations.grill_online_basic()
        elif situation_name == "off":
            situation_dict = DeviceSituations.grill_offline()
        elif hasattr(DeviceSituations, situation_name):
            situation_dict = getattr(DeviceSituations, situation_name)()
        else:
            # Assume it's already a situation dictionary
            situation_dict = situation_name

        return DeviceFactory.create_device_from_situation(
            situation_dict, preferences=preferences
        )

    def create_lua_device(self, situation_name="grill_online_basic", preferences=None):
        """Create a new PyDevice using DeviceFactory and convert it to Lua."""
        py_dev = self.create_device(situation_name, preferences)
        lua_dev = self.utils.convert_device_to_lua(self.lua, py_dev)
        return py_dev, lua_dev

    def create_grill_status(self, **overrides):
        """Create a grill status dict with optional overrides."""
        status = create_default_grill_status()
        status.update(overrides)
        return status

    def to_lua_table(self, python_dict):
        """Convert a Python dict to a Lua table."""
        return self.utils.to_lua_table(self.lua, python_dict)

    def assert_event_exists(
        self, events, event_name=None, event_value=None, attribute=None
    ):
        """Assert that an event with given name/value exists."""
        event = self.utils.find_event(events, event_name, event_value, attribute)
        self.assertIsNotNone(
            event,
            f"Event not found: name={event_name}, value={event_value}, attribute={attribute}",
        )
        return event

    def assert_component_event_exists(
        self,
        component_events,
        component_id,
        event_name=None,
        event_value=None,
        attribute=None,
    ):
        """Assert that a component event exists."""
        event = self.utils.find_component_event(
            component_events, component_id, event_name, event_value, attribute
        )
        self.assertIsNotNone(
            event,
            f"Component event not found: component={component_id}, name={event_name}, value={event_value}, attribute={attribute}",
        )
        return event

    def assert_switch_off(self, component_events):
        """Assert that a switch off event exists in component events."""
        found_off = any(
            self.utils.is_switch_off(ce["event"]) for ce in component_events
        )
        self.assertTrue(found_off, "Switch off event not found")

    def assert_field_equals(self, device, field_name, expected_value):
        """Assert that a device field has the expected value."""
        actual_value = device.get_field(field_name)
        self.assertEqual(
            actual_value,
            expected_value,
            f"Field '{field_name}' expected {expected_value}, got {actual_value}",
        )

    def assert_field_is_none(self, device, field_name):
        """Assert that a device field is None."""
        actual_value = device.get_field(field_name)
        self.assertIsNone(
            actual_value, f"Field '{field_name}' expected None, got {actual_value}"
        )

    def print_debug_info(self, device):
        """Print debug information about device state."""
        pass  # Debug output disabled


class DeviceStatusServiceTestBase(LuaTestBase):
    """Base class specifically for device_status_service tests."""

    @classmethod
    def _load_modules(cls):
        """Load device_status_service module."""
        cls.device_status_service = cls.lua.globals().device_status_service
        # Load status messages from config instead of separate locales module
        cls.language = cls.config.STATUS_MESSAGES


class TemperatureServiceTestBase(LuaTestBase):
    """Base class specifically for temperature_service tests."""

    @classmethod
    def _load_modules(cls):
        """Load temperature_service module."""
        cls.temperature_service = cls.lua.globals().temperature_service


class CapabilityHandlersTestBase(LuaTestBase):
    """Base class specifically for capability_handlers tests."""

    @classmethod
    def _load_modules(cls):
        """Load capability_handlers module."""
        cls.capability_handlers = cls.lua.globals().capability_handlers


class CommandServiceTestBase(LuaTestBase):
    """Base class specifically for command_service tests."""

    @classmethod
    def _load_modules(cls):
        """Load command_service module."""
        cls.command_service = cls.lua.globals().command_service


class PanicManagerTestBase(LuaTestBase):
    """Base class specifically for panic_manager tests."""

    @classmethod
    def _load_modules(cls):
        """Load panic_manager module."""
        cls.panic_manager = cls.lua.globals().panic_manager
        # Load language module
        cls.language = cls.utils.require_lua_table(cls.lua, "locales.en")


class HealthMonitorTestBase(LuaTestBase):
    """Base class specifically for health_monitor tests."""

    @classmethod
    def _load_modules(cls):
        """Load health_monitor module."""
        cls.health_monitor = cls.lua.globals().health_monitor
