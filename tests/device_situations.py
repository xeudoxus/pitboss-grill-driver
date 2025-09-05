"""
Common device situations and mock scenarios for SmartThings Edge driver tests.
Provides standardized test scenarios to reduce duplication and improve consistency.
"""

from mock_device import (
    PyDevice,
    create_default_grill_status,
    create_default_preferences,
)


class DeviceSituations:
    """Collection of common device states and scenarios for testing."""

    @staticmethod
    def grill_online_basic():
        """Basic online grill with default settings."""
        status = create_default_grill_status()
        status.update(
            {
                "is_fahrenheit": True,
                "unit": "F",
                "grill_temp": 225,
                "set_temp": 225,
                "p1_temp": 180,
                "p2_temp": 175,
                "p3_temp": 170,
                "p4_temp": 165,
                "motor_state": True,
                "hot_state": True,
                "module_on": True,
                "fan_state": True,
                "light_state": False,
                "prime_state": False,
                "auger_state": True,
                "ignitor_state": False,
            }
        )
        return status

    @staticmethod
    def grill_offline():
        """Grill that is offline/disconnected."""
        status = create_default_grill_status()
        return status

    @staticmethod
    def grill_heating_up():
        """Grill in the process of heating up."""
        status = create_default_grill_status()
        status.update(
            {
                "is_fahrenheit": True,
                "grill_temp": 180,
                "set_temp": 225,
                "p1_temp": 160,
                "p2_temp": 155,
                "p3_temp": 150,
                "p4_temp": 145,
                "motor_state": True,
                "hot_state": False,
                "module_on": True,
                "fan_state": True,
                "light_state": False,
                "prime_state": False,
                "auger_state": True,
                "ignitor_state": True,
            }
        )
        return status

    @staticmethod
    def grill_at_temperature():
        """Grill that has reached target temperature."""
        status = create_default_grill_status()
        status.update(
            {
                "is_fahrenheit": True,
                "grill_temp": 225,
                "set_temp": 225,
                "p1_temp": 200,
                "p2_temp": 195,
                "p3_temp": 190,
                "p4_temp": 185,
                "motor_state": True,
                "hot_state": True,
                "module_on": True,
                "fan_state": True,
                "light_state": False,
                "prime_state": False,
                "auger_state": False,
                "ignitor_state": False,
            }
        )
        return status

    @staticmethod
    def grill_pellets_low():
        """Grill with low pellet warning."""
        status = create_default_grill_status()
        status.update(
            {
                "is_fahrenheit": True,
                "grill_temp": 220,
                "set_temp": 225,
                "p1_temp": 195,
                "p2_temp": 190,
                "p3_temp": 185,
                "p4_temp": 180,
                "motor_state": True,
                "hot_state": True,
                "module_on": True,
                "fan_state": True,
                "light_state": False,
                "prime_state": False,
                "auger_state": True,
                "ignitor_state": False,
                "no_pellets": True,
            }
        )
        return status

    @staticmethod
    def grill_error_state():
        """Grill in an error state."""
        status = create_default_grill_status()
        status.update({"motor_error": True, "fan_error": True})
        return status

    @staticmethod
    def grill_probe_disconnected():
        """Grill with some probes disconnected."""
        status = create_default_grill_status()
        status.update(
            {
                "is_fahrenheit": True,
                "grill_temp": 225,
                "set_temp": 225,
                "p1_temp": 200,
                "p2_temp": 195,
                "p3_temp": 0,  # Disconnected
                "p4_temp": 0,  # Disconnected
                "motor_state": True,
                "hot_state": True,
                "module_on": True,
                "fan_state": True,
                "light_state": False,
                "prime_state": False,
                "auger_state": True,
                "ignitor_state": False,
            }
        )
        return status

    @staticmethod
    def grill_celsius_mode():
        """Grill configured for Celsius temperature display."""
        status = create_default_grill_status()
        status.update(
            {
                "is_fahrenheit": False,
                "grill_temp": 107,  # 225°F in Celsius
                "set_temp": 107,
                "p1_temp": 82,  # 180°F in Celsius
                "p2_temp": 80,  # 175°F in Celsius
                "p3_temp": 77,  # 170°F in Celsius
                "p4_temp": 74,  # 165°F in Celsius
                "motor_state": True,
                "hot_state": True,
                "module_on": True,
                "fan_state": True,
                "light_state": False,
                "prime_state": False,
                "auger_state": True,
                "ignitor_state": False,
            }
        )
        return status

    @staticmethod
    def grill_on_with_fan():
        """Grill is ON with fan running (normal heating operation)."""
        status = create_default_grill_status()
        status.update(
            {
                "motor_state": True,
                "hot_state": True,
                "module_on": True,
                "fan_state": True,  # Fan is running
                "grill_temp": 213,
                "set_temp": 225,
                "is_fahrenheit": True,
                "p1_temp": 180,
                "p2_temp": 175,
                "p3_temp": 170,
                "p4_temp": 165,
                "auger_state": True,
                "ignitor_state": False,
                "light_state": False,
                "prime_state": False,
            }
        )
        return status

    @staticmethod
    def grill_cooling_state():
        """Grill OFF but fan still running for cooling (from test_advanced_situations)."""
        status = create_default_grill_status()
        status.update(
            {
                "motor_state": False,
                "hot_state": False,
                "module_on": False,
                "fan_state": True,  # Fan still running for cooling
                "grill_temp": 213,
                "set_temp": 225,
                "is_fahrenheit": True,
                "p1_temp": 77,  # Add missing probe temperatures
                "p2_temp": 74,
                "p3_temp": 0,
                "p4_temp": 0,
                "auger_state": False,
                "ignitor_state": False,
                "light_state": False,
                "prime_state": False,  # Add missing prime state
                # Add missing error fields
                "high_temp_error": False,
                "fan_error": False,
                "hot_error": False,
                "motor_error": False,
                "no_pellets": False,
                "erl_error": False,
                "error_1": False,
                "error_2": False,
                "error_3": False,
            }
        )
        return status

    @staticmethod
    def grill_cooling_power_calc():
        """Grill in cooling state for power consumption calculation."""
        status = create_default_grill_status()
        status.update(
            {
                "motor_state": False,
                "hot_state": False,
                "module_on": False,
                "fan_state": True,
                "grill_temp": 213,
                "is_fahrenheit": True,
                "p1_temp": 77,
                "p2_temp": 74,
                "p3_temp": 0,
                "p4_temp": 0,
                "auger_state": False,
                "ignitor_state": False,
                "light_state": False,
                "prime_state": False,
            }
        )
        return status

    @staticmethod
    def grill_cooling_pellet_status():
        """Grill in cooling state for pellet status updates."""
        status = create_default_grill_status()
        status.update(
            {
                "motor_state": False,
                "hot_state": False,
                "module_on": False,
                "fan_state": True,  # Fan ON for cooling
                "auger_state": False,
                "ignitor_state": False,
                "light_state": False,
                "grill_temp": 200,
                "set_temp": 225,
                "is_fahrenheit": True,
                "p1_temp": 77,
                "p2_temp": 74,
                "p3_temp": 0,
                "p4_temp": 0,
                "prime_state": False,
                "high_temp_error": False,
                "fan_error": False,
                "hot_error": False,
                "motor_error": False,
                "no_pellets": False,
                "erl_error": False,
                "error_1": False,
                "error_2": False,
                "error_3": False,
            }
        )
        return status

    @staticmethod
    def grill_fully_off():
        """Grill completely off (motor, hot, module, fan all false) for temperature range updates."""
        status = create_default_grill_status()
        status.update(
            {
                "motor_state": False,
                "hot_state": False,
                "module_on": False,
                "fan_state": False,
                "grill_temp": 200,
                "set_temp": 225,
                "is_fahrenheit": True,
                "p1_temp": 77,
                "p2_temp": 74,
                "p3_temp": 0,
                "p4_temp": 0,
                "auger_state": False,
                "ignitor_state": False,
                "light_state": False,
                "prime_state": False,
                "high_temp_error": False,
                "fan_error": False,
                "hot_error": False,
                "motor_error": False,
                "no_pellets": False,
                "erl_error": False,
                "error_1": False,
                "error_2": False,
                "error_3": False,
            }
        )
        return status


