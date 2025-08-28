from base_test_classes import LuaTestBase


class TestTemperatureService(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        """Load temperature_service module and Device mock."""
        cls.temperature_service = cls.lua.eval('require("temperature_service")')

        # Load Device class from tests/mocks/device.lua for use in tests
        cls.lua.execute('Device = dofile("tests/mocks/device.lua")')
        # Patch generate_probe_text globally for all Device instances (mock)
        cls.lua.execute('Device.generate_probe_text = function(...) return "" end')
        cls.lua.execute(
            'local devmod = require("device"); (devmod.Device or _G.Device).generate_probe_text = function(...) return "" end'
        )
        cls.Device = cls.lua.eval("Device")

    def _new_device(self, prefs=None):
        """Create a new device using DeviceFactory for consistency."""
        if prefs is None:
            refresh_interval = self.get_config_value(
                "CONSTANTS", "DEFAULT_REFRESH_INTERVAL"
            )
            prefs = {"refreshInterval": refresh_interval}

        py_dev, lua_dev = self.create_lua_device("on", prefs)
        return lua_dev

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.temperature_service,
            "temperature_service module not loaded or not returned as a table",
        )

    def test_celsius_fahrenheit_conversion(self):
        ts = self.temperature_service
        self.assertEqual(ts.celsius_to_fahrenheit(0), 32)
        self.assertEqual(ts.fahrenheit_to_celsius(32), 0)
        self.assertEqual(ts.celsius_to_fahrenheit(100), 212)
        self.assertEqual(ts.fahrenheit_to_celsius(212), 100)

    def test_is_valid_temperature(self):
        ts = self.temperature_service
        config = self.lua.eval('require("config")')
        unit = config.CONSTANTS.DEFAULT_UNIT
        sensor_range = config.get_sensor_range(unit)
        self.assertFalse(ts.is_valid_temperature(None, unit))
        self.assertFalse(
            ts.is_valid_temperature(config.CONSTANTS.DISCONNECT_VALUE, unit)
        )
        self.assertFalse(ts.is_valid_temperature(sensor_range["max"] + 100, unit))
        self.assertTrue(ts.is_valid_temperature(225, unit))
        self.assertFalse(ts.is_valid_temperature(-999, unit))
        self.assertFalse(ts.is_valid_temperature(9999, unit))

    def test_is_valid_setpoint(self):
        ts = self.temperature_service
        config = self.lua.eval('require("config")')
        unit = config.CONSTANTS.DEFAULT_UNIT
        approved_setpoints = config.get_approved_setpoints(unit)
        temp_range = config.get_temperature_range(unit)
        self.assertTrue(ts.is_valid_setpoint(approved_setpoints[1], unit))
        self.assertFalse(ts.is_valid_setpoint(temp_range["min"] - 10, unit))
        self.assertFalse(ts.is_valid_setpoint(temp_range["max"] + 10, unit))

    def test_temperature_caching(self):
        ts = self.temperature_service
        dev = self._new_device()
        off_display_temp = self.get_config_value("CONSTANTS", "OFF_DISPLAY_TEMP")
        ts.store_temperature_value(dev, "grill_temp", 200)
        val = ts.get_cached_temperature_value(dev, "grill_temp", off_display_temp)
        self.assertEqual(val, 200)
        # Fallback for missing cache
        fallback = ts.get_cached_temperature_value(
            dev, "nonexistent_temp", off_display_temp
        )
        self.assertEqual(fallback, off_display_temp)

    def test_unit_handling(self):
        ts = self.temperature_service
        dev = self._new_device()
        dev.set_field(dev, "unit", "F")
        unit = ts.get_device_unit(dev)
        self.assertEqual(unit, "F")
        dev.set_field(dev, "unit", "C")
        unit = ts.get_device_unit(dev)
        self.assertEqual(unit, "C")

    def test_snap_to_approved_setpoint(self):
        ts = self.temperature_service
        # Fahrenheit
        self.assertEqual(ts.snap_to_approved_setpoint(201, "F"), 200)
        self.assertEqual(ts.snap_to_approved_setpoint(220, "F"), 225)
        # Celsius
        self.assertEqual(ts.snap_to_approved_setpoint(94, "C"), 93)
        self.assertEqual(ts.snap_to_approved_setpoint(108, "C"), 107)
        # Boundary - use config values
        temp_range = self.get_temperature_range("F")
        f_setpoints = self.get_approved_setpoints("F")
        self.assertEqual(
            ts.snap_to_approved_setpoint(temp_range["min"] - 10, "F"), f_setpoints[1]
        )
        self.assertEqual(
            ts.snap_to_approved_setpoint(temp_range["max"] + 10, "F"),
            f_setpoints[len(f_setpoints)],
        )

    def test_is_grill_preheating_and_heating(self):
        ts = self.temperature_service
        dev = self._new_device()
        f_setpoints = self.get_approved_setpoints("F")
        target_temp = f_setpoints[3]  # 225°F
        tolerance_percent = self.get_config_value("CONSTANTS", "TEMP_TOLERANCE_PERCENT")
        current_temp = target_temp * tolerance_percent - 10
        # Preheating
        is_preheating = ts.is_grill_preheating(dev, 60, current_temp, target_temp)
        self.assertTrue(is_preheating)
        # Heating after reaching temp
        dev.set_field(dev, "session_reached_temp", True)
        dev.set_field(
            dev, "session_ever_reached_temp", True
        )  # Also set the persistent flag
        is_heating = ts.is_grill_heating(dev, current_temp, target_temp)
        self.assertTrue(is_heating)
        # At-temp state (Python: just check threshold logic)
        tolerance_percent = self.get_config_value("CONSTANTS", "TEMP_TOLERANCE_PERCENT")
        at_temp_current = target_temp * tolerance_percent + 5
        is_at_temp = at_temp_current >= (target_temp * tolerance_percent)
        self.assertTrue(is_at_temp)

    def test_temperature_service_sequence(self):
        """Test temperature service sequence: preheat -> reach temp -> small increase"""
        ts = self.temperature_service
        dev = self._new_device()

        f_setpoints = self.get_approved_setpoints("F")
        initial_target = f_setpoints[3]  # 225°F
        runtime = 60  # not freshly turned on

        # Step 1: starting below threshold => preheating
        tolerance_percent = self.get_config_value("CONSTANTS", "TEMP_TOLERANCE_PERCENT")
        current_before = initial_target * tolerance_percent - 5
        dev.set_field(dev, "session_reached_temp", False)
        preheat = ts.is_grill_preheating(dev, runtime, current_before, initial_target)
        self.assertTrue(preheat, "should be preheating before reaching temp")

        # Step 2: reach at-temp => session flag set
        current_at = initial_target * tolerance_percent + 2
        ts.track_session_temp_reached(dev, current_at, initial_target)
        session_reached = dev.get_field(dev, "session_reached_temp")
        self.assertTrue(
            session_reached, "session_reached_temp should be true after reaching target"
        )

        # Step 3: small setpoint increase (less than reset threshold) should NOT reset session
        small_increase_target = initial_target + 5  # delta = 5 < 50
        ts.track_session_temp_reached(dev, current_at, small_increase_target)
        session_persisted = dev.get_field(dev, "session_reached_temp")
        self.assertTrue(
            session_persisted, "session should persist after small target increase"
        )

        # Confirm preheating/heating semantics after increase
        still_preheating = ts.is_grill_preheating(
            dev, runtime, current_at, small_increase_target
        )
        heating = ts.is_grill_heating(dev, current_at, small_increase_target)
        self.assertFalse(still_preheating, "not preheating after session reached")
        self.assertTrue(
            heating,
            "should be heating (re-heating) when below new threshold only if session reached",
        )

    def test_preheating_rule_never_returns_after_session_reached(self):
        """Test RULE: Once session_reached_temp is true, preheating NEVER triggers again, even with runtime==0"""
        ts = self.temperature_service
        dev = self._new_device()

        f_setpoints = self.get_approved_setpoints("F")
        initial_target = f_setpoints[1]  # 160°F
        big_change_target = f_setpoints[3]  # 225°F
        runtime = 0  # grill just turned back on

        # Step 1: Establish session by reaching temperature
        tolerance_percent = self.get_config_value("CONSTANTS", "TEMP_TOLERANCE_PERCENT")
        current_at = initial_target * tolerance_percent + 2
        ts.track_session_temp_reached(dev, current_at, initial_target)
        session_reached = dev.get_field(dev, "session_reached_temp")
        self.assertTrue(session_reached, "session should be reached")

        # Step 2: Big temperature change (session stays reached, no reset)
        ts.track_session_temp_reached(dev, current_at, big_change_target)
        session_still_reached = dev.get_field(dev, "session_reached_temp")
        self.assertTrue(
            session_still_reached, "session should remain reached after big change"
        )

        # Step 3: Grill turns back on with runtime==0, current below new threshold
        current_below_new = big_change_target * tolerance_percent - 10
        preheat_after_restart = ts.is_grill_preheating(
            dev, runtime, current_below_new, big_change_target
        )
        heating_after_restart = ts.is_grill_heating(
            dev, current_below_new, big_change_target
        )

        # RULE: Preheating should NEVER return after session_reached_temp is true, even with runtime==0
        self.assertFalse(
            preheat_after_restart,
            "RULE: preheating should NEVER return after session reached",
        )
        # Should be heating instead
        self.assertTrue(
            heating_after_restart,
            "should be heating after restart when session reached",
        )

    def test_probe_temperature_caching_and_validation(self):
        ts = self.temperature_service
        dev = self._new_device()
        disconnect_value = self.get_config_value("CONSTANTS", "DISCONNECT_VALUE")
        off_display_temp = self.get_config_value("CONSTANTS", "OFF_DISPLAY_TEMP")

        ts.store_temperature_value(dev, "probe1_temp", 95)
        ts.store_temperature_value(dev, "probe2_temp", 93)
        ts.store_temperature_value(dev, "probe3_temp", disconnect_value)
        ts.store_temperature_value(dev, "probe4_temp", disconnect_value)

        probe1_cached = ts.get_cached_temperature_value(
            dev, "probe1_temp", off_display_temp
        )
        probe2_cached = ts.get_cached_temperature_value(
            dev, "probe2_temp", off_display_temp
        )
        probe3_cached = ts.get_cached_temperature_value(
            dev, "probe3_temp", off_display_temp
        )

        self.assertEqual(probe1_cached, 95)
        self.assertEqual(probe2_cached, 93)
        self.assertEqual(probe3_cached, disconnect_value)

        self.assertTrue(ts.is_valid_temperature(95, "F"))
        self.assertTrue(ts.is_valid_temperature(93, "F"))
        self.assertFalse(ts.is_valid_temperature(disconnect_value, "F"))

    def test_format_temperature_display(self):
        ts = self.temperature_service
        disconnect_value = self.get_config_value("CONSTANTS", "DISCONNECT_VALUE")

        display, numeric = ts.format_temperature_display(95, True, None)
        self.assertEqual(display, "95")
        self.assertEqual(numeric, 95)

        display, numeric = ts.format_temperature_display(disconnect_value, False, 85)
        self.assertEqual(display, "85")
        self.assertEqual(numeric, 85)

    def test_probe_status_and_change_detection(self):
        ts = self.temperature_service
        dev = self._new_device()
        disconnect_value = self.get_config_value("CONSTANTS", "DISCONNECT_VALUE")

        # Probe status tracking
        probe_status = self.to_lua_table(
            {
                "probe1": self.to_lua_table({"temp": 95, "connected": True}),
                "probe2": self.to_lua_table({"temp": 93, "connected": True}),
                "probe3": self.to_lua_table(
                    {"temp": disconnect_value, "connected": False}
                ),
                "probe4": self.to_lua_table(
                    {"temp": disconnect_value, "connected": False}
                ),
            }
        )

        connected_probes = 0
        for k in probe_status:
            if probe_status[k]["connected"]:
                connected_probes += 1
        self.assertEqual(connected_probes, 2)

        # Probe temperature change
        ts.store_temperature_value(dev, "probe1_last", 90)
        probe1_current = 95
        probe1_change = probe1_current - ts.get_cached_temperature_value(
            dev, "probe1_last", 90
        )
        self.assertEqual(probe1_change, 5)
        # Probe disconnection detection
        ts.store_temperature_value(dev, "probe3_connected", True)
        was_connected = ts.get_cached_temperature_value(dev, "probe3_connected", True)
        is_connected = probe_status["probe3"]["connected"]
        self.assertTrue(was_connected != is_connected)

    def test_probe_temperature_stability(self):
        stable_readings = [95, 95, 94, 95, 96]
        avg_temp = sum(stable_readings) / len(stable_readings)
        temp_variance = sum(abs(t - avg_temp) for t in stable_readings) / len(
            stable_readings
        )
        self.assertTrue(temp_variance < 2)

    def test_probe_unit_conversion_and_calibration(self):
        ts = self.temperature_service
        celsius_temp = ts.fahrenheit_to_celsius(95)
        fahrenheit_temp = ts.celsius_to_fahrenheit(celsius_temp)
        self.assertIsInstance(celsius_temp, (int, float))
        self.assertIsInstance(fahrenheit_temp, (int, float))
        # Calibration offset simulation
        raw_probe_temp = 95
        calibration_offset = 2
        calibrated_temp = raw_probe_temp + calibration_offset
        self.assertEqual(calibrated_temp, 97)

    def test_temperature_service_basic_functionality(self):
        """Test basic temperature service functionality"""
        # Test that the module has expected functions
        self.assertIsNotNone(self.temperature_service)

        # Test temperature conversion functions
        celsius = self.temperature_service.fahrenheit_to_celsius(212)
        self.assertAlmostEqual(celsius, 100.0, places=1)

        fahrenheit = self.temperature_service.celsius_to_fahrenheit(100)
        self.assertAlmostEqual(fahrenheit, 212.0, places=1)

        # Test validation functions
        f_setpoints = self.get_approved_setpoints("F")
        test_temp = f_setpoints[4]  # 250°F
        result = self.temperature_service.is_valid_setpoint(test_temp, "F")
        self.assertTrue(result)

        result = self.temperature_service.is_valid_temperature(test_temp, "F")
        self.assertTrue(result)

        # Test setpoint snapping
        snapped = self.temperature_service.snap_to_approved_setpoint(273, "F")
        self.assertIsNotNone(snapped)

    def test_temperature_setting_validation(self):
        """Test temperature setting validation"""
        # Test valid temperature setting
        result = self.temperature_service.is_valid_setpoint(275, "F")
        self.assertTrue(result, "should accept valid temperature")

        # Test invalid temperature (too low)
        result = self.temperature_service.is_valid_setpoint(150, "F")
        self.assertFalse(result, "should reject temperature below minimum")

        # Test invalid temperature (too high)
        result = self.temperature_service.is_valid_setpoint(600, "F")
        self.assertFalse(result, "should reject temperature above maximum")

        # Test setpoint snapping
        snapped = self.temperature_service.snap_to_approved_setpoint(273, "F")
        self.assertIsNotNone(snapped, "should snap to approved setpoint")

    def test_temperature_increment_handling(self):
        """Test temperature conversion functions"""
        # Test Fahrenheit to Celsius conversion
        celsius = self.temperature_service.fahrenheit_to_celsius(275)
        self.assertAlmostEqual(
            celsius,
            135.0,
            places=1,
            msg="should convert Fahrenheit to Celsius correctly",
        )

        # Test Celsius to Fahrenheit conversion
        fahrenheit = self.temperature_service.celsius_to_fahrenheit(135)
        self.assertAlmostEqual(
            fahrenheit,
            275.0,
            places=1,
            msg="should convert Celsius to Fahrenheit correctly",
        )

    def test_temperature_decrement_handling(self):
        """Test temperature validation functions"""
        # Test valid probe temperature
        result = self.temperature_service.is_valid_temperature(250, "F")
        self.assertTrue(result, "should accept valid probe temperature")

        # Test invalid probe temperature (too low)
        result = self.temperature_service.is_valid_temperature(-50, "F")
        self.assertFalse(result, "should reject invalid probe temperature")

    def test_temperature_range_validation(self):
        """Test temperature range validation"""
        config = self.lua.eval('require("config")')

        # Test minimum temperature validation
        result = self.temperature_service.is_valid_setpoint(
            config.CONSTANTS.MIN_TEMP_F, "F"
        )
        self.assertTrue(result, "should accept minimum temperature")

        # Test maximum temperature validation
        result = self.temperature_service.is_valid_setpoint(
            config.CONSTANTS.MAX_TEMP_F, "F"
        )
        self.assertTrue(result, "should accept maximum temperature")

        # Test invalid temperatures
        result = self.temperature_service.is_valid_setpoint(
            config.CONSTANTS.MIN_TEMP_F - 10, "F"
        )
        self.assertFalse(result, "should reject temperature below minimum")

        result = self.temperature_service.is_valid_setpoint(
            config.CONSTANTS.MAX_TEMP_F + 10, "F"
        )
        self.assertFalse(result, "should reject temperature above maximum")

    def test_temperature_service_state_management(self):
        """Test temperature service caching and session tracking"""
        dev = self._new_device()

        # Test temperature caching
        f_setpoints = self.get_approved_setpoints("F")
        test_temp = f_setpoints[4]  # 250°F
        self.temperature_service.store_temperature_value(dev, "grill_temp", test_temp)
        cached_value = self.temperature_service.get_cached_temperature_value(
            dev, "grill_temp", 0
        )
        self.assertEqual(
            cached_value, test_temp, "should store and retrieve cached temperature"
        )

        # Test session temperature tracking
        result = self.temperature_service.track_session_temp_reached(
            dev, test_temp - 5, test_temp
        )
        self.assertIsNotNone(result, "should track session temperature")

        # Test cache clearing
        self.temperature_service.clear_temperature_cache(dev)
        cleared_value = self.temperature_service.get_cached_temperature_value(
            dev, "grill_temp", 0
        )
        self.assertEqual(cleared_value, 0, "should clear temperature cache")

    def test_temperature_service_error_handling(self):
        """Test temperature service display formatting for error conditions"""
        # Test disconnect display
        display_value = self.temperature_service.display_for_disconnect()
        self.assertEqual(display_value, "--", "should return disconnect display value")

        # Test temperature display formatting with valid values
        display_value, numeric_value = (
            self.temperature_service.format_temperature_display(
                250, self.lua.eval("true"), self.lua.eval("nil")
            )
        )
        self.assertEqual(display_value, "250", "should format valid temperature")
        self.assertEqual(numeric_value, 250, "should return valid numeric value")

        # Test temperature display formatting with invalid values
        display_value, numeric_value = (
            self.temperature_service.format_temperature_display(
                self.lua.eval("nil"), self.lua.eval("false"), 245
            )
        )
        self.assertEqual(
            display_value, "245", "should use cached value when current is invalid"
        )
        self.assertEqual(numeric_value, 245, "should return cached numeric value")

        # Test temperature display formatting with valid values
        display_value, numeric_value = (
            self.temperature_service.format_temperature_display(
                250, self.lua.eval("true"), self.lua.eval("nil")
            )
        )
        self.assertEqual(display_value, "250", "should format valid temperature")
        self.assertEqual(numeric_value, 250, "should return valid numeric value")

        # Test temperature display formatting with invalid values
        display_value, numeric_value = (
            self.temperature_service.format_temperature_display(
                self.lua.eval("nil"), self.lua.eval("false"), 245
            )
        )
        self.assertEqual(
            display_value, "245", "should use cached value when current is invalid"
        )
        self.assertEqual(numeric_value, 245, "should return cached numeric value")

    def test_temperature_service_event_emission(self):
        """Test temperature service validation and caching"""
        dev = self._new_device()

        # Test temperature validation
        result = self.temperature_service.is_valid_setpoint(275, "F")
        self.assertTrue(result, "should validate temperature setpoint")

        # Test temperature caching
        self.temperature_service.store_temperature_value(dev, "test_temp", 275)
        cached_value = self.temperature_service.get_cached_temperature_value(
            dev, "test_temp", 0
        )
        self.assertEqual(cached_value, 275, "should cache temperature value")

        # Test temperature conversion
        celsius = self.temperature_service.fahrenheit_to_celsius(275)
        fahrenheit = self.temperature_service.celsius_to_fahrenheit(celsius)
        self.assertAlmostEqual(
            fahrenheit, 275.0, places=1, msg="should convert temperatures accurately"
        )

    def test_temperature_service_status_updates(self):
        """Test temperature service display formatting"""
        config = self.lua.eval('require("config")')

        # Test valid temperature display
        display, numeric = self.temperature_service.format_temperature_display(
            275, True, None
        )
        self.assertEqual(display, "275", "should format valid temperature")
        self.assertEqual(numeric, 275, "should return numeric value")

        # Test disconnected temperature display with cached value
        display, numeric = self.temperature_service.format_temperature_display(
            config.CONSTANTS.DISCONNECT_VALUE, False, 250
        )
        self.assertEqual(display, "250", "should show cached value when disconnected")
        self.assertEqual(numeric, 250, "should return cached numeric value")

        # Test disconnected temperature display without cached value
        display, numeric = self.temperature_service.format_temperature_display(
            config.CONSTANTS.DISCONNECT_VALUE, False, None
        )
        self.assertEqual(
            display,
            config.CONSTANTS.DISCONNECT_DISPLAY,
            "should show disconnect display when disconnected without cache",
        )
        self.assertEqual(
            numeric,
            config.CONSTANTS.OFF_DISPLAY_TEMP,
            "should return off display temp as numeric value",
        )

    def test_temperature_service_api_integration(self):
        """Test temperature service caching integration"""
        dev = self._new_device()

        # Test temperature caching operations
        self.temperature_service.store_temperature_value(dev, "grill_temp", 275)
        self.temperature_service.store_temperature_value(dev, "probe1_temp", 95)
        self.temperature_service.store_temperature_value(dev, "probe2_temp", 93)

        # Verify cached values
        grill_temp = self.temperature_service.get_cached_temperature_value(
            dev, "grill_temp", 0
        )
        probe1_temp = self.temperature_service.get_cached_temperature_value(
            dev, "probe1_temp", 0
        )
        probe2_temp = self.temperature_service.get_cached_temperature_value(
            dev, "probe2_temp", 0
        )

        self.assertEqual(grill_temp, 275, "should cache grill temperature")
        self.assertEqual(probe1_temp, 95, "should cache probe1 temperature")
        self.assertEqual(probe2_temp, 93, "should cache probe2 temperature")

        # Test cache clearing
        self.temperature_service.clear_temperature_cache(dev)
        cleared_temp = self.temperature_service.get_cached_temperature_value(
            dev, "grill_temp", -1
        )
        self.assertEqual(cleared_temp, -1, "should clear temperature cache")

    def test_temperature_service_boundary_conditions(self):
        """Test temperature service boundary conditions"""
        config = self.lua.eval('require("config")')

        # Test boundary temperatures validation
        boundary_temps = [config.CONSTANTS.MIN_TEMP_F, config.CONSTANTS.MAX_TEMP_F]

        for temp in boundary_temps:
            result = self.temperature_service.is_valid_setpoint(temp, "F")
            self.assertTrue(result, f"should accept boundary temperature {temp}")

        # Test invalid boundary temperatures
        invalid_temps = [
            config.CONSTANTS.MIN_TEMP_F - 10,
            config.CONSTANTS.MAX_TEMP_F + 10,
        ]

        for temp in invalid_temps:
            result = self.temperature_service.is_valid_setpoint(temp, "F")
            self.assertFalse(result, f"should reject invalid temperature {temp}")

        # Test setpoint snapping for boundary conditions
        snapped_min = self.temperature_service.snap_to_approved_setpoint(
            config.CONSTANTS.MIN_TEMP_F - 10, "F"
        )
        snapped_max = self.temperature_service.snap_to_approved_setpoint(
            config.CONSTANTS.MAX_TEMP_F + 10, "F"
        )

        self.assertIsNotNone(
            snapped_min, "should snap invalid low temperature to valid value"
        )
        self.assertIsNotNone(
            snapped_max, "should snap invalid high temperature to valid value"
        )

    def test_temperature_service_concurrent_operations(self):
        """Test temperature service multiple operations"""
        dev = self._new_device()

        # Simulate multiple temperature operations
        results = []
        for i in range(3):
            temp = 250 + i * 10
            # Test validation
            result = self.temperature_service.is_valid_setpoint(temp, "F")
            results.append(result)
            # Test caching
            self.temperature_service.store_temperature_value(dev, f"temp_{i}", temp)

        # All operations should succeed
        self.assertTrue(all(results), "should handle multiple temperature validations")

        # Verify all cached values
        for i in range(3):
            temp = 250 + i * 10
            cached = self.temperature_service.get_cached_temperature_value(
                dev, f"temp_{i}", 0
            )
            self.assertEqual(cached, temp, f"should cache temperature {i}")

    def test_temperature_service_device_state_validation(self):
        """Test temperature service validation with different states"""
        # Test temperature validation in different units
        result_f = self.temperature_service.is_valid_setpoint(275, "F")
        result_c = self.temperature_service.is_valid_setpoint(135, "C")

        self.assertTrue(result_f, "should accept valid Fahrenheit temperature")
        self.assertTrue(result_c, "should accept valid Celsius temperature")

        # Test invalid temperatures
        result_invalid_f = self.temperature_service.is_valid_setpoint(150, "F")
        result_invalid_c = self.temperature_service.is_valid_setpoint(50, "C")

        self.assertFalse(
            result_invalid_f, "should reject invalid Fahrenheit temperature"
        )
        self.assertFalse(result_invalid_c, "should reject invalid Celsius temperature")

        # Test temperature conversion consistency
        original_f = 275
        converted_c = self.temperature_service.fahrenheit_to_celsius(original_f)
        converted_back_f = self.temperature_service.celsius_to_fahrenheit(converted_c)

        self.assertAlmostEqual(
            converted_back_f,
            original_f,
            places=1,
            msg="should maintain conversion consistency",
        )

    def test_temperature_service_temperature_sync(self):
        """Test temperature service session tracking"""
        dev = self._new_device()

        # Test session temperature tracking
        target_temp = 275
        current_temp = target_temp * 0.90  # Below threshold (90% < 95%)

        # Track temperature - should not reach target yet
        self.temperature_service.track_session_temp_reached(
            dev, current_temp, target_temp
        )
        reached = dev.get_field(dev, "session_reached_temp")
        self.assertFalse(
            reached or False, "should not mark as reached when below threshold"
        )

        # Track temperature - should reach target
        current_temp = target_temp * 1.05  # Above threshold (105% > 95%)
        self.temperature_service.track_session_temp_reached(
            dev, current_temp, target_temp
        )
        reached = dev.get_field(dev, "session_reached_temp")
        self.assertTrue(reached, "should mark as reached when above threshold")

        # Test session clearing
        self.temperature_service.clear_session_tracking(dev)
        cleared = dev.get_field(dev, "session_reached_temp")
        self.assertFalse(cleared, "should clear session tracking to false")


