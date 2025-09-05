"""
Mock SmartThings device for Python-Lua testing.
Provides a Python implementation that can be bridged to Lua for testing SmartThings Edge drivers.
"""


class PyDevice:
    """Mock SmartThings device that can be converted to Lua for testing."""

    def offline(self, *args, **kwargs):
        """Mock offline method for compatibility with Lua device:offline() calls."""
        return True

    def online(self, *args, **kwargs):
        """Mock online method for compatibility with Lua device:online() calls."""
        return True

    def __init__(self, initial_state="on", preferences=None):
        self.preferences = preferences or {}
        self.profile = {
            "components": {
                "Standard_Grill": {
                    "id": "Standard_Grill",
                    "capabilities": [
                        {"id": "temperatureMeasurement"},
                        {"id": "thermostatHeatingSetpoint"},
                        {"id": "switch"},
                        {"id": "powerMeter"},
                    ],
                },
                "probe1": {
                    "id": "probe1",
                    "capabilities": [{"id": "temperatureMeasurement"}],
                },
                "probe2": {
                    "id": "probe2",
                    "capabilities": [{"id": "temperatureMeasurement"}],
                },
                "probe3": {
                    "id": "probe3",
                    "capabilities": [{"id": "temperatureMeasurement"}],
                },
                "probe4": {
                    "id": "probe4",
                    "capabilities": [{"id": "temperatureMeasurement"}],
                },
                "error": {"id": "error"},
                "Grill_Error": {
                    "id": "Grill_Error",
                    "capabilities": [{"id": "panicAlarm"}],
                },
                "main": {
                    "id": "main",
                    "capabilities": [
                        {"id": "{{NAMESPACE}}.grillStatus"},
                        {"id": "{{NAMESPACE}}.grillTemp"},
                        {"id": "{{NAMESPACE}}.lightControl"},
                        {"id": "{{NAMESPACE}}.pelletStatus"},
                        {"id": "{{NAMESPACE}}.primeControl"},
                        {"id": "{{NAMESPACE}}.temperatureProbes"},
                        {"id": "{{NAMESPACE}}.temperatureUnit"},
                    ],
                },
            },
            "capabilities": [],
        }
        self.events = []
        self.component_events = []
        self.fields = {}
        self.initial_state = initial_state

        # Add missing fields that tests expect
        self.fields = {}

        # Mock thread object for timer functionality
        class MockThread:
            def call_with_delay(self, delay, callback):
                # Just call the callback immediately for testing
                callback()
                return self

            def call_on_schedule(self, delay, callback, name=None):
                # Just call the callback immediately for testing
                callback()
                return self

            def cancel(self):
                pass

        self.thread = MockThread()
        self.state = initial_state
        self.switch_state = initial_state
        self.is_on = initial_state == "on"
        self._latest_state = initial_state

    @staticmethod
    def _convert_st_event_to_simple(event):
        # If it's a Lua table, convert to dict
        if hasattr(event, "items"):
            event_dict = dict(event.items())
        else:
            event_dict = event
        # Improved device table detection: recursively check for event keys at any level before classifying as a device table.
        import traceback

        device_keys = {
            "emit_event",
            "emit_component_event",
            "set_field",
            "get_latest_state",
            "get_parent_device",
            "preferences",
            "label",
            "offline",
            "profile",
            "id",
            "online",
            "get_field",
        }
        event_keys = {"capability", "attribute", "name", "value"}

        def has_event_keys(d):
            if not isinstance(d, dict):
                return False
            if any(k in d for k in event_keys):
                return True
            # Recursively check nested dicts
            for v in d.values():
                if isinstance(v, dict) and has_event_keys(v):
                    return True
            return False

        if isinstance(event_dict, dict):
            if has_event_keys(event_dict):
                pass  # continue to event extraction
            else:
                matched_keys = device_keys.intersection(set(event_dict.keys()))
                callable_count = 0
                for k in matched_keys:
                    try:
                        if callable(event_dict[k]):
                            callable_count += 1
                    except Exception as e:
                        print(
                            f"[MOCK_DEVICE] _convert_st_event_to_simple: Exception checking callable for key {k}: {e}"
                        )
                # Only skip as device table if all device keys are present and most are callables
                if len(matched_keys) == len(device_keys) and callable_count >= 7:
                    traceback.print_stack()
                    return None
        # Now try to extract event fields
        result = {}
        if isinstance(event_dict, dict):
            # Try direct fields
            for k in ("capability", "attribute", "name", "value"):
                if k in event_dict:
                    result[k] = event_dict[k]
            # If 'name' but not 'attribute', alias
            if "name" in result and "attribute" not in result:
                result["attribute"] = result["name"]
            # Always set 'name' as alias for 'attribute' for test compatibility
            if "attribute" in result:
                result["name"] = result["attribute"]
            for subkey in ("event", "data"):
                if subkey in event_dict and isinstance(event_dict[subkey], dict):
                    for k in ("capability", "attribute", "name", "value"):
                        if k in event_dict[subkey]:
                            result[k] = event_dict[subkey][k]
            # Fallback: if only value
            if "value" in event_dict and "value" not in result:
                result["value"] = event_dict["value"]
            # Flatten value if it's a dict with 'value' key
            if (
                "value" in result
                and isinstance(result["value"], dict)
                and "value" in result["value"]
            ):
                val = result["value"]
                result["value"] = val["value"]
                if "unit" in val:
                    result["unit"] = val["unit"]
            # Always include everything else for debug
            for k, v in event_dict.items():
                if k not in result:
                    result[k] = v
        else:
            result = {"value": event_dict}
        return result

    def emit_event(self, *args):
        """Mock emit_event method."""
        # Handles both Lua and Python device objects, always appends to 'events' list.
        event = None
        target = self
        if len(args) == 0:
            return
        elif len(args) == 1:
            event = args[0]
        elif len(args) >= 2:
            event = args[1]

        # Convert Lua table to dict if needed
        if event is not None and hasattr(event, "items"):
            event = dict(event.items())

        # Convert SmartThings format to simplified format for integration tests
        convert = getattr(target, "_convert_st_event_to_simple", None)
        if not callable(convert):
            simple_event = event
        else:
            simple_event = convert(event)

        # Always ensure 'events' exists and is a list
        if not hasattr(target, "events") or not isinstance(target.events, list):
            target.events = []
        # Append event to 'events' list (Python or Lua table)
        target.events.append(simple_event)
        return

    def emit_component_event(self, *args):
        """Mock emit_component_event method."""
        # When called from Lua as device:emit_component_event(component, event),
        # args = [device_table, component, event, ...] (3 args)
        # When called from Python as device.emit_component_event(component, event),
        # args = [component, event, ...] (2 args)

        if len(args) == 3:
            # Called from Lua with colon syntax: device:emit_component_event(component, event)
            # Skip the device table (args[0])
            component = args[1]
            event = args[2]
        elif len(args) == 2:
            # Called as function call: emit_component_event(component, event)
            component = args[0]
            event = args[1]
        else:
            # Fallback
            component = args[0] if len(args) > 0 else None
            event = args[1] if len(args) > 1 else None

        # Convert Lua table to dict if needed
        if hasattr(event, "items") and not isinstance(event, dict):
            event = dict(event.items())

        # Convert component - it should be a string or have an id
        if hasattr(component, "id"):
            component_id = component.id
        elif hasattr(component, "items") and not isinstance(component, dict):
            component_dict = dict(component.items())
            component_id = component_dict.get("id", str(component))
        else:
            component_id = str(component) if component is not None else None

        self.component_events.append({"component": component_id, "event": event})

    def get_field(self, *args):
        """Mock get_field method."""
        # When called from Lua as device:get_field(key),
        # args = [device_table, key, ...]
        # When called from Python as device.get_field(key),
        # args = [key, ...]

        # Check if first arg is a Lua table (device object)
        if len(args) > 0 and hasattr(args[0], "items") and not isinstance(args[0], str):
            # Called from Lua: skip the device table
            key = args[1] if len(args) > 1 else None
        else:
            # Called from Python: use args directly
            key = args[0] if len(args) > 0 else None
        # If key is a Lua table, use .id if present, else repr(key)
        if hasattr(key, "id"):
            key_str = key.id
        elif hasattr(key, "items") and not isinstance(key, str):
            key_str = repr(key)
        else:
            key_str = key
        # Special case: grill_start_time and any last_update_* field should always be None or a number
        if key_str == "grill_start_time" or (
            isinstance(key_str, str) and key_str.startswith("last_update_")
        ):
            val = self.fields.get(key_str, None)

            if isinstance(val, (int, float)):
                return val
            # If not set, always return None for last_update_* fields
            return None
        # Try direct, then stringified, then fallback to first string key
        if key_str in self.fields:
            return self.fields[key_str]
        if isinstance(key_str, str):
            for k in self.fields:
                if isinstance(k, str) and k == key_str:
                    return self.fields[k]
                if hasattr(k, "id") and k.id == key_str:
                    return self.fields[k]
        return None

    def set_field(self, *args):
        """Mock set_field method."""
        # When called from Lua as device:set_field(key, value, options),
        # args = [device_table, key, value, options, ...]
        # When called from Python as device.set_field(key, value, options),
        # args = [key, value, options, ...]
        import traceback

        # Check if first arg is a Lua table (device object)
        if len(args) > 0 and hasattr(args[0], "items") and not isinstance(args[0], str):
            # Called from Lua: skip the device table
            key = args[1] if len(args) > 1 else None
            value = args[2] if len(args) > 2 else None
        else:
            # Called from Python: use args directly
            key = args[0] if len(args) > 0 else None
            value = args[1] if len(args) > 1 else None
        # If key is a Lua table, use .id if present, else repr(key)
        if hasattr(key, "id"):
            key_str = key.id
        elif hasattr(key, "items") and not isinstance(key, str):
            key_str = repr(key)
        else:
            key_str = key

        if key_str is None:
            print(
                f"[ERROR] set_field called with key=None! Value={value} (type: {type(value)})\nStack trace:"
            )
            traceback.print_stack()
            return

        # For time fields, ensure we only store numbers or None
        if key_str == "grill_start_time" or (
            isinstance(key_str, str) and key_str.startswith("last_update_")
        ):
            if value is not None and not isinstance(value, (int, float)):
                print(
                    f"[WARNING] Attempting to store non-numeric time value: {value} ({type(value)}) for field '{key_str}'"
                )
                try:
                    value = float(value)
                except (ValueError, TypeError):
                    print(f"[ERROR] Cannot convert {value} to number, storing None")
                    value = None
        self.fields[key_str] = value

    def get_latest_state(self, *args):
        """Mock get_latest_state method."""
        # When called from Lua as device:get_latest_state(component_id, capability_id, attribute_name)
        # args[0] is the device object itself, actual arguments start from args[1]
        if len(args) >= 4:
            # Called from Lua: args = [device_table, component_id, capability_id, attribute_name]
            component_id = args[1]
            capability_id = args[2]
            attribute_name = args[3]
        elif len(args) >= 3:
            # Called from Python: args = [component_id, capability_id, attribute_name]
            component_id = args[0]
            capability_id = args[1]
            attribute_name = args[2]
        else:
            return None

        # Handle both string and object forms for capability_id
        if hasattr(capability_id, "ID"):
            capability_id = capability_id.ID

        # Handle both string and object forms for attribute_name
        if hasattr(attribute_name, "NAME"):
            attribute_name = attribute_name.NAME

        # For switch capability, return the device's initial state directly
        if (
            component_id == "Standard_Grill"
            and attribute_name == "switch"
            and capability_id in ("switch", "st.switch")
        ):
            return self.initial_state

        # For other capabilities, return None (no state)
        return None

    def clear_events(self):
        """Clear all recorded events."""
        self.events.clear()
        self.component_events.clear()

    def clear_fields(self):
        """Clear all stored fields."""
        self.fields.clear()

    def reset(self):
        """Reset device to initial state."""
        self.clear_events()
        self.clear_fields()

    # Custom Capability Helper Methods

    def emit_grill_status(self, message):
        """Emit a grill status message event."""
        event = create_grill_status_event(message)
        self.emit_event(event)

    def emit_grill_temp(self, current_temp=None, target_temp=None, unit="F"):
        """Emit grill temperature events."""
        events = create_grill_temp_event(current_temp, target_temp, unit)
        if isinstance(events, list):
            for event in events:
                self.emit_event(event)
        else:
            self.emit_event(events)

    def emit_light_control(self, state):
        """Emit a light control state event."""
        event = create_light_control_event(state)
        self.emit_event(event)

    def emit_pellet_status(self, fan_state=None, auger_state=None, ignitor_state=None):
        """Emit pellet status events."""
        events = create_pellet_status_events(fan_state, auger_state, ignitor_state)
        for event in events:
            self.emit_event(event)

    def emit_prime_control(self, state):
        """Emit a prime control state event."""
        event = create_prime_control_event(state)
        self.emit_event(event)

    def emit_temperature_probes(self, probe_text):
        """Emit a temperature probes event."""
        event = create_temperature_probes_event(probe_text)
        self.emit_event(event)

    def emit_temperature_unit(self, unit):
        """Emit a temperature unit event."""
        event = create_temperature_unit_event(unit)
        self.emit_event(event)

    def emit_all_custom_events(self, status):
        """Emit all custom capability events based on status data."""
        events = create_custom_capability_events(status)
        for event in events:
            self.emit_event(event)


