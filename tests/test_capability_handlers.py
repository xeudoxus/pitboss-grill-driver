from base_test_classes import LuaTestBase


class TestCapabilityHandlers(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        """Load capability_handlers module with all its dependencies."""
        # Load all the dependencies that capability_handlers needs
        try:
            cls.lua.eval('require("custom_capabilities")')
            cls.lua.eval('require("device_status_service")')
            cls.lua.eval('require("command_service")')
            cls.lua.eval('require("virtual_device_manager")')
            cls.lua.eval('require("refresh_service")')
            # Now load capability_handlers
            result = cls.lua.eval('require("capability_handlers")')
            if isinstance(result, tuple):
                cls.capability_handlers = result[
                    0
                ]  # Take the first element (the Lua table)
            else:
                cls.capability_handlers = result
        except Exception as e:
            print(f"Failed to load capability_handlers: {e}")
            cls.capability_handlers = None

    def setUp(self):
        """Set up test-specific state."""
        super().setUp()
        # Additional setup specific to capability handlers can go here
        self.mock_driver = self.to_lua_table({})
        # Initialize command tracking
        self.lua.execute("command_sent = {}")
        # Initialize call counters
        self.lua.execute("refresh_calls = 0")
        self.lua.execute("refresh_from_status_calls = 0")
        self.lua.execute("update_offline_status_calls = 0")
        self.lua.execute("is_grill_on_calls = 0")
        self.lua.execute("update_virtual_devices_calls = 0")

        # Patch command_service to track calls
        self.lua.execute(
            """
        if package.loaded["command_service"] then
            -- Replace functions in the original module
            local original_send_temperature_command = package.loaded["command_service"].send_temperature_command
            package.loaded["command_service"].send_temperature_command = function(device, temp)
                table.insert(command_sent, {type = "temperature", value = temp})
                return true
            end

            local original_send_light_command = package.loaded["command_service"].send_light_command
            package.loaded["command_service"].send_light_command = function(device, state)
                table.insert(command_sent, {type = "light", value = state})
                return true
            end

            local original_send_prime_command = package.loaded["command_service"].send_prime_command
            package.loaded["command_service"].send_prime_command = function(device, state)
                table.insert(command_sent, {type = "prime", value = state})
                return true
            end

            local original_send_unit_command = package.loaded["command_service"].send_unit_command
            package.loaded["command_service"].send_unit_command = function(device, unit)
                table.insert(command_sent, {type = "unit", value = unit})
                return true
            end

            local original_send_power_command = package.loaded["command_service"].send_power_command
            package.loaded["command_service"].send_power_command = function(device, state)
                table.insert(command_sent, {type = "power", value = state})
                return true
            end

            -- Mock schedule_refresh to avoid calling refresh_device
            package.loaded["command_service"].schedule_refresh = function(device, command)
                -- Do nothing to avoid refresh_device call
                return true
            end
        end

        -- Patch refresh_service to track calls
        if package.loaded["refresh_service"] then
            -- Replace functions in the original module
            local original_refresh_device = package.loaded["refresh_service"].refresh_device
            package.loaded["refresh_service"].refresh_device = function(device, command)
                refresh_calls = refresh_calls + 1
                -- Handle case where command might not have 'command' key
                if command and command.command then
                    -- Manual refresh logic here if needed
                end
                return true
            end

            local original_refresh_from_status = package.loaded["refresh_service"].refresh_from_status
            package.loaded["refresh_service"].refresh_from_status = function(device, status)
                refresh_from_status_calls = refresh_from_status_calls + 1
                return true
            end
        end

        -- Patch device_status_service to track calls
        if package.loaded["device_status_service"] then
            -- Replace functions in the original module
            local original_update_offline_status = package.loaded["device_status_service"].update_offline_status
            package.loaded["device_status_service"].update_offline_status = function(device)
                update_offline_status_calls = update_offline_status_calls + 1
                return true
            end

            local original_is_grill_on = package.loaded["device_status_service"].is_grill_on
            package.loaded["device_status_service"].is_grill_on = function(device, status)
                is_grill_on_calls = is_grill_on_calls + 1
                return true
            end
        end

        -- Patch virtual_device_manager to track calls
        if package.loaded["virtual_device_manager"] then
            -- Replace functions in the original module
            local original_update_virtual_devices = package.loaded["virtual_device_manager"].update_virtual_devices
            package.loaded["virtual_device_manager"].update_virtual_devices = function(device, status)
                update_virtual_devices_calls = update_virtual_devices_calls + 1
                return true
            end
        end
        """
        )

    def tearDown(self):
        """Clean up and export coverage data."""
        # Export coverage data after test completes
        if hasattr(self, "lua_coverage_enabled") and self.lua_coverage_enabled:
            coverage_data = self.export_lua_coverage("lua_coverage.json")
            if coverage_data:
                print(
                    f"\nLua coverage data exported with {len(coverage_data)} files tracked"
                )
        super().tearDown()

    def create_virtual_device_lua(self, child_key):
        """Create a proper Lua virtual device with parent_assigned_child_key"""
        virtual_device = (
            self.py_device.__class__()
        )  # Create a new instance of the same type
        virtual_device.parent_assigned_child_key = child_key
        virtual_device.get_parent_device = lambda *a, **k: self.lua_device

        # Convert to Lua device
        lua_virtual_device = self.utils.convert_device_to_lua(self.lua, virtual_device)

        self.lua.execute(
            f"""
        -- Set the child key directly on the Lua device object
        local device = ...
        device.parent_assigned_child_key = "{child_key}"

        -- Also ensure get_parent_device works
        device.get_parent_device = function(self)
            return parent_device
        end
        """,
            lua_virtual_device,
        )

        # Store parent device reference for the get_parent_device function
        self.lua.execute("parent_device = ...", self.lua_device)

        return lua_virtual_device

    def get_command_sent(self):
        """Helper method to get the command_sent table from Lua"""
        lua_commands = self.lua.eval("command_sent")
        # Convert Lua table to Python list of dicts
        commands = []
        if lua_commands:
            for i in range(1, len(lua_commands) + 1):  # Lua arrays are 1-indexed
                lua_cmd = lua_commands[i]
                if lua_cmd:
                    commands.append(
                        {"type": lua_cmd["type"], "value": lua_cmd["value"]}
                    )
        return commands

    def get_command_sent_count(self):
        """Helper method to get the count of commands sent"""
        return self.lua.eval("#command_sent")

    def test_debug_services(self):
        # Test command_service directly
        cs = self.lua.eval('require("command_service")')
        self.assertIsNotNone(cs, "command_service module not loaded")
        self.assertTrue(
            hasattr(cs, "send_temperature_command"),
            "send_temperature_command not found in command_service",
        )
        cs.send_temperature_command(self.lua_device, 123)
        commands = self.get_command_sent()
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0]["type"], "temperature")
        self.assertEqual(commands[0]["value"], 123)

        # Test refresh_service directly
        rs = self.lua.eval('require("refresh_service")')
        self.assertIsNotNone(rs, "refresh_service module not loaded")
        self.assertTrue(
            hasattr(rs, "refresh_device"), "refresh_device not found in refresh_service"
        )
        rs.refresh_device(self.lua_device, {"command": "refresh"})
        calls = self.lua.eval("refresh_calls")
        self.assertEqual(calls, 1)

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.capability_handlers,
            "capability_handlers module not loaded or not returned as a table",
        )

        if self.capability_handlers:
            handler_funcs = []
            try:
                # Try to get all keys from the Lua table
                for key in self.capability_handlers:
                    handler_funcs.append(key)
            except Exception as e:
                print(f"  Error getting functions: {e}")
                # Alternative: try to access known function names
                known_funcs = [
                    "thermostat_setpoint_handler",
                    "switch_handler",
                    "light_control_handler",
                    "prime_control_handler",
                    "temperature_unit_handler",
                    "refresh_handler",
                    "virtual_switch_handler",
                    "virtual_thermostat_handler",
                ]
                for func_name in known_funcs:
                    try:
                        func = getattr(self.capability_handlers, func_name)
                        if func:
                            handler_funcs.append(func_name)
                    except AttributeError:
                        pass

    def test_thermostat_setpoint_handler(self):
        self.capability_handlers.thermostat_setpoint_handler(
            self.mock_driver, self.lua_device, {"args": {"setpoint": 100}}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "temperature")
        self.assertEqual(command_sent[0]["value"], 100)

    def test_switch_handler(self):
        self.capability_handlers.switch_handler(
            self.mock_driver, self.lua_device, {"command": "on"}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "power")
        self.assertEqual(command_sent[0]["value"], "on")

    def test_light_control_handler(self):
        self.capability_handlers.light_control_handler(
            self.mock_driver, self.lua_device, {"args": {"state": "ON"}}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "light")
        self.assertEqual(command_sent[0]["value"], "ON")

    def test_prime_control_handler(self):
        self.capability_handlers.prime_control_handler(
            self.mock_driver, self.lua_device, {"args": {"state": "ON"}}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "prime")
        self.assertEqual(command_sent[0]["value"], "ON")

    def test_temperature_unit_handler(self):
        self.capability_handlers.temperature_unit_handler(
            self.mock_driver, self.lua_device, {"args": {"state": "C"}}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "unit")
        self.assertEqual(command_sent[0]["value"], "C")

    def test_refresh_handler(self):
        self.lua.execute("refresh_calls = 0")
        # Provide a command dict with 'command' key to avoid KeyError
        self.capability_handlers.refresh_handler(
            self.mock_driver, self.lua_device, {"command": "refresh"}
        )
        refresh_calls = self.lua.eval("refresh_calls")
        self.assertEqual(refresh_calls, 1)

    def test_update_device_from_status(self):
        self.lua.execute("refresh_from_status_calls = 0")
        # Provide a status dict with all required keys
        status = {
            "is_fahrenheit": True,
            "grill_temp": 200,
            "set_temp": 200,
            "p1_temp": 100,  # Use 0 for disconnected/off
            "p2_temp": 100,  # Use 0 for disconnected/off
            "p3_temp": 100,  # Use 0 for disconnected/off
            "p4_temp": 100,  # Use 0 for disconnected/off
            "motor_state": True,
            "hot_state": True,
            "module_on": True,
            "fan_state": True,
            "light_state": True,
            "prime_state": True,
            "auger_state": True,
            "ignitor_state": True,
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
        self.capability_handlers.update_device_from_status(self.lua_device, status)
        refresh_from_status_calls = self.lua.eval("refresh_from_status_calls")
        self.assertEqual(refresh_from_status_calls, 1)

    def test_virtual_switch_handler_light(self):
        lua_virtual_light = self.create_virtual_device_lua("virtual-light")
        self.capability_handlers.virtual_switch_handler(
            self.mock_driver, lua_virtual_light, {"command": "on"}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "light")
        self.assertEqual(command_sent[0]["value"], "ON")

    def test_virtual_switch_handler_prime(self):
        lua_virtual_prime = self.create_virtual_device_lua("virtual-prime")
        self.capability_handlers.virtual_switch_handler(
            self.mock_driver, lua_virtual_prime, {"command": "on"}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "prime")
        self.assertEqual(command_sent[0]["value"], "ON")

    def test_virtual_switch_handler_main(self):
        lua_virtual_main = self.create_virtual_device_lua("virtual-main")
        self.capability_handlers.virtual_switch_handler(
            self.mock_driver, lua_virtual_main, {"command": "on"}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "power")
        self.assertEqual(command_sent[0]["value"], "on")

    def test_virtual_thermostat_handler_main(self):
        lua_virtual_main_thermo = self.create_virtual_device_lua("virtual-main")
        self.capability_handlers.virtual_thermostat_handler(
            self.mock_driver, lua_virtual_main_thermo, {"args": {"setpoint": 100}}
        )
        command_sent = self.get_command_sent()
        self.assertEqual(len(command_sent), 1)
        self.assertEqual(command_sent[0]["type"], "temperature")
        self.assertEqual(command_sent[0]["value"], 100)

    def test_update_virtual_devices(self):
        self.lua.execute("update_virtual_devices_calls = 0")
        self.capability_handlers.update_virtual_devices(self.lua_device, {})
        update_virtual_devices_calls = self.lua.eval("update_virtual_devices_calls")
        self.assertEqual(update_virtual_devices_calls, 1)

    def test_is_grill_on_from_status(self):
        self.lua.execute("is_grill_on_calls = 0")
        status = {"motor_state": True}
        result = self.capability_handlers.is_grill_on_from_status(
            self.lua_device, status
        )
        is_grill_on_calls = self.lua.eval("is_grill_on_calls")
        self.assertEqual(is_grill_on_calls, 1)
        self.assertTrue(result)

    def test_update_device_panic_status(self):
        self.lua.execute("update_offline_status_calls = 0")
        self.capability_handlers.update_device_panic_status(self.lua_device)
        update_offline_status_calls = self.lua.eval("update_offline_status_calls")
        self.assertEqual(update_offline_status_calls, 1)

    def test_grill_status_handler(self):
        self.assertTrue(hasattr(self.capability_handlers, "grill_status_handler"))