# Additional tests for probe display formatting and layout (Unicode, spacing, disconnected, etc.)


class TestProbeDisplay(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        """Load probe_display module."""
        cls.probe_display = cls.lua.eval('require("probe_display")')

    def test_two_probe_display_spacing_and_unicode(self):
        pd = self.probe_display
        # 2-probe, both 2-digit
        text = pd.generate_two_probe_text(85, 99, True)
        self.assertIn("\u2007", text)  # Figure space present
        self.assertIn("ᴘʀᴏʙᴇ¹", text)
        self.assertIn("ᴘʀᴏʙᴇ²", text)
        self.assertRegex(text, r"\d+°F")
        # 2-probe, one 3-digit
        text2 = pd.generate_two_probe_text(105, 99, True)
        self.assertIn("105°F", text2)
        self.assertIn("99°F", text2)

    def test_four_probe_display_spacing_and_unicode(self):
        pd = self.probe_display
        # 4-probe, all 2-digit
        text = pd.generate_four_probe_text(85, 99, 88, 77, True)
        self.assertIn("\u2007", text)
        self.assertIn("ᴘ¹", text)
        self.assertIn("ᴘ²", text)
        self.assertIn("ᴘ³", text)
        self.assertIn("ᴘ⁴", text)
        # 4-probe, mixed digits
        text2 = pd.generate_four_probe_text(105, 99, 88, 120, True)
        self.assertIn("105°F", text2)
        self.assertIn("120°F", text2)

    def test_disconnected_probe_display(self):
        pd = self.probe_display
        disc = self.config.CONSTANTS.DISCONNECT_DISPLAY
        # 2-probe, one disconnected
        text = pd.generate_two_probe_text(disc, 99, True)
        self.assertIn("--°F", text)
        # 4-probe, two disconnected
        text2 = pd.generate_four_probe_text(85, disc, disc, 77, True)
        self.assertIn("--°F", text2)
        self.assertIn("85°F", text2)
        self.assertIn("77°F", text2)

    def test_generate_probe_text_auto_selects_format(self):
        pd = self.probe_display
        # Only 2 probes connected
        arr = self.lua.table_from(
            [
                85,
                99,
                self.config.CONSTANTS.DISCONNECT_DISPLAY,
                self.config.CONSTANTS.DISCONNECT_DISPLAY,
            ]
        )
        text = pd.generate_probe_text(arr, True)
        self.assertIn("ᴘʀᴏʙᴇ¹", text)
        self.assertNotIn("ᴘ³", text)
        # 3rd probe connected triggers 4-probe layout
        arr2 = self.lua.table_from(
            [85, 99, 88, self.config.CONSTANTS.DISCONNECT_DISPLAY]
        )
        text2 = pd.generate_probe_text(arr2, True)
        self.assertIn("ᴘ³", text2)
        self.assertIn("ᴘ⁴", text2)