def create_default_grill_status():
    """Create a default grill status dictionary for testing."""
    return {
        "is_fahrenheit": True,
        "grill_temp": 0,
        "set_temp": 0,
        "p1_temp": 0,  # Use 0 for disconnected/off
        "p2_temp": 0,  # Use 0 for disconnected/off
        "p3_temp": 0,  # Use 0 for disconnected/off
        "p4_temp": 0,  # Use 0 for disconnected/off
        "motor_state": False,
        "hot_state": False,
        "module_on": False,
        "fan_state": False,
        "light_state": False,
        "prime_state": False,
        "auger_state": False,
        "ignitor_state": False,
        "error_1": False,
        "error_2": False,
        "error_3": False,
        "erl_error": False,
        "hot_error": False,
        "no_pellets": False,
        "high_temp_error": False,
        "motor_error": False,
        "fan_error": False,
    }


def create_default_preferences():
    """Create default device preferences for testing."""
    return {
        "grillOffset": 0,
        "probe1Offset": 0,
        "probe2Offset": 0,
        "probe3Offset": 0,
        "probe4Offset": 0,
    }


# Custom Capability Event Helpers


def create_grill_status_event(message):
    """Create a grillStatus.lastMessage event."""
    return {
        "capability": "{{NAMESPACE}}.grillStatus",
        "attribute": "lastMessage",
        "value": {"value": str(message)},
    }


