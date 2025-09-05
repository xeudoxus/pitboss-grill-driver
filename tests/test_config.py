# Canonical, robust config integration test
import os
import sys

from base_test_classes import LuaTestBase

tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)


class TestConfig(LuaTestBase):
    def test_module_loaded(self):
        self.assertIsNotNone(
            self.config, "config module not loaded or not returned as a table"
        )

    def test_config_tables_and_constants(self):
        config = self.config
        # Check major tables
        self.assertIn("CONSTANTS", config)
        self.assertIn("APPROVED_SETPOINTS", config)
        self.assertIn("COMPONENTS", config)
        self.assertIn("ERROR_MESSAGES", config)
        self.assertIn("POWER_CONSTANTS", config)
        self.assertIn("VIRTUAL_DEVICES", config)
        # Check CONSTANTS fields
        constants = config["CONSTANTS"]
        self.assertIsInstance(constants, type(self.lua.table_from({})))
        for key in [
            "DEFAULT_UNIT",
            "DEFAULT_REFRESH_INTERVAL",
            "INITIAL_HEALTH_CHECK_DELAY",
            "MIN_HEALTH_CHECK_INTERVAL",
            "MAX_HEALTH_CHECK_INTERVAL",
            "REFRESH_DELAY",
            "MIN_TEMP_F",
            "MAX_TEMP_F",
            "MIN_TEMP_C",
            "MAX_TEMP_C",
            "DISCONNECT_VALUE",
            "DISCONNECT_DISPLAY",
            "OFF_DISPLAY_TEMP",
        ]:
            self.assertIn(key, constants)
        self.assertIsInstance(constants["DEFAULT_UNIT"], str)
        self.assertIsInstance(constants["DEFAULT_REFRESH_INTERVAL"], (int, float))
        self.assertIsInstance(constants["DISCONNECT_VALUE"], str)
        self.assertIsInstance(constants["OFF_DISPLAY_TEMP"], (int, float))

    def test_config_methods(self):
        config = self.config
        # Check documented config methods exist and are callable
        for method in [
            "get_temperature_range",
            "get_sensor_range",
            "get_approved_setpoints",
            "get_temp_reset_threshold",
            "get_refresh_interval",
        ]:
            self.assertIn(method, config)
            self.assertTrue(callable(config[method]))

    def test_get_temperature_range(self):
        config = self.config
        # Should return a table for both 'F' and 'C'
        for unit in ["F", "C"]:
            rng = config["get_temperature_range"](unit)
            self.assertIsInstance(rng, type(self.lua.table_from({})))
            self.assertIn("min", rng)
            self.assertIn("max", rng)

    def test_get_refresh_interval(self):
        config = self.config

        # Should return a number for a mock device with preferences
        class Dummy:
            def __init__(self):
                self.preferences = {"refreshInterval": 60}

        dummy = Dummy()
        interval = config["get_refresh_interval"](dummy)
        self.assertIsInstance(interval, (int, float))
