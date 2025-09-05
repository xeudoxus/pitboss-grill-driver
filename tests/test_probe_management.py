from base_test_classes import LuaTestBase


class TestProbeManagementLua(LuaTestBase):
    """Test probe management functionality in device_status_service module."""

    @classmethod
    def _load_modules(cls):
        # Load dependencies first
        dependencies = [
            'package.loaded["bit32"] = dofile("tests/mocks/bit32.lua")',
            'package.loaded["log"] = dofile("tests/mocks/log.lua")',
            'package.loaded["cosock"] = dofile("tests/mocks/cosock.lua")',
            'package.loaded["dkjson"] = dofile("tests/mocks/dkjson.lua")',
            'package.loaded["st.capabilities"] = dofile("tests/mocks/st/capabilities.lua")',
            'package.loaded["st.json"] = dofile("tests/mocks/st/json.lua")',
            'package.loaded["st.driver"] = dofile("tests/mocks/st/driver.lua")',
            # Real modules in topological order
            'package.loaded["config"] = dofile("src/config.lua")',
            'package.loaded["custom_capabilities"] = dofile("src/custom_capabilities.lua")',
            'package.loaded["temperature_calibration"] = dofile("src/temperature_calibration.lua")',
            'package.loaded["temperature_service"] = dofile("src/temperature_service.lua")',
            'package.loaded["panic_manager"] = dofile("src/panic_manager.lua")',
            'package.loaded["probe_display"] = dofile("src/probe_display.lua")',
            'package.loaded["device_status_service"] = dofile("src/device_status_service.lua")',
        ]
        for dep in dependencies:
            cls.lua.execute(dep)

        # Load device_status_service module - it may return a tuple
        result = cls.lua.eval('require("device_status_service")')
        if isinstance(result, tuple):
            cls.device_status_service = result[
                0
            ]  # Take the first element if it's a tuple
        else:
            cls.device_status_service = result

        cls.config = cls.lua.eval('require("config")')

    def setUp(self):
        # Create a mock device in Lua
        self.device = self.lua.eval('require("tests.mocks.st.driver")()')
        # Add preferences and profile for probe offsets
        self.device.preferences = self.lua.table_from(
            {"probe1Offset": 5, "probe2Offset": -3}
        )
        self.device.profile = self.lua.table_from(
            {
                "components": self.lua.table_from(
                    {
                        "probe1": self.lua.table_from({"id": "probe1"}),
                        "probe2": self.lua.table_from({"id": "probe2"}),
                    }
                )
            }
        )
        # Event tracking
        self.emitted_events = []
        self.emitted_component_events = []

        def emit_event(dev, event):
            self.emitted_events.append(event)

        def emit_component_event(dev, component, event):
            self.emitted_component_events.append(
                {"component": component, "event": event}
            )

        self.device.emit_event = emit_event
        self.device.emit_component_event = emit_component_event
        # Add get_field/set_field for caching
        self._fields = {}

        def get_field(dev, key):
            return self._fields.get(key)

        def set_field(dev, key, value, *args, **kwargs):
            self._fields[key] = value

        self.device.get_field = get_field
        self.device.set_field = set_field

    def test_probe_offset_and_caching(self):
        # Test 1: Probe temperature offset application
        status = self.lua.table_from(
            {
                "p1_temp": 100,
                "p2_temp": self.config.CONSTANTS.DISCONNECT_VALUE,
                "grill_temp": 225,
                "set_temp": 250,
                "is_fahrenheit": True,
            }
        )
        self.device_status_service.update_device_status(self.device, status)
        probe1_cached = self._fields.get("cached_p1_temp")
        self.assertTrue(104 <= probe1_cached <= 107)

    def test_probe_disconnection_uses_cache(self):
        # Test 2: Probe disconnection handling
        self._fields["cached_p1_temp"] = 95
        status = self.lua.table_from(
            {
                "p1_temp": self.config.CONSTANTS.DISCONNECT_VALUE,
                "p2_temp": self.config.CONSTANTS.DISCONNECT_VALUE,
                "grill_temp": 225,
                "set_temp": 250,
                "is_fahrenheit": True,
            }
        )
        self.device_status_service.update_device_status(self.device, status)
        # Debug: print all emitted events
        disconnect_display = self.config.CONSTANTS.DISCONNECT_DISPLAY
        found_probe_event = any(
            getattr(e, "name", None) == "probe"
            and disconnect_display in str(getattr(e, "value", ""))
            for e in self.emitted_events
        )
        self.assertTrue(found_probe_event)

    def test_probe_out_of_range_uses_cache(self):
        # Test 3: Probe temperature validation ranges
        sensor_range = self.config.get_sensor_range("F")
        self._fields["cached_p1_temp"] = 95
        status = self.lua.table_from(
            {
                "p1_temp": sensor_range["min"] - 10,
                "p2_temp": self.config.CONSTANTS.DISCONNECT_VALUE,
                "grill_temp": 225,
                "set_temp": 250,
                "is_fahrenheit": True,
            }
        )
        self.device_status_service.update_device_status(self.device, status)
        probe1_cached_after_invalid = self._fields.get("cached_p1_temp")
        self.assertEqual(probe1_cached_after_invalid, 95)

    def test_multiple_probe_management(self):
        # Test 4: Multiple probe management
        status = self.lua.table_from(
            {
                "p1_temp": 150,
                "p2_temp": 140,
                "grill_temp": 225,
                "set_temp": 250,
                "is_fahrenheit": True,
            }
        )
        self._fields.clear()
        self.emitted_events.clear()
        self.emitted_component_events.clear()
        self.device_status_service.update_device_status(self.device, status)
        probe1_final = self._fields.get("cached_p1_temp")
        probe2_final = self._fields.get("cached_p2_temp")
        self.assertTrue(154 <= probe1_final <= 158)
        self.assertTrue(136 <= probe2_final <= 139)
        # Unified probe display event
        probe_display_event_found = any(
            getattr(e, "name", None) == "probe"
            and str(probe1_final) in str(getattr(e, "value", ""))
            and str(probe2_final) in str(getattr(e, "value", ""))
            for e in self.emitted_events
        )
        self.assertTrue(probe_display_event_found)
        # Component events
        probe1_component_event_found = any(
            c["component"]
            and getattr(c["component"], "id", None) == "probe1"
            and getattr(c["event"], "value", None) == probe1_final
            for c in self.emitted_component_events
        )
        probe2_component_event_found = any(
            c["component"]
            and getattr(c["component"], "id", None) == "probe2"
            and getattr(c["event"], "value", None) == probe2_final
            for c in self.emitted_component_events
        )
        self.assertTrue(probe1_component_event_found)
        self.assertTrue(probe2_component_event_found)

    def test_probe_display_disconnected(self):
        # Test 6: Probe display formatting for disconnected probes
        status = self.lua.table_from(
            {
                "p1_temp": self.config.CONSTANTS.DISCONNECT_VALUE,
                "p2_temp": self.config.CONSTANTS.DISCONNECT_VALUE,
                "grill_temp": 225,
                "set_temp": 250,
                "is_fahrenheit": True,
            }
        )
        self._fields["cached_p1_temp"] = None
        self._fields["cached_p2_temp"] = None
        self.emitted_events.clear()
        self.device_status_service.update_device_status(self.device, status)
        disconnect_display_found = any(
            getattr(e, "name", None) == "probe"
            and self.config.CONSTANTS.DISCONNECT_DISPLAY in str(getattr(e, "value", ""))
            for e in self.emitted_events
        )
        self.assertTrue(disconnect_display_found)

    def test_probe3_probe4_unified_display(self):
        # Test: Probes 3&4 only appear in unified display
        status = self.lua.table_from(
            {
                "p3_temp": 120,
                "p4_temp": 130,
                "grill_temp": 225,
                "set_temp": 250,
                "is_fahrenheit": True,
            }
        )
        self.emitted_events.clear()
        self.emitted_component_events.clear()
        self.device_status_service.update_device_status(self.device, status)
        # No individual events for probe3/probe4
        future_probe_events = sum(
            1
            for e in self.emitted_events
            if getattr(e, "name", None) in ("probeC", "probeD")
        )
        self.assertEqual(future_probe_events, 0)
        # Unified display includes p3/p4
        unified_display_includes_p3_p4 = any(
            getattr(e, "name", None) == "probe"
            and "120" in str(getattr(e, "value", ""))
            and "130" in str(getattr(e, "value", ""))
            for e in self.emitted_events
        )
        self.assertTrue(unified_display_includes_p3_p4)