def create_grill_temp_event(current_temp=None, target_temp=None, unit="F"):
    """Create grillTemp events for currentTemp and/or targetTemp."""
    events = []

    if current_temp is not None:
        events.append(
            {
                "capability": "{{NAMESPACE}}.grillTemp",
                "attribute": "currentTemp",
                "value": {"value": str(current_temp), "unit": unit},
            }
        )

    if target_temp is not None:
        events.append(
            {
                "capability": "{{NAMESPACE}}.grillTemp",
                "attribute": "targetTemp",
                "value": {"value": str(target_temp), "unit": unit},
            }
        )

    return events[0] if len(events) == 1 else events


def create_light_control_event(state):
    """Create a lightControl.lightState event."""
    return {
        "capability": "{{NAMESPACE}}.lightControl",
        "attribute": "lightState",
        "value": {"value": "ON" if state else "OFF"},
    }


def create_pellet_status_events(fan_state=None, auger_state=None, ignitor_state=None):
    """Create pelletStatus events for fan, auger, and/or ignitor states."""
    events = []

    if fan_state is not None:
        events.append(
            {
                "capability": "{{NAMESPACE}}.pelletStatus",
                "attribute": "fanState",
                "value": {"value": "ON" if fan_state else "OFF"},
            }
        )

    if auger_state is not None:
        events.append(
            {
                "capability": "{{NAMESPACE}}.pelletStatus",
                "attribute": "augerState",
                "value": {"value": "ON" if auger_state else "OFF"},
            }
        )

    if ignitor_state is not None:
        events.append(
            {
                "capability": "{{NAMESPACE}}.pelletStatus",
                "attribute": "ignitorState",
                "value": {"value": "ON" if ignitor_state else "OFF"},
            }
        )

    return events


