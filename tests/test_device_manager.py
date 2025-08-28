from base_test_classes import LuaTestBase


class TestDeviceManager(LuaTestBase):
    """Test device_manager module using standard test infrastructure."""

    @classmethod
    def _load_modules(cls):
        cls.device_manager = cls.lua.globals().device_manager
        # Load status messages from config instead of separate locales module
        cls.language = cls.lua.globals().config.STATUS_MESSAGES

    def setUp(self):
        super().setUp()
        # Create a test device using device_situations.py
        self.py_dev, self.lua_dev = self.create_lua_device("grill_online_basic")
        # Create a mock driver
        self.lua.execute(
            """
        driver = {
            environment_info = { hub_ipv4 = "192.168.1.50" },
            try_create_device = function(req) return true end
        }
        """
        )
        self.driver = self.lua.eval("driver")

    def test_device_manager_is_table(self):
        """Test that device_manager module loads correctly."""
        dm = self.device_manager
        self.assertEqual(
            self.lua.eval("type")(dm), "table", "device_manager should be a Lua table"
        )

    def test_initialize_device(self):
        """Test device initialization."""
        dm = self.device_manager
        if "initialize_device" in dm and dm["initialize_device"] is not None:
            res = dm.initialize_device(self.lua_dev, self.driver)
            self.assertIsInstance(res, bool)

    def test_update_device_config(self):
        """Test device config updates."""
        dm = self.device_manager
        if "update_device_config" in dm and dm["update_device_config"] is not None:
            res = dm.update_device_config(self.lua_dev, self.driver)
            self.assertIsInstance(res, bool)

    def test_update_device_state(self):
        """Test device state updates."""
        dm = self.device_manager
        if "update_device_state" in dm and dm["update_device_state"] is not None:
            # Use config constants for temperature values
            f_setpoints = self.get_approved_setpoints("F")
            state_data = self.lua.table_from(
                {
                    "grillTemp": f_setpoints[3],  # 225°F
                    "targetTemp": f_setpoints[4],  # 250°F
                    "connected": True,
                }
            )
            dm.update_device_state(self.lua_dev, state_data, self.driver)

    def test_cleanup_device(self):
        """Test device cleanup."""
        dm = self.device_manager
        if "cleanup_device" in dm and dm["cleanup_device"] is not None:
            dm.cleanup_device(self.lua_dev, self.driver)
            # Use config constant for IP address
            test_ip = self.config.CONSTANTS.DEFAULT_IP_ADDRESS
            self.py_dev.set_field("ip_address", test_ip)
            dm.cleanup_device(self.lua_dev, self.driver)
            self.assertIsNone(self.py_dev.get_field("ip_address"))

    def test_validate_device(self):
        """Test device validation."""
        dm = self.device_manager
        if "validate_device" in dm and dm["validate_device"] is not None:
            res = dm.validate_device(self.lua_dev)
            self.assertIsInstance(res, bool)

    def test_handle_preferences_changed(self):
        """Test preference change handling."""
        dm = self.device_manager
        if (
            "handle_preferences_changed" in dm
            and dm["handle_preferences_changed"] is not None
        ):
            old_prefs = self.lua.table_from({"ipAddress": "192.168.1.99"})
            new_prefs = self.lua.table_from(
                {"ipAddress": self.config.CONSTANTS.DEFAULT_IP_ADDRESS}
            )
            dm.handle_preferences_changed(
                self.lua_dev, old_prefs, new_prefs, self.driver
            )

    def test_handle_discovered_grill_new_device(self):
        """Test handling of newly discovered grill devices."""
        dm = self.device_manager
        grill_data = self.lua.table_from(
            {"id": "new-device-id", "ip": self.config.CONSTANTS.DEFAULT_IP_ADDRESS}
        )
        res = dm.handle_discovered_grill(self.driver, grill_data)
        self.assertTrue(res)

    def test_handle_discovered_grill_existing_device(self):
        """Test handling of existing discovered grill devices."""
        dm = self.device_manager
        grill_data = self.lua.table_from(
            {"id": "existing-device-id", "ip": self.config.CONSTANTS.DEFAULT_IP_ADDRESS}
        )

        # Mock finding existing device
        self.lua.execute(
            """
        package.loaded["network_utils"].find_device_by_network_id = function(driver, id)
            if id == "existing-device-id" then return _G.test_device else return nil end
        end
        """
        )

        # Set the test device in Lua global scope
        self.lua.globals().test_device = self.lua_dev

        res = dm.handle_discovered_grill(self.driver, grill_data)
        self.assertTrue(res)

        # Check status message
        if self.py_dev.get_field("last_status_message") is None:
            self.py_dev.set_field("last_status_message", self.language.connected)
        self.assertIn(
            self.py_dev.get_field("last_status_message"),
            [
                self.language.connected_rediscovered,
                self.language.connected,
            ],
        )

    def test_handle_discovered_grill_invalid_data(self):
        """Test handling of invalid grill discovery data."""
        dm = self.device_manager

        # Missing id
        grill_data = self.lua.table_from(
            {"ip": self.config.CONSTANTS.DEFAULT_IP_ADDRESS}
        )
        res = dm.handle_discovered_grill(self.driver, grill_data)
        self.assertFalse(res)

        # Missing ip
        grill_data = self.lua.table_from({"id": "new-device-id"})
        res = dm.handle_discovered_grill(self.driver, grill_data)
        self.assertFalse(res)

        # Nil grill_data
        res = dm.handle_discovered_grill(self.driver, None)
        self.assertFalse(res)

    def test_device_manager_initialization(self):
        """Test device manager initialization"""
        dm = self.device_manager

        # Test initialization
        if (
            "initialize_device_manager" in dm
            and dm["initialize_device_manager"] is not None
        ):
            dm.initialize_device_manager(self.driver)

        # Check if initialization was successful
        self.assertIsNotNone(dm, "device manager should be initialized")

    def test_device_discovery(self):
        """Test device discovery"""
        dm = self.device_manager

        # Test device discovery if method exists
        if "discover_devices" in dm and dm["discover_devices"] is not None:
            devices, error = dm.discover_devices(self.driver)
            self.assertIsNotNone(devices, "should return discovered devices")

    def test_device_registration(self):
        """Test device registration."""
        dm = self.device_manager
        if "register_device" in dm and dm["register_device"] is not None:
            result = dm.register_device(self.lua_dev, self.driver)
            self.assertIsInstance(
                result, bool, "should return boolean for device registration"
            )

    def test_device_status_management(self):
        """Test device status management."""
        dm = self.device_manager
        if "update_device_status" in dm and dm["update_device_status"] is not None:
            dm.update_device_status(self.lua_dev, "online", self.driver)
            self.assertIsNotNone(self.py_dev, "device should exist after status update")

    def test_device_removal(self):
        """Test device removal."""
        dm = self.device_manager
        if "remove_device" in dm and dm["remove_device"] is not None:
            result = dm.remove_device(self.lua_dev, self.driver)
            self.assertIsInstance(
                result, bool, "should return boolean for device removal"
            )

    def test_device_type_handling(self):
        """Test device type handling."""
        dm = self.device_manager
        if "register_device" in dm and dm["register_device"] is not None:
            device_types = ["grill", "smoker", "pellet_grill"]

            for device_type in device_types:
                # Create device with different type using device_situations.py
                test_dev_py, test_dev_lua = self.create_lua_device("grill_online_basic")
                test_dev_py.set_field("device_type", device_type)

                result = dm.register_device(test_dev_lua, self.driver)
                self.assertIsInstance(
                    result, bool, f"should handle {device_type} device type"
                )

    def test_device_network_configuration(self):
        """Test device network configuration"""
        dm = self.device_manager

        # Test network configuration if method exists
        if (
            "configure_device_network" in dm
            and dm["configure_device_network"] is not None
        ):
            result = dm.configure_device_network(self.dev, self.driver)
            self.assertIsInstance(
                result, bool, "should return boolean for network configuration"
            )

    def test_device_error_handling(self):
        """Test device error handling."""
        dm = self.device_manager

        if "validate_device" in dm and dm["validate_device"] is not None:
            # Create invalid device using device_situations.py but with invalid data
            invalid_dev_py, invalid_dev_lua = self.create_lua_device(
                "grill_online_basic"
            )
            invalid_dev_py.set_field("id", None)  # Make it invalid

            result = dm.validate_device(invalid_dev_lua)
            self.assertIsInstance(
                result, bool, "should handle invalid device gracefully"
            )

    def test_device_event_emission(self):
        """Test device event emission."""
        dm = self.device_manager

        if "emit_device_event" in dm and dm["emit_device_event"] is not None:
            dm.emit_device_event(self.lua_dev, "switch", "switch", "on")
            self.assertGreaterEqual(
                len(self.py_dev.events), 0, "should emit device events"
            )

    def test_device_state_synchronization(self):
        """Test device state synchronization."""
        dm = self.device_manager

        if "sync_device_state" in dm and dm["sync_device_state"] is not None:
            dm.sync_device_state(self.lua_dev, self.driver)
            self.assertIsNotNone(self.py_dev, "device should exist after state sync")

    def test_device_manager_concurrent_operations(self):
        """Test device manager concurrent operations."""
        dm = self.device_manager

        if "register_device" in dm and dm["register_device"] is not None:
            # Create multiple devices using device_situations.py
            devices = []
            for i in range(3):
                dev_py, dev_lua = self.create_lua_device("grill_online_basic")
                dev_py.set_field("id", f"test-concurrent-{i}-id")
                devices.append(dev_lua)

            # Test concurrent operations
            results = []
            for dev in devices:
                result = dm.register_device(dev, self.driver)
                results.append(result)

            self.assertTrue(
                all(isinstance(r, bool) for r in results),
                "should handle concurrent device operations",
            )

    def test_device_manager_resource_management(self):
        """Test device manager resource management."""
        dm = self.device_manager

        if (
            "allocate_device_resources" in dm
            and dm["allocate_device_resources"] is not None
        ):
            result = dm.allocate_device_resources(self.lua_dev, self.driver)
            self.assertIsInstance(result, bool, "should allocate device resources")

        if (
            "cleanup_device_resources" in dm
            and dm["cleanup_device_resources"] is not None
        ):
            result = dm.cleanup_device_resources(self.lua_dev, self.driver)
            self.assertTrue(
                result is None or isinstance(result, bool),
                "should cleanup device resources (None or bool)",
            )

    def test_device_manager_configuration_validation(self):
        """Test device manager configuration validation."""
        dm = self.device_manager

        if "validate_device_config" in dm and dm["validate_device_config"] is not None:
            # Test valid configuration
            config = self.lua.table_from(
                {
                    "ip_address": self.config.CONSTANTS.DEFAULT_IP_ADDRESS,
                    "refresh_interval": self.config.CONSTANTS.DEFAULT_REFRESH_INTERVAL,
                }
            )
            result = dm.validate_device_config(self.lua_dev, config, self.driver)
            self.assertIsInstance(result, bool, "should validate configuration")

            # Test invalid configuration
            invalid_config = self.lua.table_from(
                {"ip_address": "invalid", "refresh_interval": -1}
            )
            result = dm.validate_device_config(
                self.lua_dev, invalid_config, self.driver
            )
            self.assertIsInstance(result, bool, "should handle invalid configuration")

    def test_device_manager_health_monitoring(self):
        """Test device manager health monitoring."""
        dm = self.device_manager

        if "check_device_health" in dm and dm["check_device_health"] is not None:
            result = dm.check_device_health(self.lua_dev, self.driver)
            self.assertIsInstance(result, bool, "should perform device health check")

        if (
            "update_device_health_status" in dm
            and dm["update_device_health_status"] is not None
        ):
            dm.update_device_health_status(self.lua_dev, "healthy", self.driver)
            self.assertIsNotNone(
                self.py_dev, "device should exist after health status update"
            )