class DeviceFactory:
    """Factory for creating devices in specific situations."""

    @staticmethod
    def create_device_from_situation(
        situation_dict,
        device_id="test-device",
        device_label="Test Grill",
        preferences=None,
    ):
        """Create a PyDevice from a situation dictionary."""
        if preferences is None:
            preferences = create_default_preferences()

        # Determine initial state based on grill status
        motor_state = situation_dict.get("motor_state", False)
        hot_state = situation_dict.get("hot_state", False)
        module_on = situation_dict.get("module_on", False)
        initial_state = "on" if (motor_state or hot_state or module_on) else "off"

        device = PyDevice(initial_state, preferences)

        # Set device fields based on situation
        for key, value in situation_dict.items():
            if key in [
                "is_fahrenheit",
                "grill_temp",
                "set_temp",
                "p1_temp",
                "p2_temp",
                "p3_temp",
                "p4_temp",
                "motor_state",
                "hot_state",
                "module_on",
                "fan_state",
                "light_state",
                "prime_state",
                "auger_state",
                "ignitor_state",
                "error_1",
                "error_2",
                "error_3",
                "erl_error",
                "hot_error",
                "no_pellets",
                "high_temp_error",
                "motor_error",
                "fan_error",
            ]:
                device.set_field(key, value)
            elif key == "state":
                device.set_field("state", value)
            elif key == "unit":
                device.set_field(
                    "unit", "F" if situation_dict.get("is_fahrenheit", True) else "C"
                )
            elif key == "error_message":
                device.set_field("error_message", value)

        # Set device metadata
        device.id = device_id
        device.label = device_label

        return device

    @staticmethod
    def create_online_grill():
        """Create a standard online grill device."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_online_basic()
        )

    @staticmethod
    def create_offline_grill():
        """Create an offline grill device."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_offline()
        )

    @staticmethod
    def create_heating_grill():
        """Create a grill that is heating up."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_heating_up()
        )

    @staticmethod
    def create_at_temp_grill():
        """Create a grill at target temperature."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_at_temperature()
        )

    @staticmethod
    def create_pellets_low_grill():
        """Create a grill with low pellet warning."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_pellets_low()
        )

    @staticmethod
    def create_error_grill():
        """Create a grill in error state."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_error_state()
        )

    @staticmethod
    def create_probe_disconnected_grill():
        """Create a grill with disconnected probes."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_probe_disconnected()
        )

    @staticmethod
    def create_celsius_grill():
        """Create a grill in Celsius mode."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_celsius_mode()
        )

    @staticmethod
    def create_grill_on_with_fan():
        """Create a grill that is ON with fan running."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_on_with_fan()
        )

    @staticmethod
    def create_grill_cooling_state():
        """Create a grill in cooling state (off but fan running)."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_cooling_state()
        )

    @staticmethod
    def create_grill_cooling_power_calc():
        """Create a grill in cooling state for power consumption calculation."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_cooling_power_calc()
        )

    @staticmethod
    def create_grill_cooling_pellet_status():
        """Create a grill in cooling state for pellet status updates."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_cooling_pellet_status()
        )

    @staticmethod
    def create_grill_fully_off():
        """Create a grill that is completely off (motor, hot, module, fan all false)."""
        return DeviceFactory.create_device_from_situation(
            DeviceSituations.grill_fully_off()
        )


class MockDataFactory:
    """Factory for creating mock API responses and data."""

    @staticmethod
    def create_grill_status_response(**overrides):
        """Create a mock grill status API response."""
        base_response = create_default_grill_status()
        base_response.update(overrides)
        return base_response

    @staticmethod
    def create_success_api_response():
        """Create a successful API response."""
        return {"result": "success", "status": "ok"}

    @staticmethod
    def create_error_api_response(error_message="API Error"):
        """Create an error API response."""
        return {"result": "error", "message": error_message}

    @staticmethod
    def create_network_timeout_response():
        """Create a network timeout response."""
        return {"result": "timeout", "message": "Network request timed out"}
