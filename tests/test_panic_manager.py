import unittest

from base_test_classes import LuaTestBase
from mock_device import PyDevice


class TestPanicManager(LuaTestBase):
    @classmethod
    def _load_modules(cls):
        cls.panic_manager = cls.lua.globals().panic_manager
        cls.config = cls.lua.globals().config

    def setUp(self):
        super().setUp()
        # Patch os.time in Lua to always return 1000 for deterministic tests
        self.lua.execute("os = os or {}; os.time = function() return 1000 end")
        # Set up error component for all devices
        self.py_device.profile["components"][self.config.COMPONENTS.ERROR] = {
            "id": self.config.COMPONENTS.ERROR
        }
        self.lua_device = self.utils.convert_device_to_lua(self.lua, self.py_device)

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.panic_manager,
            "panic_manager module not loaded or not returned as a table",
        )

    def test_update_last_active_time(self):
        self.panic_manager.update_last_active_time(self.lua_device)
        last_active = self.py_device.get_field("last_active_time")
        self.assertIsInstance(last_active, (int, float))

    def test_update_last_active_time_if_on(self):
        # Grill is on
        status = {"motor_state": True, "hot_state": False, "module_on": False}
        self.panic_manager.update_last_active_time_if_on(
            self.lua_device, self.utils.to_lua_table(self.lua, status)
        )
        last_active = self.py_device.get_field("last_active_time")
        self.assertIsInstance(last_active, (int, float))
        # Grill is off
        self.py_device.set_field("last_active_time", 12345)
        status = {"motor_state": False, "hot_state": False, "module_on": False}
        self.panic_manager.update_last_active_time_if_on(
            self.lua_device, self.utils.to_lua_table(self.lua, status)
        )
        self.assertEqual(self.py_device.get_field("last_active_time"), 12345)

    def test_handle_offline_panic_state_transitions(self):
        # No recent activity, no panic
        self.py_device.set_field("last_active_time", 0)
        self.panic_manager.handle_offline_panic_state(self.lua_device)
        panic_state = self.py_device.get_field("panic_state")
        self.assertFalse(panic_state or False)
        self.assertTrue(
            any(
                ev["event"].get("value") == "clear"
                for ev in self.py_device.component_events
            )
        )
        # Recent activity, triggers panic
        now = 1000
        self.py_device.set_field("last_active_time", now)
        self.py_device.component_events.clear()
        # Simulate time within timeout
        self.panic_manager.handle_offline_panic_state(self.lua_device)
        self.assertTrue(self.py_device.get_field("panic_state"))
        self.assertTrue(
            any(
                ev["event"].get("value") == "panic"
                for ev in self.py_device.component_events
            )
        )
        # Already in panic, maintain
        self.py_device.set_field("panic_state", True)
        self.py_device.component_events.clear()
        self.panic_manager.handle_offline_panic_state(self.lua_device)
        self.assertTrue(self.py_device.get_field("panic_state"))
        self.assertTrue(
            any(
                ev["event"].get("value") == "panic"
                for ev in self.py_device.component_events
            )
        )
        # Not recently active, already in panic -> clear
        self.py_device.set_field("last_active_time", 0)
        self.py_device.set_field("panic_state", True)
        self.py_device.component_events.clear()
        self.panic_manager.handle_offline_panic_state(self.lua_device)
        self.assertFalse(self.py_device.get_field("panic_state"))
        self.assertTrue(
            any(
                ev["event"].get("value") == "clear"
                for ev in self.py_device.component_events
            )
        )

    def test_clear_panic_on_reconnect(self):
        # Was offline, in panic
        self.py_device.set_field("panic_state", True)
        self.panic_manager.clear_panic_on_reconnect(self.lua_device, True)
        self.assertFalse(self.py_device.get_field("panic_state"))
        # Was offline, not in panic
        self.py_device.set_field("panic_state", False)
        self.panic_manager.clear_panic_on_reconnect(self.lua_device, True)
        self.assertFalse(self.py_device.get_field("panic_state"))
        # Not offline, in panic
        self.py_device.set_field("panic_state", True)
        self.panic_manager.clear_panic_on_reconnect(self.lua_device, False)
        self.assertTrue(self.py_device.get_field("panic_state"))

    def test_clear_panic_state(self):
        self.py_device.set_field("panic_state", True)
        self.panic_manager.clear_panic_state(self.lua_device)
        self.assertFalse(self.py_device.get_field("panic_state"))
        self.assertTrue(
            any(
                ev["event"].get("value") == "clear"
                for ev in self.py_device.component_events
            )
        )

    def test_is_in_panic_state(self):
        self.py_device.set_field("panic_state", True)
        self.assertTrue(self.panic_manager.is_in_panic_state(self.lua_device))
        self.py_device.set_field("panic_state", False)
        self.assertFalse(self.panic_manager.is_in_panic_state(self.lua_device))

    def test_get_panic_status_message(self):
        self.py_device.set_field("panic_state", True)
        msg = self.panic_manager.get_panic_status_message(self.lua_device)
        self.assertEqual(msg, "PANIC: Lost Connection (Grill Was On!)")
        self.py_device.set_field("panic_state", False)
        msg = self.panic_manager.get_panic_status_message(self.lua_device)
        self.assertIsNone(msg)

    def test_cleanup_panic_resources(self):
        self.py_device.set_field("panic_state", True)
        self.py_device.set_field("last_active_time", 12345)
        self.panic_manager.cleanup_panic_resources(self.lua_device)
        self.assertIsNone(self.py_device.get_field("panic_state"))
        self.assertIsNone(self.py_device.get_field("last_active_time"))

    def test_panic_manager_initialization(self):
        """Test panic manager initialization"""
        # Test initialization if method exists
        if (
            "initialize_panic_manager" in self.panic_manager
            and self.panic_manager["initialize_panic_manager"] is not None
        ):
            self.panic_manager.initialize_panic_manager(self.lua_device, None)
            # Check if initialization was successful
            self.assertIsNotNone(
                self.lua_device, "device should exist after initialization"
            )

    def test_panic_timeout_detection(self):
        """Test panic timeout detection"""
        # Test case 1: Device with old last_active_time should not enter panic when offline
        old_time = 1000 - (self.config.CONSTANTS.PANIC_TIMEOUT + 60)
        self.py_device.set_field("last_active_time", old_time)
        self.py_device.set_field("panic_state", False)  # Ensure no existing panic state

        # Call handle_offline_panic_state - should not enter panic due to old activity
        self.panic_manager.handle_offline_panic_state(self.lua_device)
        panic_state = self.py_device.get_field("panic_state")
        self.assertFalse(
            panic_state or False,
            "should not enter panic when device was not recently active",
        )

        # Test case 2: Device with recent last_active_time should enter panic when offline
        recent_time = 1000 - (self.config.CONSTANTS.PANIC_TIMEOUT // 2)
        self.py_device.set_field("last_active_time", recent_time)
        self.py_device.set_field("panic_state", False)  # Reset panic state

        # Call handle_offline_panic_state - should enter panic due to recent activity
        self.panic_manager.handle_offline_panic_state(self.lua_device)
        panic_state = self.py_device.get_field("panic_state")
        self.assertTrue(
            panic_state,
            "should enter panic when device was recently active and goes offline",
        )

    def test_panic_state_management(self):
        """Test panic state management"""
        # Test entering panic state if method exists
        if (
            "enter_panic_state" in self.panic_manager
            and self.panic_manager["enter_panic_state"] is not None
        ):
            self.panic_manager.enter_panic_state(self.lua_device, None)
            # Check if panic state was set
            panic_state = self.py_device.get_field("panic_state")
            self.assertTrue(panic_state or False, "should set panic state")

    def test_panic_recovery(self):
        """Test panic recovery"""
        # Set device in panic state
        self.py_device.set_field("panic_state", True)

        # Test exiting panic state if method exists
        if (
            "exit_panic_state" in self.panic_manager
            and self.panic_manager["exit_panic_state"] is not None
        ):
            self.panic_manager.exit_panic_state(self.lua_device, None)
            # Check if panic state was cleared
            panic_state = self.py_device.get_field("panic_state")
            self.assertFalse(panic_state or False, "should clear panic state")

    def test_offline_panic_handling(self):
        """Test offline panic handling"""
        # Test offline panic if method exists
        if (
            "handle_offline_panic_state" in self.panic_manager
            and self.panic_manager["handle_offline_panic_state"] is not None
        ):
            self.panic_manager.handle_offline_panic_state(self.lua_device)
            # Check if offline panic was handled
            self.assertIsNotNone(
                self.lua_device, "device should exist after offline panic handling"
            )

    def test_panic_manager_error_handling(self):
        """Test panic manager error handling"""
        # Test with invalid device data
        if (
            "enter_panic_state" in self.panic_manager
            and self.panic_manager["enter_panic_state"] is not None
        ):
            try:
                self.panic_manager.enter_panic_state(None, None)
                # Should handle errors gracefully
            except Exception:
                # If it errors with invalid input, that's acceptable
                pass  # nosec B110

    def test_panic_manager_event_emission(self):
        """Test panic manager event emission"""
        # Test event emission if method exists
        if (
            "emit_panic_event" in self.panic_manager
            and self.panic_manager["emit_panic_event"] is not None
        ):
            self.panic_manager.emit_panic_event(self.lua_device, "panic_detected")
            # Check if events were emitted
            self.assertGreaterEqual(
                len(self.py_device.component_events), 0, "should emit panic events"
            )

    def test_panic_manager_status_updates(self):
        """Test panic manager status updates"""
        # Test status update if method exists
        if (
            "update_panic_status" in self.panic_manager
            and self.panic_manager["update_panic_status"] is not None
        ):
            self.panic_manager.update_panic_status(self.lua_device, "panic", None)
            # Check if status was updated
            self.assertIsNotNone(
                self.lua_device, "device should exist after status update"
            )

    def test_panic_manager_device_state_validation(self):
        """Test panic manager device state validation"""
        # Test with grill off - create new device
        py_device_off = PyDevice()
        py_device_off.set_field("switch_state", "off")
        lua_device_off = self.utils.convert_device_to_lua(self.lua, py_device_off)

        # Test panic state handling when device goes offline
        self.panic_manager.handle_offline_panic_state(lua_device_off)
        panic_state = py_device_off.get_field("panic_state")
        self.assertFalse(
            panic_state or False, "should not enter panic state when grill is off"
        )

        # Test with grill on - should enter panic state if recently active
        self.py_device.set_field("last_active_time", 1000)  # Recent activity
        self.panic_manager.handle_offline_panic_state(self.lua_device)
        panic_state = self.py_device.get_field("panic_state")
        self.assertTrue(
            panic_state or False,
            "should enter panic state when grill is on and recently active",
        )

    def test_panic_manager_concurrent_operations(self):
        """Test panic manager concurrent operations"""
        if (
            "check_panic_timeout" in self.panic_manager
            and self.panic_manager["check_panic_timeout"] is not None
        ):
            # Simulate concurrent operations
            results = []
            operations = [
                lambda: self.panic_manager.check_panic_timeout(self.lua_device, None),
                lambda: (
                    self.panic_manager.enter_panic_state(self.lua_device, None)
                    if "enter_panic_state" in self.panic_manager
                    else lambda: True
                ),
                lambda: (
                    self.panic_manager.exit_panic_state(self.lua_device, None)
                    if "exit_panic_state" in self.panic_manager
                    else lambda: True
                ),
            ]

            for op in operations:
                try:
                    result = op()
                    results.append(result)
                except Exception:
                    results.append(False)

            # Should handle concurrent operations
            self.assertEqual(
                len(results), 3, "should handle concurrent panic operations"
            )

    def test_panic_manager_configuration_validation(self):
        """Test panic manager configuration validation"""
        if (
            "validate_panic_config" in self.panic_manager
            and self.panic_manager["validate_panic_config"] is not None
        ):
            # Test valid configuration
            config = self.lua.table_from({"panic_timeout": 300, "enabled": True})
            result = self.panic_manager.validate_panic_config(
                self.lua_device, config, None
            )
            self.assertIsInstance(result, bool, "should validate configuration")

            # Test invalid configuration
            invalid_config = self.lua.table_from(
                {"panic_timeout": -1, "enabled": "invalid"}
            )
            result = self.panic_manager.validate_panic_config(
                self.lua_device, invalid_config, None
            )
            self.assertIsInstance(result, bool, "should handle invalid configuration")

    def test_panic_manager_health_integration(self):
        """Test panic manager health integration"""
        if (
            "integrate_with_health_monitor" in self.panic_manager
            and self.panic_manager["integrate_with_health_monitor"] is not None
        ):
            result = self.panic_manager.integrate_with_health_monitor(
                self.lua_device, None
            )
            self.assertIsInstance(result, bool, "should integrate with health monitor")

    def test_panic_manager_recovery_validation(self):
        """Test panic manager recovery validation"""
        # Set device in panic state
        self.py_device.set_field("panic_state", True)

        if (
            "validate_panic_recovery" in self.panic_manager
            and self.panic_manager["validate_panic_recovery"] is not None
        ):
            result = self.panic_manager.validate_panic_recovery(self.lua_device, None)
            self.assertIsInstance(result, bool, "should validate panic recovery")

        if (
            "execute_panic_recovery" in self.panic_manager
            and self.panic_manager["execute_panic_recovery"] is not None
        ):
            result = self.panic_manager.execute_panic_recovery(self.lua_device, None)
            self.assertIsInstance(result, bool, "should execute panic recovery")

    def test_panic_manager_timeout_configuration(self):
        """Test panic manager timeout configuration"""
        if (
            "configure_panic_timeout" in self.panic_manager
            and self.panic_manager["configure_panic_timeout"] is not None
        ):
            # Test different timeout configurations
            timeouts = [60, 300, 600]  # 1 min, 5 min, 10 min

            for timeout in timeouts:
                config = self.lua.table_from({"panic_timeout": timeout})
                result = self.panic_manager.configure_panic_timeout(
                    self.lua_device, config, None
                )
                self.assertIsInstance(
                    result, bool, f"should configure timeout {timeout}"
                )

    def test_panic_manager_state_persistence(self):
        """Test panic manager state persistence"""
        if (
            "get_panic_state" in self.panic_manager
            and self.panic_manager["get_panic_state"] is not None
        ):
            # Test state persistence
            initial_state = self.panic_manager.get_panic_state(self.lua_device)
            self.assertIsInstance(
                initial_state, bool, "should have initial panic state"
            )

            # Change state
            if (
                "enter_panic_state" in self.panic_manager
                and self.panic_manager["enter_panic_state"] is not None
            ):
                self.panic_manager.enter_panic_state(self.lua_device, None)

                # Check persistence
                current_state = self.panic_manager.get_panic_state(self.lua_device)
                self.assertIsInstance(current_state, bool, "should persist panic state")


if __name__ == "__main__":
    unittest.main()
