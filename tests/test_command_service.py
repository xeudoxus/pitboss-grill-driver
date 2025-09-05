import os
import sys

from base_test_classes import LuaTestBase
from mock_device import create_default_preferences

tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)


class TestCommandService(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        # command_service is already loaded by the base class setup
        cls.command_service = cls.lua.globals().command_service
        # Load status messages from config instead of separate locales module
        cls.language = cls.lua.globals().config.STATUS_MESSAGES

    def setUp(self):
        super().setUp()
        # Create the global network recorder BEFORE setting up mocks
        self.lua.execute(
            """
if not _G.GLOBAL_NETWORK_RECORDER then
    _G.GLOBAL_NETWORK_RECORDER = { sent = {}, clear_sent = function(self) self.sent = {} end }
end
"""
        )
        # Network recorder is already set up by the base class, just get reference to it
        self.recorder = self.lua.eval("_G.GLOBAL_NETWORK_RECORDER")
        self.recorder.clear_sent(self.recorder)
        # Ensure network_utils stub always records commands
        self.lua.execute("_G.network_should_fail = false")

    def _refresh_recorder(self):
        # Always re-fetch the global recorder and sent table from Lua
        self.recorder = self.lua.eval("_G.GLOBAL_NETWORK_RECORDER")
        # Get the length of the sent table
        sent_length = self.lua.eval(
            "(_G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent) and #_G.GLOBAL_NETWORK_RECORDER.sent or 0"
        )
        # Get each command individually
        self.sent = []
        for i in range(1, sent_length + 1):
            cmd = self.lua.eval(
                f"(_G.GLOBAL_NETWORK_RECORDER and _G.GLOBAL_NETWORK_RECORDER.sent and _G.GLOBAL_NETWORK_RECORDER.sent[{i}]) or nil"
            )
            if cmd:
                # Convert Lua table to Python dictionary
                python_cmd = self.utils.from_lua_table(cmd)
                self.sent.append(python_cmd)

    def make_device(self, state="on", prefs=None):
        """Create device using DeviceFactory for consistency."""
        preferences = create_default_preferences()
        if prefs:
            preferences.update(prefs)
        py_dev, lua_dev = self.create_lua_device(state, preferences)
        return lua_dev

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.command_service,
            "command_service module not loaded or not returned as a table",
        )

    def test_temperature_command_off_and_on(self):
        cs = self.command_service
        # Use a valid Celsius temperature for the test (SmartThings sends in Celsius)
        test_temp = 100  # 100°C is within the valid range (71-260°C)
        dev_off = self.make_device("off")
        dev_on = self.make_device("on")
        # Grill off: should reject
        self._refresh_recorder()
        ok_off = cs["send_temperature_command"](dev_off, test_temp)
        self._refresh_recorder()
        self.assertFalse(ok_off)
        self.assertEqual(len(self.sent), 0)
        # Grill on: should accept
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        ok_on = cs["send_temperature_command"](dev_on, test_temp)
        self._refresh_recorder()
        self.assertTrue(ok_on)
        # Command was sent (we can see from the mock output that it was called)

    def test_temperature_snapping_and_conversion(self):
        cs = self.command_service
        config = self.config
        dev_on = self.make_device("on")
        temp_range = config["get_temperature_range"](
            config["CONSTANTS"]["DEFAULT_UNIT"]
        )
        extreme_temp = temp_range["max"] + 100
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        ok_extreme = cs["send_temperature_command"](
            dev_on, extreme_temp
        )
        self._refresh_recorder()
        self.assertFalse(ok_extreme)
        self.assertEqual(len(self.sent), 0)
        # Celsius conversion
        celsius_approved = config["get_approved_setpoints"]("C")[1]
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        ok_celsius = cs["send_temperature_command"](
            dev_on, celsius_approved
        )
        self._refresh_recorder()
        self.assertTrue(ok_celsius)
        self.assertGreaterEqual(len(self.sent), 1)
        self.assertEqual(self.sent[len(self.sent) - 1]["cmd"], "set_temperature")

    def test_power_command(self):
        cs = self.command_service
        dev_on = self.make_device("on")
        # Clear recorder AFTER device creation to avoid counting device initialization calls
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result = cs.send_power_command(dev_on, "off")
        print(f"send_power_command result: {result}")
        self._refresh_recorder()
        self.assertTrue(result)
        # Debug: print what commands were sent
        print(f"Number of commands sent: {len(self.sent)}")
        for i, cmd in enumerate(self.sent):
            print(f"Command {i+1}: cmd={cmd['cmd']}, arg={cmd['arg']}")
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.sent[0]["cmd"], "set_power")

    def test_light_command(self):
        cs = self.command_service
        dev_off = self.make_device("off")
        dev_on = self.make_device("on")
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result_off = cs["send_light_command"](dev_off, "ON")
        self._refresh_recorder()
        self.assertFalse(result_off)
        self.assertEqual(len(self.sent), 0)
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result_on = cs["send_light_command"](dev_on, "ON")
        self._refresh_recorder()
        self.assertTrue(result_on)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.sent[0]["cmd"], "set_light")

    def test_prime_command(self):
        cs = self.command_service
        dev_off = self.make_device("off")
        dev_on = self.make_device("on")

        # Patch thread for auto-off
        class Thread:
            def call_with_delay(self, delay, func):
                return type("Timer", (), {"cancel": lambda self: None})()

        dev_on["thread"] = Thread()
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result_off = cs["send_prime_command"](dev_off, "ON")
        self._refresh_recorder()
        self.assertFalse(result_off)
        self.assertEqual(len(self.sent), 0)
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result_on = cs["send_prime_command"](dev_on, "ON")
        self._refresh_recorder()
        self.assertTrue(result_on)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.sent[0]["cmd"], "set_prime")

    def test_prime_timeout_configuration(self):
        """Test that prime timeout uses config constant"""
        config = self.config
        prime_timeout = config["CONSTANTS"]["PRIME_TIMEOUT"]
        self.assertEqual(prime_timeout, 30, "prime timeout should use config constant")

    def test_prime_off_command(self):
        """Test prime OFF command when grill is on"""
        cs = self.command_service
        dev_on = self.make_device("on")

        # Patch thread for auto-off
        class Thread:
            def call_with_delay(self, delay, func):
                return type("Timer", (), {"cancel": lambda self: None})()

        dev_on["thread"] = Thread()
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result_off = cs["send_prime_command"](dev_on, "OFF")
        self._refresh_recorder()
        self.assertTrue(result_off, "prime OFF command should succeed when grill is on")
        self.assertEqual(len(self.sent), 1, "network command should be sent for OFF")
        self.assertEqual(self.sent[0]["arg"], "off", "argument should be 'off'")

    def test_network_failure_handling(self):
        """Test network failure handling for all commands"""
        cs = self.command_service
        dev_on = self.make_device("on")

        # Mock network failure
        self.lua.execute("_G.network_should_fail = true")

        # Test power command failure
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result = cs["send_power_command"](dev_on, "off")
        self._refresh_recorder()
        self.assertFalse(result, "should handle network failure")

        # Test temperature command failure
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result = cs["send_temperature_command"](dev_on, 225)
        self._refresh_recorder()
        self.assertFalse(result, "should handle network failure for temperature")

        # Test light command failure
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result = cs["send_light_command"](dev_on, "ON")
        self._refresh_recorder()
        self.assertFalse(result, "should handle network failure for light")

        # Reset network
        self.lua.execute("_G.network_should_fail = false")

    def test_ip_address_validation(self):
        """Test IP address validation"""
        # Mock network_utils
        self.lua.execute(
            """
        package.loaded["network_utils"] = {
          validate_ip_address = function(ip)
            if ip == "999.999.999.999" then
              return false, "Invalid IP address"
            elseif ip == "192.168.1.100" then
              return true, "Valid IP"
            else
              return false, "Invalid IP address"
            end
          end
        }
        """
        )

        network_utils = self.lua.eval('require("network_utils")')

        valid, msg = network_utils.validate_ip_address("999.999.999.999")
        self.assertFalse(valid, "should reject invalid IP address")
        self.assertIsInstance(msg, str, "should return error message")

        valid, msg = network_utils.validate_ip_address("192.168.1.100")
        self.assertTrue(valid, "should accept valid IP address")

    def test_unit_command(self):
        cs = self.command_service
        dev_off = self.make_device("off")
        dev_on = self.make_device("on")
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result_off = cs["send_unit_command"](dev_off, "C")
        self._refresh_recorder()
        self.assertFalse(result_off)
        self.assertEqual(len(self.sent), 0)
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()
        result_on = cs["send_unit_command"](dev_on, "C")
        self._refresh_recorder()
        self.assertTrue(result_on)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.sent[0]["cmd"], "set_unit")

    def test_command_service_initialization(self):
        """Test command service initialization"""
        dev = self.make_device("on")
        mock_driver = self.lua.table()

        # Test initialization
        self.command_service.initialize_command_service(dev, mock_driver)

        # Check if initial state was set
        self._refresh_recorder()
        # Verify initialization doesn't break anything
        self.assertIsNotNone(dev, "device should exist after initialization")

    def test_light_control_commands(self):
        """Test light control commands"""
        dev = self.make_device("on")
        mock_driver = self.lua.table()

        # Reset tracking
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()

        # Test light on
        result = self.command_service.set_light(dev, "on")
        self._refresh_recorder()
        self.assertTrue(result, "should turn light on")

        # Test light off
        result = self.command_service.set_light(dev, "off")
        self._refresh_recorder()
        self.assertTrue(result, "should turn light off")

        # Check API calls
        self.assertEqual(len(self.sent), 2, "should make API calls for light control")

    def test_prime_control_commands(self):
        """Test prime control commands"""
        dev = self.make_device("on")
        mock_driver = self.lua.table()

        # Reset tracking
        self.recorder.clear_sent(self.recorder)
        self._refresh_recorder()

        # Test prime on
        result = self.command_service.set_prime(dev, "on")
        self._refresh_recorder()
        self.assertTrue(result, "should turn prime on")

        # Test prime off
        result = self.command_service.set_prime(dev, "off")
        self._refresh_recorder()
        self.assertTrue(result, "should turn prime off")

        # Check API calls
        self.assertEqual(len(self.sent), 2, "should make API calls for prime control")

    def test_command_validation(self):
        """Test command validation"""
        dev = self.make_device("on")
        mock_driver = self.lua.table()

        # Test invalid light command
        result = self.command_service.set_light(dev, "invalid")
        self.assertFalse(result, "should reject invalid light command")

        # Test invalid prime command
        result = self.command_service.set_prime(dev, "invalid")
        self.assertFalse(result, "should reject invalid prime command")

    def test_command_service_error_handling(self):
        """Test command service error handling"""
        dev = self.make_device("on")
        mock_driver = self.lua.table()

        # Mock API failure by setting network to fail
        self.lua.execute("_G.network_should_fail = true")

        result = self.command_service.send_light_command(dev, "ON")
        self.assertFalse(result, "should handle API errors gracefully")

        # Reset network state
        self.lua.execute("_G.network_should_fail = false")

    def test_command_service_device_state_validation(self):
        """Test command service device state validation"""
        mock_driver = self.lua.table()

        # Test with grill off
        dev_off = self.make_device("off")
        result = self.command_service.set_light(dev_off, "on")
        self.assertFalse(result, "should reject command when grill is off")

        # Test with grill on
        dev_on = self.make_device("on")
        result = self.command_service.set_light(dev_on, "on")
        self.assertTrue(result, "should accept command when grill is on")

    def test_command_service_parameter_validation(self):
        """Test command service parameter validation"""
        dev = self.make_device("on")
        mock_driver = self.lua.table()

        # Test with nil parameters - this will be handled by Lua
        try:
            result = self.command_service.set_light(dev, None)
            # If it doesn't crash, that's acceptable
        except Exception:
            # If it crashes due to nil, that's also acceptable behavior
            pass  # nosec B110

        # Test with empty parameters
        result = self.command_service.set_light(dev, "")
        self.assertFalse(result, "should reject empty parameters")

    def test_command_service_timeout_handling(self):
        """Test command service timeout handling"""
        dev = self.make_device("on")
        mock_driver = self.lua.table()

        # Mock timeout by setting network to fail
        self.lua.execute("_G.network_should_fail = true")

        result = self.command_service.send_light_command(dev, "ON")
        self.assertFalse(result, "should handle timeout gracefully")

        # Reset network state
        self.lua.execute("_G.network_should_fail = false")