def create_prime_control_event(state):
    """Create a primeControl.primeState event."""
    return {
        "capability": "{{NAMESPACE}}.primeControl",
        "attribute": "primeState",
        "value": {"value": "ON" if state else "OFF"},
    }


def create_temperature_probes_event(probe_text):
    """Create a temperatureProbes.probe event."""
    return {
        "capability": "{{NAMESPACE}}.temperatureProbes",
        "attribute": "probe",
        "value": {"value": str(probe_text)},
    }


def create_temperature_unit_event(unit):
    """Create a temperatureUnit.unit event."""
    return {
        "capability": "{{NAMESPACE}}.temperatureUnit",
        "attribute": "unit",
        "value": {"value": unit},
    }


# SmartThings Format Event Creation Functions (for unit testing)


def create_grill_status_event_st_format(message):
    """Create a grillStatus.lastMessage event in SmartThings format."""
    return {
        "capability": "{{NAMESPACE}}.grillStatus",
        "attribute": "lastMessage",
        "value": {"value": str(message)},
    }


def create_grill_temp_event_st_format(current_temp=None, target_temp=None, unit="F"):
    """Create grillTemp events in SmartThings format."""
    events = []

    if current_temp is not None:
        events.append(
            {
                "capability": "{{NAMESPACE}}.grillTemp",
                "attribute": "currentTemp",
                "value": {"value": str(current_temp), "unit": unit},
            }
        )

    if target_temp is not None:
        events.append(
            {
                "capability": "{{NAMESPACE}}.grillTemp",
                "attribute": "targetTemp",
                "value": {"value": str(target_temp), "unit": unit},
            }
        )

    return events[0] if len(events) == 1 else events


