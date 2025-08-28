# Canonical, robust test suite matching example_custom_capabilities_test.py
import os
import sys
import unittest

from base_test_classes import LuaTestBase
from mock_device import (
    create_custom_capability_events,
    create_grill_status,
    create_grill_status_event,
    create_grill_temp_event,
    create_light_control_event,
    create_pellet_status_events,
    create_prime_control_event,
    create_temperature_probes_event,
    create_temperature_unit_event,
)

tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)


class TestCustomCapabilities(LuaTestBase):
    def test_individual_custom_capability_events(self):
        py_dev, lua_dev = self.create_lua_device("on")
        py_dev.emit_grill_status("Grill is heating up")
        self.assert_event_exists(py_dev.events, event_name="lastMessage")
        py_dev.emit_grill_temp(current_temp=225, target_temp=250, unit="F")
        self.assert_event_exists(
            py_dev.events, event_name="currentTemp", event_value="225"
        )
        self.assert_event_exists(
            py_dev.events, event_name="targetTemp", event_value="250"
        )
        py_dev.emit_light_control(True)
        self.assert_event_exists(
            py_dev.events, event_name="lightState", event_value="ON"
        )
        py_dev.emit_pellet_status(fan_state=True, auger_state=False, ignitor_state=True)
        self.assert_event_exists(py_dev.events, event_name="fanState", event_value="ON")
        self.assert_event_exists(
            py_dev.events, event_name="augerState", event_value="OFF"
        )
        self.assert_event_exists(
            py_dev.events, event_name="ignitorState", event_value="ON"
        )
        py_dev.emit_prime_control(False)
        self.assert_event_exists(
            py_dev.events, event_name="primeState", event_value="OFF"
        )
        py_dev.emit_temperature_probes("225,180,0,0")
        self.assert_event_exists(
            py_dev.events, event_name="probe", event_value="225,180,0,0"
        )
        py_dev.emit_temperature_unit("F")
        self.assert_event_exists(py_dev.events, event_name="unit", event_value="F")

    def test_status_based_custom_events(self):
        py_dev, lua_dev = self.create_lua_device("on")
        status = create_grill_status(
            grill_temp=250,
            set_temp=225,
            p1_temp=180,
            p2_temp=175,
            p3_temp=0,
            p4_temp=0,
            fan_state=True,
            light_state=True,
            prime_state=False,
            auger_state=True,
            ignitor_state=False,
            is_fahrenheit=True,
        )
        py_dev.emit_all_custom_events(status)
        self.assert_event_exists(
            py_dev.events, event_name="currentTemp", event_value="250"
        )
        self.assert_event_exists(
            py_dev.events, event_name="targetTemp", event_value="225"
        )
        self.assert_event_exists(
            py_dev.events, event_name="lightState", event_value="ON"
        )
        self.assert_event_exists(py_dev.events, event_name="fanState", event_value="ON")
        self.assert_event_exists(
            py_dev.events, event_name="augerState", event_value="ON"
        )
        self.assert_event_exists(
            py_dev.events, event_name="ignitorState", event_value="OFF"
        )
        self.assert_event_exists(
            py_dev.events, event_name="primeState", event_value="OFF"
        )
        self.assert_event_exists(
            py_dev.events, event_name="probe", event_value="180,175,0,0"
        )
        self.assert_event_exists(py_dev.events, event_name="unit", event_value="F")

    def test_custom_capability_event_creation_functions(self):
        status_event = create_grill_status_event("Test message")
        expected_status = {
            "capability": "{{NAMESPACE}}.grillStatus",
            "attribute": "lastMessage",
            "value": {"value": "Test message"},
        }
        self.assertEqual(status_event, expected_status)
        temp_event = create_grill_temp_event(current_temp=200)
        expected_temp = {
            "capability": "{{NAMESPACE}}.grillTemp",
            "attribute": "currentTemp",
            "value": {"value": "200", "unit": "F"},
        }
        self.assertEqual(temp_event, expected_temp)
        temp_events = create_grill_temp_event(
            current_temp=200, target_temp=225, unit="C"
        )
        self.assertEqual(len(temp_events), 2)
        self.assertEqual(temp_events[0]["attribute"], "currentTemp")
        self.assertEqual(temp_events[1]["attribute"], "targetTemp")
        self.assertEqual(temp_events[0]["value"]["unit"], "C")
        light_event = create_light_control_event(True)
        expected_light = {
            "capability": "{{NAMESPACE}}.lightControl",
            "attribute": "lightState",
            "value": {"value": "ON"},
        }
        self.assertEqual(light_event, expected_light)
        pellet_events = create_pellet_status_events(fan_state=True, auger_state=False)
        self.assertEqual(len(pellet_events), 2)
        self.assertEqual(pellet_events[0]["attribute"], "fanState")
        self.assertEqual(pellet_events[0]["value"]["value"], "ON")
        self.assertEqual(pellet_events[1]["attribute"], "augerState")
        self.assertEqual(pellet_events[1]["value"]["value"], "OFF")
        prime_event = create_prime_control_event(False)
        expected_prime = {
            "capability": "{{NAMESPACE}}.primeControl",
            "attribute": "primeState",
            "value": {"value": "OFF"},
        }
        self.assertEqual(prime_event, expected_prime)
        probes_event = create_temperature_probes_event("200,175,0,0")
        expected_probes = {
            "capability": "{{NAMESPACE}}.temperatureProbes",
            "attribute": "probe",
            "value": {"value": "200,175,0,0"},
        }
        self.assertEqual(probes_event, expected_probes)
        unit_event = create_temperature_unit_event("C")
        expected_unit = {
            "capability": "{{NAMESPACE}}.temperatureUnit",
            "attribute": "unit",
            "value": {"value": "C"},
        }
        self.assertEqual(unit_event, expected_unit)

    def test_comprehensive_status_event_creation(self):
        status = create_grill_status(
            grill_temp=275,
            set_temp=250,
            p1_temp=185,
            p2_temp=180,
            p3_temp=165,
            p4_temp=0,
            fan_state=True,
            light_state=False,
            prime_state=True,
            auger_state=True,
            ignitor_state=False,
            is_fahrenheit=False,
        )
        all_events = create_custom_capability_events(status)
        self.assertEqual(len(all_events), 9)
        temp_events = [
            e for e in all_events if e["capability"] == "{{NAMESPACE}}.grillTemp"
        ]
        self.assertEqual(len(temp_events), 2)
        pellet_events = [
            e for e in all_events if e["capability"] == "{{NAMESPACE}}.pelletStatus"
        ]
        self.assertEqual(len(pellet_events), 3)
        unit_events = [e for e in all_events if e["attribute"] == "unit"]
        self.assertEqual(len(unit_events), 1)
        self.assertEqual(unit_events[0]["value"]["value"], "C")
        probe_events = [e for e in all_events if e["attribute"] == "probe"]
        self.assertEqual(len(probe_events), 1)
        self.assertEqual(probe_events[0]["value"]["value"], "185,180,165,0")

    def test_device_profile_has_custom_capabilities(self):
        py_dev, lua_dev = self.create_lua_device("on")
        self.assertIn("main", py_dev.profile["components"])
        main_component = py_dev.profile["components"]["main"]
        capability_ids = [cap["id"] for cap in main_component["capabilities"]]
        expected_capabilities = [
            "{{NAMESPACE}}.grillStatus",
            "{{NAMESPACE}}.grillTemp",
            "{{NAMESPACE}}.lightControl",
            "{{NAMESPACE}}.pelletStatus",
            "{{NAMESPACE}}.primeControl",
            "{{NAMESPACE}}.temperatureProbes",
            "{{NAMESPACE}}.temperatureUnit",
        ]
        for expected_cap in expected_capabilities:
            self.assertIn(
                expected_cap, capability_ids, f"Missing capability: {expected_cap}"
            )

    def test_celsius_temperature_handling(self):
        py_dev, lua_dev = self.create_lua_device("on")
        status = create_grill_status(
            grill_temp=120, set_temp=110, p1_temp=75, is_fahrenheit=False
        )
        py_dev.emit_all_custom_events(status)
        temp_events = [e for e in py_dev.events if "Temp" in e.get("name", "")]
        for event in temp_events:
            if "unit" in event:
                self.assertEqual(event["unit"], "C")
        self.assert_event_exists(py_dev.events, event_name="unit", event_value="C")


if __name__ == "__main__":
    unittest.main()
