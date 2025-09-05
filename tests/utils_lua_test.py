"""
Lua testing utilities for SmartThings Edge driver tests.
Provides common functionality for setting up Lua runtime and bridging Python-Lua objects.
"""

import os
import sys

from lupa import LuaRuntime
from mock_device import PyDevice

# Add the tests directory to the Python path so imports work from both project root and tests directory
tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)


class LuaTestUtils:
    @staticmethod
    def require_lua_table(lua, module_name, global_name=None):
        try:
            mod = lua.eval(f'require("{module_name}")')
        except Exception:
            mod = None
            try:
                mod = lua.globals()[module_name]
            except Exception:
                mod = None
        # Check for userdata (Lupa's proxy for Lua objects)
        if hasattr(mod, "_obj"):
            # For language module, keep it as Lua table to preserve dot notation
            if module_name == "locales.en":
                # Use config.STATUS_MESSAGES instead of separate module
                if hasattr(lua.globals(), "config") and hasattr(
                    lua.globals().config, "STATUS_MESSAGES"
                ):
                    mod = lua.globals().config.STATUS_MESSAGES
                else:
                    pass  # Keep as Lua table
            else:
                # Try to convert to table if possible
                try:
                    mod = dict(mod)
                except Exception as e:
                    print(
                        f"[require_lua_table] Could not convert userdata for '{module_name}': {e}"
                    )
        if mod is None:
            raise RuntimeError(
                f"[require_lua_table] Could not load Lua module '{module_name}' as table."
            )
        # Assign to global and package.loaded
        gname = global_name or module_name
        lua.globals()[gname] = mod
        lua.execute(f'package.loaded["{module_name}"] = _G["{gname}"]')
        return mod

    """Utilities for Lua-Python testing bridge."""

    @staticmethod
    def setup_lua_runtime():
        """Set up a Lua runtime with minimal necessary mocks and dependencies."""
        import os

        lua = LuaRuntime(unpack_returned_tuples=True)

        # Always add both absolute and relative paths for mocks, mocks/st, and src
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        tests_mocks = os.path.join(base_dir, "tests", "mocks")
        tests_mocks_st = os.path.join(tests_mocks, "st")
        src_dir = os.path.join(base_dir, "src")
        locales_dir = os.path.join(base_dir, "locales")
        # Normalize for Lua (use /)
        tests_mocks_lua = tests_mocks.replace("\\", "/")
        tests_mocks_st_lua = tests_mocks_st.replace("\\", "/")
        src_dir_lua = src_dir.replace("\\", "/")
        locales_dir_lua = locales_dir.replace("\\", "/")
        # Add both absolute and relative paths
        lua.execute(
            f'package.path = package.path .. ";{tests_mocks_lua}/?.lua;{tests_mocks_st_lua}/?.lua;{src_dir_lua}/?.lua;{locales_dir_lua}/?.lua;./tests/mocks/?.lua;./tests/mocks/st/?.lua;./src/?.lua;./locales/?.lua;./mocks/?.lua;./mocks/st/?.lua"'
        )

        # Ensure working directory is project root
        project_root = base_dir
        if os.getcwd() != project_root:
            os.chdir(project_root)

        # Explicitly preload base64 module for all require calls
        base64_path = os.path.join(
            project_root, "tests", "mocks", "base64.lua"
        ).replace("\\", "/")
        lua.execute(
            f"""
local ok, mod = pcall(dofile, "{base64_path}")
if ok and mod then
    package.loaded["base64"] = mod
    package.preload["base64"] = function() return mod end
    package.loaded["tests.mocks.base64"] = mod
    package.preload["tests.mocks.base64"] = function() return mod end
end
        """
        )

        # Mock socket module for pitboss_api BEFORE loading any modules that use it
        lua.execute(
            """
            package.loaded["socket"] = {
                tcp = function()
                    return {
                        settimeout = function(self, timeout) end,
                        connect = function(self, host, port) return true end,
                        send = function(self, data) return #data end,
                        receive = function(self, pattern)
                            if pattern == "*l" then
                                return "HTTP/1.1 200 OK"
                            elseif pattern == "*a" then
                                return \'{"result": "success"}\'
                            end
                            return ""
                        end,
                        close = function(self) end
                    }
                end
            }
        """
        )

        # Preload real src modules for main dependencies
        for mod in [
            "config",
            "temperature_service",
            "device_status_service",
            "refresh_service",
            "command_service",
            "health_monitor",
            "device_manager",
            "probe_display",
            "network_utils",
            "pitboss_api",
        ]:
            src_path = os.path.join(project_root, "src", f"{mod}.lua").replace(
                "\\", "/"
            )
            lua.execute(
                f"""
local ok, realmod = pcall(dofile, "{src_path}")
if ok and realmod then
    _G["{mod}"] = realmod
    package.loaded["{mod}"] = realmod
    package.preload["{mod}"] = function() return realmod end
    -- Also register as pitboss_grill.network_utils for legacy compatibility
    if "{mod}" == "network_utils" then
        package.loaded["pitboss_grill.network_utils"] = realmod
        package.preload["pitboss_grill.network_utils"] = function() return realmod end
    end
else
    print("Warning: Failed to load {mod} from {src_path}")
end
"""
            )

        # Load language module from config.STATUS_MESSAGES
        lua.execute(
            """
if config and config.STATUS_MESSAGES then
    _G["language"] = config.STATUS_MESSAGES
    package.loaded["locales.en"] = config.STATUS_MESSAGES
    package.preload["locales.en"] = function() return config.STATUS_MESSAGES end
else
    print("Warning: config.STATUS_MESSAGES not found")
end
"""
        )

        # Load test_helpers module
        test_helpers_path = os.path.join(
            project_root, "tests", "test_helpers.lua"
        ).replace("\\", "/")
        lua.execute(
            f"""
local ok, testmod = pcall(dofile, "{test_helpers_path}")
if ok and testmod then
    _G["test_helpers"] = testmod
    package.loaded["test_helpers"] = testmod
    package.loaded["tests.test_helpers"] = testmod
    package.preload["test_helpers"] = function() return testmod end
    package.preload["tests.test_helpers"] = function() return testmod end
else
    print("Warning: Failed to load test_helpers from {test_helpers_path}")
end
"""
        )

        # Define global mocks for pitboss_api tests
        lua.execute(
            """
mock_responses = mock_responses or {}
network_should_fail = network_should_fail or false
connection_attempts = connection_attempts or {}
"""
        )

        # Determine prefix for loading files
        if os.path.exists(os.path.join(base_dir, "tests", "mocks", "log.lua")):
            tests_prefix = "tests/"
            src_prefix = "src/"
        elif os.path.exists(os.path.join(base_dir, "mocks", "log.lua")):
            tests_prefix = ""
            src_prefix = "../src/"
        else:
            raise RuntimeError(
                "Cannot find test files. Run from project root or tests directory."
            )

        # Create minimal inline mocks for problematic dependencies
        lua.execute(
            """
            -- Mock os module
            os = os or {}
            os.time = os.time or function() return 1234567890 end
            
            -- Mock capabilities
            local capabilities = {}
            capabilities.switch = {
                ID = "switch",
                switch = { 
                    NAME = "switch",
                    on = function() return {capability = "switch", attribute = "switch", value = "on"} end,
                    off = function() return {capability = "switch", attribute = "switch", value = "off"} end
                }
            }
            capabilities.temperatureMeasurement = {
                ID = "temperatureMeasurement",
                temperature = function(args) return {capability = "temperatureMeasurement", attribute = "temperature", value = args.value, unit = args.unit} end,
                temperatureRange = function(args) return {capability = "temperatureMeasurement", attribute = "temperatureRange", value = args} end
            }
            capabilities.thermostatHeatingSetpoint = {
                ID = "thermostatHeatingSetpoint",
                heatingSetpoint = function(args) return {capability = "thermostatHeatingSetpoint", attribute = "heatingSetpoint", value = args.value, unit = args.unit} end,
                heatingSetpointRange = function(args) return {capability = "thermostatHeatingSetpoint", attribute = "heatingSetpointRange", value = args} end,
                commands = {
                    setHeatingSetpoint = {
                        NAME = "setHeatingSetpoint"
                    }
                }
            }
            capabilities.powerMeter = {
                ID = "powerMeter",
                power = function(args) return {capability = "powerMeter", attribute = "power", value = args.value, unit = args.unit} end
            }
            capabilities.panicAlarm = {
                ID = "panicAlarm",
                panicAlarm = function(args) return {capability = "panicAlarm", attribute = "panicAlarm", value = args.value} end
            }
            _G["capabilities"] = capabilities
            package.loaded["st.capabilities"] = capabilities
            
            -- Mock custom capabilities
            local custom_caps = {}
            custom_caps.grillStatus = { 
                ID = "grillStatus",
                lastMessage = function(args) 
                    if type(args) == "table" and args.value then
                        return {capability = "grillStatus", attribute = "lastMessage", value = args.value}
                    else
                        return {capability = "grillStatus", attribute = "lastMessage", value = args}
                    end
                end
            }
            custom_caps.grillTemp = {
                ID = "grillTemp",
                currentTemp = function(args) return {capability = "grillTemp", attribute = "currentTemp", value = args.value, unit = args.unit} end,
                targetTemp = function(args) return {capability = "grillTemp", attribute = "targetTemp", value = args.value, unit = args.unit} end
            }
            custom_caps.temperatureProbes = {
                ID = "temperatureProbes",
                probe = function(args) return {capability = "temperatureProbes", attribute = "probe", value = args.value} end
            }
            custom_caps.pelletStatus = {
                ID = "pelletStatus",
                fanState = function(args) return {capability = "pelletStatus", attribute = "fanState", value = args.value} end,
                augerState = function(args) return {capability = "pelletStatus", attribute = "augerState", value = args.value} end,
                ignitorState = function(args) return {capability = "pelletStatus", attribute = "ignitorState", value = args.value} end
            }
            custom_caps.lightControl = {
                ID = "lightControl",
                lightState = function(args) return {capability = "lightControl", attribute = "lightState", value = args.value} end
            }
            custom_caps.primeControl = {
                ID = "primeControl",
                primeState = function(args) return {capability = "primeControl", attribute = "primeState", value = args.value} end
            }
            custom_caps.temperatureUnit = {
                ID = "temperatureUnit",
                unit = function(args) return {capability = "temperatureUnit", attribute = "unit", value = args.value} end
            }
            _G["custom_caps"] = custom_caps
            package.loaded["custom_capabilities"] = custom_caps
            

        """
        )

        # Load essential SmartThings mocks FIRST
        essential_mocks = [
            "log",
            "st/capabilities",
            "st/driver",
            "st/utils",
            "custom_capabilities",
        ]

        for dep in essential_mocks:
            if dep == "st/capabilities":
                path = f"{tests_prefix}mocks/st/capabilities.lua"
            elif dep == "custom_capabilities":
                path = f"{src_prefix}custom_capabilities.lua"
            else:
                path = f"{tests_prefix}mocks/{dep}.lua"
            lua.execute(
                f"""
                local mod = dofile("{path}")
                if mod ~= nil then
                    if "{dep}" == "st/capabilities" then
                        _G["capabilities"] = mod
                        package.loaded["st.capabilities"] = mod
                        package.loaded["capabilities"] = mod
                    elseif "{dep}" == "custom_capabilities" then
                        _G["custom_caps"] = mod
                        package.loaded["custom_capabilities"] = mod
                    else
                        _G["{dep}"] = mod
                        package.loaded["{dep}"] = mod
                    end
                end
            """
            )

        # Load source files in dependency order
        source_files = [
            "config",
            "network_utils",
            "pitboss_api",
            "temperature_service",
            "device_status_service",
            "refresh_service",
            "command_service",
            "panic_manager",
            "temperature_calibration",
            "probe_display",
            "health_monitor",
            "device_manager",
        ]

        for dep in source_files:
            path = f"{src_prefix}{dep}.lua"
            if os.path.exists(path):
                lua.execute(
                    f"""
                    local mod = dofile("{path}")
                    if mod ~= nil then
                        _G["{dep}"] = mod
                        package.loaded["{dep}"] = mod
                    end
                """
                )

        # Mock pitboss_api and device_status_service AFTER all modules are loaded
        lua.execute(
            """
            if package.loaded["pitboss_api"] then
                local original_send_command = package.loaded["pitboss_api"].send_command
                package.loaded["pitboss_api"].send_command = function(ip, command)
                    -- Mock successful response for all commands
                    return true
                end
                package.loaded["pitboss_api"].set_light = function(ip, state)
                    -- Check for network failure simulation
                    if _G.network_should_fail then
                        return false, "Network failure"
                    end
                    -- Check for invalid parameters
                    if not state or state == "" or (state ~= "on" and state ~= "off") then
                        return false, "Invalid state"
                    end
                    -- Mock successful response for set_light - record the call directly
                    local entry = {cmd = "set_light", arg = state, device = {ip = ip}}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true, nil
                end
                -- Note: set_temperature is not mocked to allow validation testing
                package.loaded["pitboss_api"].set_temperature = function(ip, temp)
                    -- Check for network failure simulation
                    if _G.network_should_fail then
                        return false, "Network failure"
                    end
                    -- Check for invalid parameters using correct config values
                    if not temp or temp == "" or type(temp) ~= "number" or temp < 160 or temp > 500 then
                        return false, "Invalid temperature"
                    end
                    -- Mock successful response for set_temperature - record the call directly
                    local entry = {cmd = "set_temperature", arg = temp, device = {ip = ip}}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true, nil
                end
                package.loaded["pitboss_api"].set_prime = function(ip, state)
                    -- Check for network failure simulation
                    if _G.network_should_fail then
                        return false, "Network failure"
                    end
                    -- Check for invalid parameters
                    if not state or state == "" or (state ~= "on" and state ~= "off") then
                        return false, "Invalid state"
                    end
                    -- Mock successful response for set_prime - record the call directly
                    local entry = {cmd = "set_prime", arg = state, device = {ip = ip}}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true, nil
                end
                package.loaded["pitboss_api"].set_power = function(ip, state)
                    -- Check for network failure simulation
                    if _G.network_should_fail then
                        return false, "Network failure"
                    end
                    -- Check for invalid parameters
                    if not state or state == "" or (state ~= "on" and state ~= "off") then
                        return false, "Invalid state"
                    end
                    -- Mock successful response for set_power - record the call directly
                    local entry = {cmd = "set_power", arg = state, device = {ip = ip}}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true, nil
                end
                package.loaded["pitboss_api"].set_unit = function(ip, unit)
                    -- Check for network failure simulation
                    if _G.network_should_fail then
                        return false, "Network failure"
                    end
                    -- Check for invalid parameters
                    if not unit or unit == "" or (unit ~= "F" and unit ~= "C") then
                        return false, "Invalid unit"
                    end
                    -- Mock successful response for set_unit - record the call directly
                    local entry = {cmd = "set_unit", arg = unit, device = {ip = ip}}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true, nil
                end
            end
            if package.loaded["device_status_service"] then
                package.loaded["device_status_service"].is_grill_on = function(device, status)
                    -- Status-based logic first (more reliable for testing)
                    if status then
                        -- If status shows grill is off (no motor, hot, or module), return false
                        if not status.motor_state and not status.hot_state and not status.module_on then
                            return false
                        end
                        -- If status shows grill components are active, return true
                        if status.motor_state or status.hot_state or status.module_on then
                            return true
                        end
                    end
                    
                    -- Fallback to device switch state
                    if device and device._latest_state then
                        return device._latest_state == "on"
                    end
                    
                    -- Final fallback to get_latest_state
                    if device then
                        local switch_state = device:get_latest_state("Standard_Grill", "st.switch", "switch")
                        return switch_state == "on"
                    end
                    
                    return false
                end
            end
            if package.loaded["network_utils"] then
                package.loaded["network_utils"].health_check = function(device, driver)
                    -- In test mode, always return true
                    return true
                end
                package.loaded["network_utils"].resolve_device_ip = function(device, retest)
                    -- Mock IP resolution - return the test IP
                    print("Mock resolve_device_ip called")
                    if device and device.preferences and device.preferences.ipAddress then
                        print("Mock resolve_device_ip returning " .. tostring(device.preferences.ipAddress))
                        return device.preferences.ipAddress
                    end
                    print("Mock resolve_device_ip returning nil")
                    return nil
                end
                package.loaded["network_utils"].send_command = function(device, command, args, driver)
                    -- Mock send_command to directly call pitboss_api functions
                    print("Mock network_utils.send_command called with command=" .. tostring(command) .. ", args=" .. tostring(args))
                    local ip = package.loaded["network_utils"].resolve_device_ip(device, false)
                    if not ip or ip == "" then
                        print("Mock send_command: No valid IP")
                        return false
                    end
                    
                    -- Execute command based on type
                    if command == "set_temperature" and args then
                        return package.loaded["pitboss_api"].set_temperature(ip, args)
                    elseif command == "set_light" and args then
                        return package.loaded["pitboss_api"].set_light(ip, args)
                    elseif command == "set_prime" and args then
                        return package.loaded["pitboss_api"].set_prime(ip, args)
                    elseif command == "set_power" and args then
                        return package.loaded["pitboss_api"].set_power(ip, args)
                    elseif command == "set_unit" and args then
                        return package.loaded["pitboss_api"].set_unit(ip, args)
                    else
                        print("Mock send_command: Unknown command type: " .. tostring(command))
                        return false
                    end
                end
                package.loaded["network_utils"].resolve_device_ip = function(device, use_cache)
                    -- Return a test IP address
                    return "192.168.1.100"
                end
                package.loaded["network_utils"].send_command = function(device, command, args, driver)
                    -- Mock successful response for all commands
                    if _G.network_should_fail then
                        return false
                    end
                    local entry = {cmd = command, arg = args, device = device}
                    -- Record to both Python recorder (if available) and global recorder
                    if _G.PYTHON_TEST_RECORDER and _G.PYTHON_TEST_RECORDER.sent then
                        table.insert(_G.PYTHON_TEST_RECORDER.sent, entry)
                    end
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    
                    return true
                end
            end
            
            -- Set test mode AFTER all modules are loaded
            _G.TEST_MODE = true
            
            -- Mock command_service functions
            if package.loaded["command_service"] then
                -- Mock initialize_command_service
                package.loaded["command_service"].initialize_command_service = function(device, driver)
                    -- Mock successful initialization
                    return true
                end
                
                -- Mock set_light function
                package.loaded["command_service"].set_light = function(device, state, driver)
                    -- Check if grill is on - return false if off
                    if device and (device.state == "off" or device._latest_state == "off") then
                        return false
                    end
                    -- Check for invalid parameters
                    if not state or state == "" or (state ~= "on" and state ~= "off") then
                        return false
                    end
                    -- Mock successful response for set_light - record the call directly
                    local entry = {cmd = "set_light", arg = state, device = device}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true
                end
                
                -- Mock set_prime function
                package.loaded["command_service"].set_prime = function(device, state, driver)
                    -- Check for invalid parameters
                    if not state or state == "" or (state ~= "on" and state ~= "off") then
                        return false
                    end
                    -- Mock successful response for set_prime - record the call directly
                    local entry = {cmd = "set_prime", arg = state, device = device}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true
                end
                
                -- Mock set_temperature function
                package.loaded["command_service"].set_temperature = function(device, temperature, driver)
                    -- Check for invalid parameters
                    if not temperature or temperature == "" or type(temperature) ~= "number" or temperature < 0 or temperature > 500 then
                        print("Mock set_temperature called with invalid temp - returning false")
                        return false
                    end
                    -- Mock successful response for set_temperature - record the call directly
                    local entry = {cmd = "set_temperature", arg = temperature, device = device}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true
                end
                
                -- Mock set_unit function
                package.loaded["command_service"].set_unit = function(device, unit, driver)
                    -- Check for invalid parameters
                    if not unit or unit == "" or (unit ~= "F" and unit ~= "C") then
                        return false
                    end
                    -- Mock successful response for set_unit - record the call directly
                    local entry = {cmd = "set_unit", arg = unit, device = device}
                    -- Record to global recorder
                    if _G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent then
                        table.insert(_G.GLOBAL_NETWORK_RECORDER.sent, entry)
                    end
                    return true
                end
            end
        """
        )

        return lua

    @staticmethod
    def create_mock_device(lua, device_id="test-device", device_label="Test Grill"):
        """Create a mock SmartThings device for testing."""
        py_device = PyDevice(device_id, device_label)

        # Convert Python device to Lua table
        lua_device = lua.table()
        lua_device.id = device_id
        lua_device.label = device_label
        lua_device.preferences = lua.table()
        lua_device.profile = lua.table()
        lua_device.profile.id = "test-profile"

        # Add mock methods
        lua_device.emit_event = lambda event: py_device.emit_event(event)
        lua_device.set_field = lambda key, value, persist: py_device.set_field(
            key, value, persist
        )
        lua_device.get_field = lambda key: py_device.get_field(key)
        lua_device.online = lambda: py_device.online()
        lua_device.offline = lambda: py_device.offline()

        return lua_device, py_device

    @staticmethod
    def to_lua_table(lua, python_dict):
        """Convert a Python dictionary to a Lua table."""
        if python_dict is None:
            return None

        lua_table = lua.table()
        for key, value in python_dict.items():
            if isinstance(value, dict):
                lua_table[key] = LuaTestUtils.to_lua_table(lua, value)
            elif isinstance(value, list):
                lua_array = lua.table()
                for i, item in enumerate(value, 1):  # Lua arrays are 1-indexed
                    if isinstance(item, dict):
                        lua_array[i] = LuaTestUtils.to_lua_table(lua, item)
                    else:
                        lua_array[i] = item
                lua_table[key] = lua_array
            else:
                lua_table[key] = value
        return lua_table

    @staticmethod
    def from_lua_table(lua_table):
        """Convert a Lua table to a Python dictionary."""
        if lua_table is None:
            return None

        result = {}
        for key, value in lua_table.items():
            if hasattr(value, "items"):  # It's a Lua table
                result[key] = LuaTestUtils.from_lua_table(value)
            else:
                result[key] = value
        return result

    @staticmethod
    def find_event(events, event_name=None, event_value=None, attribute=None):
        """Find an event in a list of events. Matches on capability or attribute name."""
        for event in events:
            if event_name:
                # Match if either capability or attribute matches event_name
                if (
                    event.get("capability") != event_name
                    and event.get("attribute") != event_name
                ):
                    continue
            if attribute and event.get("attribute") != attribute:
                continue
            if event_value is not None and str(event.get("value")) != str(event_value):
                continue
            return event
        return None

    @staticmethod
    def find_component_event(
        component_events,
        component_id,
        event_name=None,
        event_value=None,
        attribute=None,
    ):
        """Find a component event. Matches on capability or attribute name."""
        for ce in component_events:
            if ce.get("component") != component_id:
                continue
            event = ce.get("event", {})
            if event_name:
                # Check capability, name, or attribute fields
                if (
                    event.get("capability") != event_name
                    and event.get("name") != event_name
                    and event.get("attribute") != event_name
                ):
                    continue
            if attribute and event.get("attribute") != attribute:
                continue
            if event_value is not None and str(event.get("value")) != str(event_value):
                continue
            return event
        return None

    @staticmethod
    def is_switch_off(event):
        """Check if an event is a switch off event."""
        return (
            event.get("capability") == "st.switch"
            and (event.get("name") == "switch" or event.get("attribute") == "switch")
            and event.get("value") == "off"
        )

    @staticmethod
    def convert_device_to_lua(lua, py_device):
        """Convert a PyDevice to a Lua table that can be used in Lua tests."""
        # Create a Lua table that mimics a SmartThings device
        device_table = lua.table()

        # Add basic device properties
        device_table.id = py_device.preferences.get("deviceId", "test-device-id")
        device_table.label = py_device.preferences.get("deviceLabel", "Test Grill")
        device_table.profile = LuaTestUtils.to_lua_table(lua, py_device.profile)
        device_table.preferences = LuaTestUtils.to_lua_table(lua, py_device.preferences)

        # Add fields table
        device_table.fields = lua.table()
        for key, value in py_device.fields.items():
            device_table.fields[key] = value

        # Add thread and other missing fields
        device_table.thread = py_device.thread
        device_table.state = py_device.state
        device_table.switch_state = py_device.switch_state
        device_table._latest_state = py_device._latest_state
        device_table.is_on = py_device.is_on

        # Add device methods as Lua functions
        def lua_get_field(*args):
            if len(args) == 2:  # Called from Lua: device:get_field(key)
                self, key = args
                return py_device.get_field(key)
            elif len(args) == 1:  # Called from Python: device.get_field(key)
                key = args[0]
                return py_device.get_field(key)
            else:
                raise TypeError(
                    f"lua_get_field expected 1-2 arguments, got {len(args)}"
                )

        def lua_set_field(*args):
            if len(args) == 4:  # Called from Lua: device:set_field(key, value, options)
                self, key, value, options = args
                return py_device.set_field(key, value, options)
            elif (
                len(args) == 3
            ):  # Called from Lua: device:set_field(key, value) or Python: device.set_field(key, value, options)
                if hasattr(args[2], "__dict__") or isinstance(
                    args[2], dict
                ):  # options dict
                    key, value, options = args
                else:
                    self, key, value = args
                    options = None
                return py_device.set_field(key, value, options)
            elif len(args) == 2:  # Called from Python: device.set_field(key, value)
                key, value = args
                return py_device.set_field(key, value)
            else:
                raise TypeError(
                    f"lua_set_field expected 2-4 arguments, got {len(args)}"
                )

        def lua_emit_event(*args):
            if len(args) == 2:  # Called from Lua: device:emit_event(event)
                self, event = args
                return py_device.emit_event(event)
            elif len(args) == 1:  # Called from Python: device.emit_event(event)
                event = args[0]
                return py_device.emit_event(event)
            else:
                raise TypeError(
                    f"lua_emit_event expected 1-2 arguments, got {len(args)}"
                )

        def lua_emit_component_event(*args):
            if (
                len(args) == 3
            ):  # Called from Lua: device:emit_component_event(component, event)
                self, component, event = args
                return py_device.emit_component_event(component, event)
            elif (
                len(args) == 2
            ):  # Called from Python: device.emit_component_event(component, event)
                component, event = args
                return py_device.emit_component_event(component, event)
            else:
                raise TypeError(
                    f"lua_emit_component_event expected 2-3 arguments, got {len(args)}"
                )

        def lua_get_latest_state(*args):
            if (
                len(args) == 4
            ):  # Called from Lua: device:get_latest_state(component, capability, attribute)
                self, component, capability, attribute = args
                return py_device.get_latest_state(component, capability, attribute)
            elif (
                len(args) == 3
            ):  # Called from Python: device.get_latest_state(component, capability, attribute)
                component, capability, attribute = args
                return py_device.get_latest_state(component, capability, attribute)
            else:
                raise TypeError(
                    f"lua_get_latest_state expected 3-4 arguments, got {len(args)}"
                )

        def lua_online(self):
            return py_device.online()

        def lua_offline(self):
            return py_device.offline()

        # Bind methods to the Lua table
        device_table.get_field = lua_get_field
        device_table.set_field = lua_set_field
        device_table.emit_event = lua_emit_event
        device_table.emit_component_event = lua_emit_component_event
        device_table.get_latest_state = lua_get_latest_state
        device_table.online = lua_online
        device_table.offline = lua_offline

        return device_table

    @staticmethod
    def convert_lua_to_py(lua, lua_device):
        """Convert a Lua device table back to a PyDevice for testing."""
        # Create a new PyDevice with the same initial state
        py_device = PyDevice()

        # Copy fields from Lua device
        if hasattr(lua_device, "fields") and lua_device.fields:
            for key, value in lua_device.fields.items():
                py_device.set_field(key, value)

        # Copy profile and preferences
        if hasattr(lua_device, "profile"):
            py_device.profile = LuaTestUtils.from_lua_table(lua_device.profile)
        if hasattr(lua_device, "preferences"):
            py_device.preferences = LuaTestUtils.from_lua_table(lua_device.preferences)

        # Copy events and component events
        if hasattr(lua_device, "events"):
            py_device.events = LuaTestUtils.from_lua_table(lua_device.events)
        if hasattr(lua_device, "component_events"):
            py_device.component_events = LuaTestUtils.from_lua_table(
                lua_device.component_events
            )

        return py_device

    @staticmethod
    def extract_event_value(event):
        """Extract the value from an event, handling different event formats."""
        if event is None:
            return None

        # Try different ways to get the value
        if "value" in event:
            value = event["value"]
            # If value is a dict with 'value' key, extract it
            if isinstance(value, dict) and "value" in value:
                return value["value"]
            return value

        # Fallback to checking for value in nested structures
        for key in ["data", "event"]:
            if key in event and isinstance(event[key], dict):
                if "value" in event[key]:
                    return event[key]["value"]

        return None
