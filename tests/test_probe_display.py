from base_test_classes import LuaTestBase


class TestProbeDisplayLua(LuaTestBase):
    """Test probe display text generation functionality."""

    @classmethod
    def _load_modules(cls):
        # Load dependencies first
        dependencies = [
            # Mocks and core dependencies
            'package.loaded["bit32"] = dofile("tests/mocks/bit32.lua")',
            'package.loaded["log"] = dofile("tests/mocks/log.lua")',
            'package.loaded["cosock"] = dofile("tests/mocks/cosock.lua")',
            'package.loaded["dkjson"] = dofile("tests/mocks/dkjson.lua")',
            'package.loaded["st.capabilities"] = dofile("tests/mocks/st/capabilities.lua")',
            'package.loaded["st.json"] = dofile("tests/mocks/st/json.lua")',
            'package.loaded["st.driver"] = dofile("tests/mocks/st/driver.lua")',
            # Real modules in topological order
            'package.loaded["config"] = dofile("src/config.lua")',
            'config = package.loaded["config"]',
            'package.loaded["custom_capabilities"] = dofile("src/custom_capabilities.lua")',
            'package.loaded["temperature_calibration"] = dofile("src/temperature_calibration.lua")',
            'package.loaded["temperature_service"] = dofile("src/temperature_service.lua")',
            'package.loaded["probe_display"] = dofile("src/probe_display.lua")',
        ]
        for dep in dependencies:
            cls.lua.execute(dep)

        # Load probe_display module - it may return a tuple
        result = cls.lua.eval('require("probe_display")')
        if isinstance(result, tuple):
            cls.probe_display = result[0]  # Take the first element if it's a tuple
        else:
            cls.probe_display = result

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.probe_display,
            "probe_display module not loaded or not returned as a table",
        )

    def test_generate_two_probe_text(self):
        # Use config values for disconnect
        config = self.lua.globals().config
        DISCONNECT = config.CONSTANTS.DISCONNECT_DISPLAY
        # 2-probe, both connected, Fahrenheit
        result = self.probe_display.generate_two_probe_text(123, 45, True)
        self.assertIn("123", result)
        self.assertIn("45", result)
        self.assertIn("F", result)
        # 2-probe, one disconnected
        result = self.probe_display.generate_two_probe_text(DISCONNECT, 99, True)
        self.assertIn(DISCONNECT, result)
        self.assertIn("99", result)
        # 2-probe, Celsius
        result = self.probe_display.generate_two_probe_text(12, 34, False)
        self.assertIn("12", result)
        self.assertIn("34", result)
        self.assertIn("c", result.lower())

    def test_generate_four_probe_text(self):
        config = self.lua.globals().config
        DISCONNECT = config.CONSTANTS.DISCONNECT_DISPLAY
        # 4-probe, all connected, Fahrenheit
        result = self.probe_display.generate_four_probe_text(101, 202, 303, 404, True)
        self.assertIn("101", result)
        self.assertIn("202", result)
        self.assertIn("303", result)
        self.assertIn("404", result)
        self.assertIn("F", result)
        # 4-probe, some disconnected
        result = self.probe_display.generate_four_probe_text(
            DISCONNECT, 88, DISCONNECT, 77, True
        )
        self.assertIn(DISCONNECT, result)
        self.assertIn("88", result)
        self.assertIn("77", result)

    def test_generate_probe_text_auto_select(self):
        config = self.lua.globals().config
        DISCONNECT = config.CONSTANTS.DISCONNECT_DISPLAY

        # Only 2 probes connected - create Lua table properly
        probe_temps = self.lua.eval(f'{{111, 222, "{DISCONNECT}", "{DISCONNECT}"}}')
        result = self.probe_display.generate_probe_text(probe_temps, True)
        # The output should include '111' and '222' if they are not disconnected
        self.assertIn("111", result)
        self.assertIn("222", result)

        # 3rd probe connected triggers 4-probe
        probe_temps = self.lua.eval(f'{{11, 22, 33, "{DISCONNECT}"}}')
        result = self.probe_display.generate_probe_text(probe_temps, True)
        self.assertIn("33", result)

        # 4th probe connected triggers 4-probe
        probe_temps = self.lua.eval(f'{{1, 2, "{DISCONNECT}", 4}}')
        result = self.probe_display.generate_probe_text(probe_temps, True)
        self.assertIn("4", result)

    def test_spacing_and_unicode(self):
        # Check that figure space (U+2007) is present for UI alignment
        result = self.probe_display.generate_two_probe_text(12, 34, True)
        self.assertIn("\u2007", result or result.encode("unicode_escape").decode())

    def test_format_temperature_edge_cases(self):
        # Test with 0, string, and None
        config = self.lua.globals().config
        DISCONNECT = config.CONSTANTS.DISCONNECT_DISPLAY
        # 0 should be treated as disconnected
        result = self.probe_display.generate_two_probe_text(0, 0, True)
        self.assertIn(DISCONNECT, result)
        # String input
        result = self.probe_display.generate_two_probe_text("123", "45", True)
        self.assertIn("123", result)
        self.assertIn("45", result)
        # None input
        result = self.probe_display.generate_two_probe_text(None, None, True)
        self.assertIn(DISCONNECT, result)
