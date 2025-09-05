from base_test_classes import LuaTestBase


class TestTemperatureCalibration(LuaTestBase):
    """Test temperature_calibration module using standard test infrastructure."""

    @classmethod
    def setUpConfigConstants(cls):
        # These values must match src/config.lua CONSTANTS
        return {
            "REFERENCE_TEMP_F": 32,
            "REFERENCE_TEMP_C": 0,
            "THERMISTOR_BETA": 3950,
        }

    @staticmethod
    def steinhart_hart_calibration(raw_temp, offset, unit, config):
        import math

        if raw_temp is None or not isinstance(raw_temp, (int, float)):
            return raw_temp
        if not offset or offset == 0:
            return raw_temp

        if unit == "F":
            reference_temp = config["REFERENCE_TEMP_F"]
            temp_k = (raw_temp - 32) * 5 / 9 + 273.15
            ref_k = (reference_temp - 32) * 5 / 9 + 273.15
            offset_k = offset * 5 / 9
        else:
            reference_temp = config["REFERENCE_TEMP_C"]
            temp_k = raw_temp + 273.15
            ref_k = reference_temp + 273.15
            offset_k = offset

        temp_diff_from_ref = abs(temp_k - ref_k)
        beta_factor = config["THERMISTOR_BETA"] / 1000
        scaling_factor = 1 + (temp_diff_from_ref * beta_factor / 1000)
        calibrated_temp_k = temp_k + (offset_k * scaling_factor)

        if unit == "F":
            calibrated_temp = math.ceil((calibrated_temp_k - 273.15) * 9 / 5 + 32)
        else:
            calibrated_temp = math.ceil(calibrated_temp_k - 273.15)
        return calibrated_temp

    @classmethod
    def _load_modules(cls):
        # Load dependencies first
        dependencies = [
            'package.loaded["cosock"] = dofile("tests/mocks/cosock.lua")',
            'package.loaded["dkjson"] = dofile("tests/mocks/dkjson.lua")',
            'package.loaded["st.capabilities"] = dofile("tests/mocks/st/capabilities.lua")',
            'package.loaded["st.json"] = dofile("tests/mocks/st/json.lua")',
            'package.loaded["st.driver"] = dofile("tests/mocks/st/driver.lua")',
            # Real modules in topological order
            'package.loaded["config"] = dofile("src/config.lua")',
            'package.loaded["custom_capabilities"] = dofile("src/custom_capabilities.lua")',
            'package.loaded["temperature_calibration"] = dofile("src/temperature_calibration.lua")',
        ]
        for dep in dependencies:
            cls.lua.execute(dep)

        # Load temperature_calibration module - it may return a tuple
        result = cls.lua.eval('require("temperature_calibration")')
        if isinstance(result, tuple):
            cls.temperature_calibration = result[
                0
            ]  # Take the first element if it's a tuple
        else:
            cls.temperature_calibration = result

    def test_module_loaded(self):
        """Test that the Lua module is loaded correctly."""
        self.assertIsNotNone(
            self.temperature_calibration,
            "temperature_calibration module not loaded or not returned as a table",
        )
        self.assertTrue(
            hasattr(self.temperature_calibration, "apply_calibration"),
            "Function 'apply_calibration' not found in module.",
        )

    def test_apply_calibration_no_offset(self):
        """Test that a zero offset results in no temperature change."""
        original_temp = 225
        offset = 0
        calibrated_temp = self.temperature_calibration.apply_calibration(
            original_temp, offset, "F", "grill"
        )
        self.assertAlmostEqual(original_temp, calibrated_temp, places=1)

    def test_apply_calibration_negative_offset_fahrenheit(self):
        """Test a negative offset (probe reads high) in Fahrenheit, verifying non-linear correction."""
        config = self.setUpConfigConstants()
        offset = -3
        low_temp_reading = 35
        calibrated_low = self.temperature_calibration.apply_calibration(
            low_temp_reading, offset, "F", "grill"
        )
        expected_low = self.steinhart_hart_calibration(
            low_temp_reading, offset, "F", config
        )
        self.assertAlmostEqual(
            calibrated_low,
            expected_low,
            delta=0.5,
            msg=f"Expected {expected_low}, got {calibrated_low}",
        )

        high_temp_reading = 400
        calibrated_high = self.temperature_calibration.apply_calibration(
            high_temp_reading, offset, "F", "grill"
        )
        expected_high = self.steinhart_hart_calibration(
            high_temp_reading, offset, "F", config
        )
        self.assertAlmostEqual(
            calibrated_high,
            expected_high,
            delta=1.0,
            msg=f"Expected {expected_high}, got {calibrated_high}",
        )

    def test_apply_calibration_positive_offset_fahrenheit(self):
        """Test a positive offset (probe reads low) in Fahrenheit, verifying non-linear correction."""
        config = self.setUpConfigConstants()
        offset = 2
        low_temp_reading = 30
        calibrated_low = self.temperature_calibration.apply_calibration(
            low_temp_reading, offset, "F", "grill"
        )
        expected_low = self.steinhart_hart_calibration(
            low_temp_reading, offset, "F", config
        )
        self.assertAlmostEqual(
            calibrated_low,
            expected_low,
            delta=0.5,
            msg=f"Expected {expected_low}, got {calibrated_low}",
        )

        high_temp_reading = 400
        calibrated_high = self.temperature_calibration.apply_calibration(
            high_temp_reading, offset, "F", "grill"
        )
        expected_high = self.steinhart_hart_calibration(
            high_temp_reading, offset, "F", config
        )
        self.assertAlmostEqual(
            calibrated_high,
            expected_high,
            delta=1.0,
            msg=f"Expected {expected_high}, got {calibrated_high}",
        )

    def test_graceful_handling_of_invalid_input(self):
        """Test that the function handles nil or non-numeric input gracefully."""
        # Should return the original value if it's not a number.
        self.assertEqual(
            self.temperature_calibration.apply_calibration(
                "not a number", -5, "F", "grill"
            ),
            "not a number",
        )
        # Should handle nil input without error.
        self.assertIsNone(
            self.temperature_calibration.apply_calibration(None, -5, "F", "grill")
        )
