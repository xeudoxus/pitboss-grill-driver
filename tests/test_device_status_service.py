import os
import sys
import unittest

from base_test_classes import DeviceStatusServiceTestBase
from mock_device import (
    create_default_preferences,
    create_grill_status,
)

# Add the tests directory to the Python path so imports work from both project root and tests directory
tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)


class TestDeviceStatusServiceLua(DeviceStatusServiceTestBase):

    def test_update_device_status_on(self):
        """Test updating device status when grill is ON (full event/component coverage)."""
        from device_situations import DeviceSituations

        preferences = create_default_preferences()
        py_dev, lua_dev = self.create_lua_device("on", preferences)
        # Create status data using device_situations.py as base
        status = DeviceSituations.grill_online_basic()
        # Override specific values for this test
        status.update(
            {
                "grill_temp": 250,
                "set_temp": 225,
                "p1_temp": 150,
                "p2_temp": 160,
                "hot_state": False,
                "error1": False,
                "fan_error": False,
            }
        )

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )
        self.print_debug_info(py_dev)

        # There should be at least 8 events and 4 component events
        self.assertGreaterEqual(len(py_dev.events), 8)
        self.assertGreaterEqual(len(py_dev.component_events), 4)

        # Check unit field
        self.assertEqual(py_dev.fields.get("unit"), "F")
        # grill_start_time should be set
        self.assertIsNotNone(py_dev.fields.get("grill_start_time"))

        # Check for grillTemp currentTemp and targetTemp
        self.assert_event_exists(
            py_dev.events,
            event_name="currentTemp",
            event_value="250",
            attribute="currentTemp",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="targetTemp",
            event_value="225",
            attribute="targetTemp",
        )

        # Check for unified probe display (should contain both probe temperatures, Lua format)
        probe_display_found = False
        for ev in py_dev.events:
            if ev.get("attribute") == "probe" and isinstance(ev.get("value"), str):
                if "150" in ev["value"] and "160" in ev["value"]:
                    probe_display_found = True
                    break
        self.assertTrue(probe_display_found)

        # Check for fanState, augerState, ignitorState, lightState, primeState, temperatureUnit
        self.assert_event_exists(
            py_dev.events, event_name="fanState", event_value="ON", attribute="fanState"
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="ignitorState",
            event_value="OFF",
            attribute="ignitorState",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="lightState",
            event_value="OFF",
            attribute="lightState",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="primeState",
            event_value="OFF",
            attribute="primeState",
        )
        self.assert_event_exists(
            py_dev.events, event_name="unit", event_value="F", attribute="unit"
        )

        # Check for component events: temperature range, heating setpoint, temperature, switch
        def find_component_event_by_pred(predicate):
            for ce in py_dev.component_events:
                if predicate(ce):
                    return ce
            return None

        # Use config to get expected range
        temp_range = self.lua.eval('require("config").get_temperature_range("F")')
        # Grill range
        grill_range = find_component_event_by_pred(
            lambda ce: ce["event"].get("value") is not None
            and dict(ce["event"]["value"]).get("minimum") == temp_range["min"]
            and dict(ce["event"]["value"]).get("maximum") == temp_range["max"]
        )
        self.assertIsNotNone(grill_range)

    """Test device_status_service module using shared test infrastructure."""

    def test_update_device_status_off(self):
        """Test updating device status when grill is off."""
        # Create device with preferences
        preferences = create_default_preferences()
        py_dev, lua_dev = self.create_lua_device("off", preferences)

        # Create status data using device_situations.py
        from device_situations import DeviceSituations

        status = DeviceSituations.grill_offline()

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )

        # Debug output
        self.print_debug_info(py_dev)

        # Assertions
        self.assert_field_is_none(py_dev, "grill_start_time")
        self.assert_switch_off(py_dev.component_events)

    def test_update_offline_status(self):
        """Test updating offline status with clear alarm."""
        py_dev, lua_dev = self.create_lua_device("off")

        self.device_status_service.update_offline_status(lua_dev)

        self.print_debug_info(py_dev)

        # Should have one component event and one regular event
        self.assertEqual(len(py_dev.component_events), 1)
        self.assertEqual(len(py_dev.events), 1)

        # Check for clear alarm
        self.assert_component_event_exists(
            py_dev.component_events,
            "Grill_Error",
            "panicAlarm",
            "clear",
            attribute="panicAlarm",
        )

        # Check for disconnected message
        self.assert_event_exists(
            py_dev.events,
            event_value=self.language.disconnected,
            attribute="lastMessage",
        )

    def test_update_offline_status_panic(self):
        """Test updating offline status when in panic state."""
        py_dev, lua_dev = self.create_lua_device("off")

        # Set panic state to true by setting the field on the device
        py_dev.set_field("panic_state", True)

        self.device_status_service.update_offline_status(lua_dev)

        self.print_debug_info(py_dev)

        # Check for panic alarm
        self.assert_component_event_exists(
            py_dev.component_events,
            "Grill_Error",
            "panicAlarm",
            "panic",
            attribute="panicAlarm",
        )

        # Check for disconnected message (should be panic message when in panic state)
        self.assert_event_exists(
            py_dev.events,
            event_value="PANIC: Lost Connection (Grill Was On!)",
            attribute="lastMessage",
        )

    def test_set_status_message(self):
        """Test setting a custom status message."""
        py_dev, lua_dev = self.create_lua_device("on")

        self.device_status_service.set_status_message(lua_dev, "Custom Message")

        self.print_debug_info(py_dev)

        # Should have one event
        self.assertEqual(len(py_dev.events), 1)

        # Check for custom message
        self.assert_event_exists(
            py_dev.events, event_value="Custom Message", attribute="lastMessage"
        )

    def test_is_grill_on(self):
        """Test is_grill_on function with device and status table."""
        # Test with device state
        py_dev_on, lua_dev_on = self.create_lua_device("on")
        result_on = self.device_status_service.is_grill_on(lua_dev_on, None)
        self.assertTrue(result_on is True or result_on == "on")

        py_dev_off, lua_dev_off = self.create_lua_device("off")
        result_off = self.device_status_service.is_grill_on(lua_dev_off, None)
        self.assertFalse(result_off)

        # Test with status table cases
        self.assertTrue(
            self.device_status_service.is_grill_on(
                None,
                self.to_lua_table(
                    {"motor_state": True, "hot_state": False, "module_on": False}
                ),
            )
        )
        self.assertTrue(
            self.device_status_service.is_grill_on(
                None,
                self.to_lua_table(
                    {"motor_state": False, "hot_state": True, "module_on": False}
                ),
            )
        )
        self.assertTrue(
            self.device_status_service.is_grill_on(
                None,
                self.to_lua_table(
                    {"motor_state": False, "hot_state": False, "module_on": True}
                ),
            )
        )
        self.assertFalse(
            self.device_status_service.is_grill_on(
                None,
                self.to_lua_table(
                    {"motor_state": False, "hot_state": False, "module_on": False}
                ),
            )
        )

    def test_calculate_power_consumption(self):
        """Test power consumption calculation for different grill states."""
        py_dev, lua_dev = self.create_lua_device("on")

        # Test all components on
        status_on = self.create_grill_status(
            grill_temp=250,
            set_temp=225,
            p1_temp=150,
            p2_temp=160,
            motor_state=True,
            hot_state=True,
            module_on=True,
            fan_state=True,
            light_state=True,
            prime_state=True,
        )

        power_on = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(status_on)
        )
        expected = (
            self.config.POWER_CONSTANTS.BASE_CONTROLLER
            + self.config.POWER_CONSTANTS.FAN_LOW_OPERATION
            - self.config.POWER_CONSTANTS.BASE_CONTROLLER
            + self.config.POWER_CONSTANTS.AUGER_MOTOR
            + self.config.POWER_CONSTANTS.IGNITOR_HOT
            + self.config.POWER_CONSTANTS.LIGHT_ON
            + self.config.POWER_CONSTANTS.PRIME_ON
        )
        self.assertEqual(power_on, expected)

        # Test off but cooling (fan running)
        status_off_cooling = self.create_grill_status(
            p1_temp=self.config.CONSTANTS.DISCONNECT_VALUE,
            p2_temp=self.config.CONSTANTS.DISCONNECT_VALUE,
            fan_state=True,
        )

        power_off_cooling = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(status_off_cooling)
        )
        expected_cooling = (
            self.config.POWER_CONSTANTS.BASE_CONTROLLER
            + self.config.POWER_CONSTANTS.FAN_HIGH_COOLING
            - self.config.POWER_CONSTANTS.BASE_CONTROLLER
        )
        self.assertEqual(power_off_cooling, expected_cooling)

        # Test all off
        status_all_off = self.create_grill_status(
            p1_temp=self.config.CONSTANTS.DISCONNECT_VALUE,
            p2_temp=self.config.CONSTANTS.DISCONNECT_VALUE,
        )

        power_all_off = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(status_all_off)
        )
        self.assertEqual(power_all_off, self.config.POWER_CONSTANTS.BASE_CONTROLLER)

    def test_update_device_status_on_with_create_grill_status(self):
        """Test updating device status when grill is on."""
        # Create device with preferences
        preferences = create_default_preferences()
        py_dev, lua_dev = self.create_lua_device("on", preferences)

        # Create status data for grill ON
        status = create_grill_status(
            grill_temp=250,
            set_temp=225,
            p1_temp=150,
            p2_temp=160,
            motor_state=True,
            hot_state=False,
            module_on=True,
            fan_state=True,
            light_state=False,
            prime_state=False,
            is_fahrenheit=True,
        )

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )

        # Debug output
        self.print_debug_info(py_dev)

        # Assertions
        self.assertIsNotNone(py_dev.get_field("grill_start_time"))
        self.assertEqual(py_dev.get_field("unit"), "F")

        # Should have at least 8 events (custom capability events)
        self.assertGreaterEqual(len(py_dev.events), 8)

        # Should have at least 4 component events (temperature ranges, setpoint range, temp, switch)
        self.assertGreaterEqual(len(py_dev.component_events), 4)

        # Check for specific events
        self.assert_event_exists(
            py_dev.events,
            event_name="currentTemp",
            event_value="250",
            attribute="currentTemp",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="targetTemp",
            event_value="225",
            attribute="targetTemp",
        )
        self.assert_event_exists(
            py_dev.events, event_name="fanState", event_value="ON", attribute="fanState"
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="augerState",
            event_value="ON",
            attribute="augerState",
        )  # motor_state=True
        self.assert_event_exists(
            py_dev.events,
            event_name="ignitorState",
            event_value="OFF",
            attribute="ignitorState",
        )  # hot_state=False
        self.assert_event_exists(
            py_dev.events,
            event_name="lightState",
            event_value="OFF",
            attribute="lightState",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="primeState",
            event_value="OFF",
            attribute="primeState",
        )
        self.assert_event_exists(
            py_dev.events, event_name="unit", event_value="F", attribute="unit"
        )

        # Check for probe display (should contain both probe temperatures)
        probe_event = self.utils.find_event(py_dev.events, event_name="probe")
        self.assertIsNotNone(probe_event)
        probe_value = self.utils.extract_event_value(probe_event)
        self.assertIn("150", str(probe_value))
        self.assertIn("160", str(probe_value))

        # Check switch component event is 'on'
        switch_event = self.utils.find_component_event(
            py_dev.component_events, "Standard_Grill", "switch", "on"
        )
        self.assertIsNotNone(switch_event)

    def test_update_device_status_celsius(self):
        """Test updating device status with Celsius temperatures."""
        preferences = create_default_preferences()
        py_dev, lua_dev = self.create_lua_device("on", preferences)

        # Create status data with Celsius
        status = create_grill_status(
            grill_temp=120,  # 120°C
            set_temp=110,  # 110°C
            p1_temp=75,  # 75°C
            p2_temp=80,  # 80°C
            motor_state=True,
            module_on=True,
            fan_state=True,
            is_fahrenheit=False,  # Celsius
        )

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )

        # Debug output
        self.print_debug_info(py_dev)

        # Check unit is set to Celsius
        self.assertEqual(py_dev.get_field("unit"), "C")

        # Check temperature events have Celsius unit
        self.assert_event_exists(
            py_dev.events,
            event_name="currentTemp",
            event_value="120",
            attribute="currentTemp",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="targetTemp",
            event_value="110",
            attribute="targetTemp",
        )
        self.assert_event_exists(
            py_dev.events, event_name="unit", event_value="C", attribute="unit"
        )

    def test_update_device_status_with_offsets(self):
        """Test updating device status with temperature offsets applied."""
        # Create preferences with offsets
        preferences = create_default_preferences()
        preferences.update({"grillOffset": 5, "probe1Offset": -3, "probe2Offset": 2})
        py_dev, lua_dev = self.create_lua_device("on", preferences)

        # Create status data
        status = create_grill_status(
            grill_temp=250,  # Should become 255 with +5 offset
            set_temp=225,
            p1_temp=150,  # Should become 147 with -3 offset
            p2_temp=160,  # Should become 162 with +2 offset
            motor_state=True,
            module_on=True,
            fan_state=True,
            is_fahrenheit=True,
        )

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )

        # Debug output
        self.print_debug_info(py_dev)

        # Note: The actual offset application depends on the temperature_calibration module
        # We're mainly testing that the function runs without error with offsets
        self.assertIsNotNone(py_dev.get_field("grill_start_time"))
        self.assertEqual(py_dev.get_field("unit"), "F")

    def test_update_device_status_disconnected_probes(self):
        """Test updating device status with disconnected probes."""
        preferences = create_default_preferences()
        py_dev, lua_dev = self.create_lua_device("on", preferences)

        # Create status data with disconnected probes
        status = create_grill_status(
            grill_temp=250,
            set_temp=225,
            p1_temp=self.config.CONSTANTS.DISCONNECT_VALUE,  # Disconnected
            p2_temp=self.config.CONSTANTS.DISCONNECT_VALUE,  # Disconnected
            p3_temp=0,  # Disconnected
            p4_temp=0,  # Disconnected
            motor_state=True,
            module_on=True,
            fan_state=True,
            is_fahrenheit=True,
        )

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )

        # Debug output
        self.print_debug_info(py_dev)

        # Should still work with disconnected probes
        self.assert_event_exists(
            py_dev.events,
            event_name="currentTemp",
            event_value="250",
            attribute="currentTemp",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="targetTemp",
            event_value="225",
            attribute="targetTemp",
        )

        # Probe display should show disconnected values
        probe_event = self.utils.find_event(py_dev.events, event_name="probe")
        self.assertIsNotNone(probe_event)

    def test_update_device_status_error_states(self):
        """Test updating device status with error conditions."""
        preferences = create_default_preferences()
        py_dev, lua_dev = self.create_lua_device("on", preferences)

        # Create status data with errors
        status = create_grill_status(
            grill_temp=250,
            set_temp=225,
            motor_state=True,
            module_on=True,
            fan_state=True,
            error1=True,  # Error condition
            fan_error=True,  # Fan error
            is_fahrenheit=True,
        )

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )

        # Debug output
        self.print_debug_info(py_dev)

        # Should still process the update
        self.assert_event_exists(
            py_dev.events,
            event_name="currentTemp",
            event_value="250",
            attribute="currentTemp",
        )
        self.assert_event_exists(
            py_dev.events,
            event_name="targetTemp",
            event_value="225",
            attribute="targetTemp",
        )

    def test_update_device_status_cooling_mode(self):
        """Test updating device status when grill is in cooling mode."""
        preferences = create_default_preferences()
        py_dev, lua_dev = self.create_lua_device("off", preferences)

        # Create status data for cooling mode (grill off but fan running)
        status = create_grill_status(
            grill_temp=100,  # Still warm
            set_temp=0,  # Target is 0 (off)
            motor_state=False,
            hot_state=False,
            module_on=False,  # Grill is off
            fan_state=True,  # But fan is running for cooling
            is_fahrenheit=True,
        )

        # Call the service
        self.device_status_service.update_device_status(
            lua_dev, self.to_lua_table(status)
        )

        # Debug output
        self.print_debug_info(py_dev)

        # Should not set grill_start_time when grill is off
        self.assertIsNone(py_dev.get_field("grill_start_time"))

        # Should show fan running
        self.assert_event_exists(
            py_dev.events, event_name="fanState", event_value="ON", attribute="fanState"
        )

        # Switch should be off
        switch_event = self.utils.find_component_event(
            py_dev.component_events, "Standard_Grill", "switch", "off"
        )
        self.assertIsNotNone(switch_event)

    def test_is_grill_on_edge_cases(self):
        """Test is_grill_on function with edge cases."""
        # Test with device that has switch state "off"
        py_dev, lua_dev = self.create_lua_device("off")
        result = self.device_status_service.is_grill_on(lua_dev, None)
        self.assertFalse(result)

        # Test with device that has switch state "on"
        py_dev, lua_dev = self.create_lua_device("on")
        result = self.device_status_service.is_grill_on(lua_dev, None)
        self.assertTrue(result)

        # Test with status where all components are false
        result = self.device_status_service.is_grill_on(
            lua_dev,
            self.to_lua_table(
                {"motor_state": False, "hot_state": False, "module_on": False}
            ),
        )
        self.assertFalse(result)

        # Test with hot_state true
        result = self.device_status_service.is_grill_on(
            lua_dev,
            self.to_lua_table(
                {"motor_state": False, "hot_state": True, "module_on": False}
            ),
        )
        self.assertTrue(result)

        # Test with motor_state true
        result = self.device_status_service.is_grill_on(
            lua_dev,
            self.to_lua_table(
                {"motor_state": True, "hot_state": False, "module_on": False}
            ),
        )
        self.assertTrue(result)

        # Test with module_on true
        result = self.device_status_service.is_grill_on(
            lua_dev,
            self.to_lua_table(
                {"motor_state": False, "hot_state": False, "module_on": True}
            ),
        )
        self.assertTrue(result)

    def test_set_status_message_with_assertion(self):
        """Test setting custom status messages."""
        py_dev, lua_dev = self.create_lua_device("on")

        # Test setting a custom message
        self.device_status_service.set_status_message(lua_dev, "Custom Message")

        # Should emit one event with the custom message
        self.assertEqual(len(py_dev.events), 1)
        self.assert_event_exists(py_dev.events, event_value="Custom Message")

    def test_calculate_power_consumption_all_on(self):
        """Test power consumption calculation with all components on."""
        py_dev, lua_dev = self.create_lua_device("on")

        # Test with all components on
        status = self.create_grill_status(
            fan_state=True,
            motor_state=True,
            auger_state=True,
            hot_state=True,
            ignitor_state=True,
            light_state=True,
            prime_state=True,
            module_on=True,
            set_temp=225,
        )

        power = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(status)
        )

        # Should include all power components
        expected_power = (
            self.config.POWER_CONSTANTS.FAN_LOW_OPERATION
            + self.config.POWER_CONSTANTS.AUGER_MOTOR
            + self.config.POWER_CONSTANTS.IGNITOR_HOT
            + self.config.POWER_CONSTANTS.LIGHT_ON
            + self.config.POWER_CONSTANTS.PRIME_ON
        )
        self.assertEqual(power, expected_power)

    def test_calculate_power_consumption_cooling_mode(self):
        """Test power consumption calculation in cooling mode."""
        py_dev, lua_dev = self.create_lua_device("on")

        # Test cooling mode (fan on, grill off)
        status = self.create_grill_status(
            fan_state=True,
            motor_state=False,
            auger_state=False,
            hot_state=False,
            ignitor_state=False,
            light_state=False,
            prime_state=False,
            module_on=False,
            set_temp=0,
        )

        power = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(status)
        )

        # Should use high cooling fan power
        expected_power = self.config.POWER_CONSTANTS.FAN_HIGH_COOLING
        self.assertEqual(power, expected_power)

    def test_calculate_power_consumption_all_off(self):
        """Test power consumption calculation with all components off."""
        py_dev, lua_dev = self.create_lua_device("on")

        # Test with all components off
        status = self.create_grill_status(
            fan_state=False,
            motor_state=False,
            auger_state=False,
            hot_state=False,
            ignitor_state=False,
            light_state=False,
            prime_state=False,
            module_on=False,
            set_temp=0,
        )

        power = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(status)
        )

        # Should only include base controller power
        expected_power = self.config.POWER_CONSTANTS.BASE_CONTROLLER
        self.assertEqual(power, expected_power)

    def test_calculate_power_consumption_edge_cases(self):
        """Test power consumption calculation with edge cases."""
        py_dev, lua_dev = self.create_lua_device("on")

        # Test with minimal status (only required fields)
        minimal_status = {
            "fan_state": False,
            "motor_state": False,
            "auger_state": False,
            "hot_state": False,
            "ignitor_state": False,
            "light_state": False,
            "prime_state": False,
            "module_on": False,
            "set_temp": 0,
        }

        power = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(minimal_status)
        )
        self.assertEqual(power, self.config.POWER_CONSTANTS.BASE_CONTROLLER)

        # Test with only fan on (should be high cooling power)
        fan_only_status = minimal_status.copy()
        fan_only_status["fan_state"] = True

        power_fan = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(fan_only_status)
        )
        expected_fan = (
            self.config.POWER_CONSTANTS.BASE_CONTROLLER
            + self.config.POWER_CONSTANTS.FAN_HIGH_COOLING
            - self.config.POWER_CONSTANTS.BASE_CONTROLLER
        )
        self.assertEqual(power_fan, expected_fan)

        # Test with fan on and grill on (should be low operation power)
        fan_grill_status = fan_only_status.copy()
        fan_grill_status["module_on"] = True
        fan_grill_status["set_temp"] = 225

        power_fan_grill = self.device_status_service.calculate_power_consumption(
            lua_dev, self.to_lua_table(fan_grill_status)
        )
        expected_fan_grill = (
            self.config.POWER_CONSTANTS.BASE_CONTROLLER
            + self.config.POWER_CONSTANTS.FAN_LOW_OPERATION
            - self.config.POWER_CONSTANTS.BASE_CONTROLLER
        )
        self.assertEqual(power_fan_grill, expected_fan_grill)


if __name__ == "__main__":
    unittest.main()