def create_light_control_event_st_format(state):
    """Create a lightControl.lightState event in SmartThings format."""
    return {
        "capability": "{{NAMESPACE}}.lightControl",
        "attribute": "lightState",
        "value": {"value": "ON" if state else "OFF"},
    }


# Enhanced Status Creation Functions


def create_grill_status(**overrides):
    """Create a grill status dictionary with optional overrides."""
    status = create_default_grill_status()
    status.update(overrides)
    return status


def create_custom_capability_events(status):
    """Create all custom capability events based on status data."""
    events = []
    unit = "F" if status.get("is_fahrenheit", True) else "C"
    # Grill temperature events
    if "grill_temp" in status or "set_temp" in status:
        temp_events = create_grill_temp_event(
            current_temp=status.get("grill_temp"),
            target_temp=status.get("set_temp"),
            unit=unit,
        )
        if isinstance(temp_events, list):
            events.extend(temp_events)
        elif temp_events:
            events.append(temp_events)
    # Pellet status events
    pellet_events = create_pellet_status_events(
        fan_state=status.get("fan_state"),
        auger_state=status.get("auger_state"),
        ignitor_state=status.get("ignitor_state"),
    )
    if pellet_events:
        events.extend(pellet_events)
    # Light control
    if "light_state" in status:
        events.append(create_light_control_event(status["light_state"]))
    # Prime control
    if "prime_state" in status:
        events.append(create_prime_control_event(status["prime_state"]))
    # Probe display (if any probe temp is present)
    probe_keys = ["p1_temp", "p2_temp", "p3_temp", "p4_temp"]
    if any(k in status for k in probe_keys):
        probe_text = ",".join(str(status.get(k, 0)) for k in probe_keys)
        events.append(create_temperature_probes_event(probe_text))
    # Temperature unit
    events.append(create_temperature_unit_event(unit))
    return events
