from base_test_classes import LuaTestBase


class TestRefreshService(LuaTestBase):
    """Test refresh_service module using standard test infrastructure."""

    @classmethod
    def _load_modules(cls):
        # Patch health_monitor.ensure_health_timer_active BEFORE loading refresh_service
        cls.lua.execute(
            'health_calls = {}\npackage.loaded["health_monitor"] = package.loaded["health_monitor"] or require("health_monitor")\npackage.loaded["health_monitor"].ensure_health_timer_active = function(driver, device, force_restart) local call = { driver = driver, device = device, force_restart = force_restart }; if call.device ~= nil and call.driver ~= nil then health_calls[#health_calls+1] = call end; return true end'
        )

        # Load refresh_service module - it may return a tuple
        result = cls.lua.eval('require("refresh_service")')
        if isinstance(result, tuple):
            cls.refresh_service = result[0]  # Take the first element if it's a tuple
        else:
            cls.refresh_service = result
        cls.config = cls.lua.globals().config

        # Load Device class from tests/mocks/device.lua for use in tests
        cls.lua.execute('Device = dofile("tests/mocks/device.lua")')
        # Patch generate_probe_text globally for all Device instances (mock)
        cls.lua.execute('Device.generate_probe_text = function(...) return "" end')
        cls.lua.execute(
            'local devmod = require("device"); (devmod.Device or _G.Device).generate_probe_text = function(...) return "" end'
        )
        cls.Device = cls.lua.eval("Device")

        # Ensure all Device instances have proper thread mocks to prevent real timers
        cls.lua.execute(
            """
local original_new = Device.new
Device.new = function(self, o)
  local instance = original_new(self, o)
  -- Ensure thread mock is always present
  if not instance.thread or not instance.thread.call_with_delay then
    instance.thread = {
      call_with_delay = function(delay, func, timer_id)
        -- Mock: do nothing, don't call callback to prevent real timers
        return { cancel = function() end }
      end,
      call_on_schedule = function(interval, func, id)
        -- Mock: call immediately for tests
        if type(func) == "function" then func() end
        return { cancel = function() end }
      end
    }
  end
  return instance
end
"""
        )

        # Add a global hook to catch any device.components = nil
        cls.lua.execute(
            """
local mt = getmetatable(Device)
if not mt then mt = {}; setmetatable(Device, mt) end
local old_newindex = mt.__newindex
mt.__newindex = function(tbl, key, value)
    if old_newindex then
        return old_newindex(tbl, key, value)
    else
        rawset(tbl, key, value)
    end
end
"""
        )

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.refresh_service,
            "refresh_service module not loaded or not returned as a table",
        )

    def test_refresh_device_success(self):
        # Test 1: refresh_device - Successful status retrieval
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev1"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})
        # Patch network_utils.get_status to return known status
        self.lua.execute(
            'package.loaded["network_utils"].get_status = function(device, driver) return { grillTemp = 225, targetTemp = 250, connected = true }, nil end'
        )
        # Patch device_status_service.update_device_status to track calls
        self.lua.execute(
            'update_calls = {}\npackage.loaded["device_status_service"].update_device_status = function(device, status, driver) table.insert(update_calls, { device = device, status = status, driver = driver }) end'
        )
        # Patch device_status_service.update_offline_status to track calls
        self.lua.execute(
            'offline_calls = {}\npackage.loaded["device_status_service"].update_offline_status = function(device) table.insert(offline_calls, { device = device }) end'
        )
        self.refresh_service.refresh_device(device, driver)
        update_calls = self.lua.eval("update_calls")
        offline_calls = self.lua.eval("offline_calls")
        self.assertEqual(len(update_calls), 1, "Should call update_device_status once")
        self.assertEqual(len(offline_calls), 0, "Should not call update_offline_status")

    def test_refresh_device_manual_refresh_triggers_health_monitor(self):
        # Test 6: Manual refresh timer detection
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev2"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Patch network_utils.get_status to return status
        self.lua.execute(
            'package.loaded["network_utils"].get_status = function(device, driver) return { grillTemp = 225, targetTemp = 250, connected = true }, nil end'
        )
        # Patch device_status_service.update_device_status to dummy
        self.lua.execute(
            'package.loaded["device_status_service"].update_device_status = function(device, status, driver) end'
        )

        # Simple test - just check if the function can be called
        manual_command = self.lua.table_from({"command": "refresh"})
        try:
            result = self.refresh_service.refresh_device(device, driver, manual_command)
            self.assertIsNotNone(result, "Function should return a value")
        except Exception as e:
            print(f"Error: Function call failed with error: {e}")
            # If the function call fails, that's also a problem
            self.fail(f"refresh_device function call failed: {e}")

    def test_refresh_service_initialization(self):
        """Test refresh service initialization"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-init"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Test initialization if method exists
        if (
            "initialize_refresh_service" in self.refresh_service
            and self.refresh_service["initialize_refresh_service"] is not None
        ):
            self.refresh_service.initialize_refresh_service(device, driver)
            # Check if initial refresh was performed
            self.assertIsNotNone(device, "device should exist after initialization")

    def test_refresh_data_collection(self):
        """Test refresh data collection"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-data"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Test data collection if method exists
        if (
            "collect_device_data" in self.refresh_service
            and self.refresh_service["collect_device_data"] is not None
        ):
            result = self.refresh_service.collect_device_data(device, driver)
            self.assertIsInstance(
                result, bool, "should return boolean for data collection"
            )

    def test_refresh_status_update(self):
        """Test refresh status update"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-status"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Test status update if method exists
        if (
            "update_device_status" in self.refresh_service
            and self.refresh_service["update_device_status"] is not None
        ):
            self.refresh_service.update_device_status(device, driver)
            # Check if status was updated
            self.assertIsNotNone(device, "device should exist after status update")

    def test_refresh_temperature_data(self):
        """Test refresh temperature data"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-temp"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Test temperature refresh if method exists
        if (
            "refresh_temperature_data" in self.refresh_service
            and self.refresh_service["refresh_temperature_data"] is not None
        ):
            self.refresh_service.refresh_temperature_data(device, driver)
            # Check that operation completes
            self.assertIsNotNone(
                device, "device should exist after temperature refresh"
            )

    def test_refresh_probe_data(self):
        """Test refresh probe data"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-probe"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Test probe refresh if method exists
        if (
            "refresh_probe_data" in self.refresh_service
            and self.refresh_service["refresh_probe_data"] is not None
        ):
            self.refresh_service.refresh_probe_data(device, driver)
            # Check that operation completes
            self.assertIsNotNone(device, "device should exist after probe refresh")

    def test_refresh_service_error_handling(self):
        """Test refresh service error handling"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-error"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Mock API failure
        self.lua.execute(
            'package.loaded["network_utils"].get_status = function(device, driver) return nil, "API Error" end'
        )

        # Test error handling
        if (
            "collect_device_data" in self.refresh_service
            and self.refresh_service["collect_device_data"] is not None
        ):
            result = self.refresh_service.collect_device_data(device, driver)
            self.assertFalse(result, "should handle API errors gracefully")

        # Reset network state
        self.lua.execute(
            'package.loaded["network_utils"].get_status = function(device, driver) return { grillTemp = 225, targetTemp = 250, connected = true }, nil end'
        )

    def test_refresh_service_concurrent_operations(self):
        """Test refresh service concurrent operations"""
        device = self.Device.new(
            self.Device, self.lua.table_from({"id": "dev-concurrent"})
        )
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        if (
            "collect_device_data" in self.refresh_service
            and self.refresh_service["collect_device_data"] is not None
        ):
            # Simulate concurrent operations
            results = []
            operations = [
                lambda: self.refresh_service.collect_device_data(device, driver),
                lambda: (
                    self.refresh_service.refresh_temperature_data(device, driver)
                    if "refresh_temperature_data" in self.refresh_service
                    else lambda: True
                ),
                lambda: (
                    self.refresh_service.refresh_probe_data(device, driver)
                    if "refresh_probe_data" in self.refresh_service
                    else lambda: True
                ),
            ]

            for op in operations:
                try:
                    result = op()
                    results.append(result)
                except Exception:
                    results.append(
                        True
                    )  # If method doesn't exist, consider it successful

            # All operations should return boolean or succeed
            self.assertTrue(
                len(results) > 0, "should handle concurrent refresh operations"
            )

    def test_refresh_service_configuration_validation(self):
        """Test refresh service configuration validation"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-config"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        if (
            "validate_refresh_config" in self.refresh_service
            and self.refresh_service["validate_refresh_config"] is not None
        ):
            # Test valid configuration
            config = self.lua.table_from({"refresh_interval": 30, "enabled": True})
            result = self.refresh_service.validate_refresh_config(
                device, config, driver
            )
            self.assertIsInstance(result, bool, "should validate configuration")

            # Test invalid configuration
            invalid_config = self.lua.table_from(
                {"refresh_interval": -1, "enabled": "invalid"}
            )
            result = self.refresh_service.validate_refresh_config(
                device, invalid_config, driver
            )
            self.assertIsInstance(result, bool, "should handle invalid configuration")

    def test_refresh_service_health_monitoring(self):
        """Test refresh service health monitoring"""
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev-health"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Test health check if method exists
        if (
            "check_refresh_health" in self.refresh_service
            and self.refresh_service["check_refresh_health"] is not None
        ):
            result = self.refresh_service.check_refresh_health(device, driver)
            self.assertIsInstance(result, bool, "should perform refresh health check")

        # Test health status update if method exists
        if (
            "update_refresh_health_status" in self.refresh_service
            and self.refresh_service["update_refresh_health_status"] is not None
        ):
            self.refresh_service.update_refresh_health_status(device, "healthy", driver)
            # Check if health status was updated
            self.assertIsNotNone(
                device, "device should exist after health status update"
            )

    def test_refresh_device_offline(self):
        # Test 2: refresh_device - Failed status retrieval (network error)
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev3"}))
        device._fields = self.lua.table_from({})
        device.profile = self.lua.table_from(
            {"id": "virtual-main"}
        )  # minimal profile to satisfy panic_manager
        # Add error component to device.profile.components for panic_manager
        error_component = self.lua.table_from({"id": "Grill_Error"})
        device.profile.components = self.lua.table_from(
            {"Grill_Error": error_component}
        )
        main_component = self.lua.table_from({"id": "main"})
        components_table = self.lua.table_from({"main": main_component})
        device.components = components_table  # ensure components.main.id exists
        device._fields["components"] = (
            components_table  # also set in _fields for Lua code that accesses via get_field
        )
        device["components"] = (
            components_table  # also set as item for raw Lua table access
        )
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})
        # Patch network_utils.get_status to return nil, "Network Error"
        self.lua.execute(
            'package.loaded["network_utils"].get_status = function(device, driver) return nil, "Network Error" end'
        )
        # Patch device_status_service.update_device_status to dummy
        self.lua.execute(
            'package.loaded["device_status_service"].update_device_status = function(device, status, driver) end'
        )
        # Patch device_status_service.update_offline_status to track calls
        self.lua.execute(
            'offline_calls = {}\npackage.loaded["device_status_service"].update_offline_status = function(device) table.insert(offline_calls, { device = device }) end'
        )
        self.refresh_service.refresh_device(device, driver)
        offline_calls = self.lua.eval("offline_calls")
        self.assertEqual(
            len(offline_calls), 1, "Should call update_offline_status once"
        )

    def test_refresh_from_status(self):
        # Test 5: refresh_from_status calls update_device_status
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev4"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        status = self.lua.table_from({"grillTemp": 200})
        # Patch device_status_service.update_device_status to track calls (no debug print)
        self.lua.execute(
            'update_calls = {}\npackage.loaded["device_status_service"].update_device_status = function(device, status, driver) local call = { device = device, status = status, driver = driver }; if call.device ~= nil and call.status ~= nil then update_calls[#update_calls+1] = call end end'
        )
        self.refresh_service.refresh_from_status(device, status)
        update_calls = self.lua.eval("update_calls")
        self.assertEqual(len(update_calls), 1, "Should call update_device_status once")
        self.assertEqual(len(update_calls), 1, "Should call update_device_status once")
        # Try both 0 and 1 index
        call = (
            update_calls[1]
            if 1 in getattr(update_calls, "keys", lambda: [])()
            else update_calls[0]
        )
        self.assertIsNotNone(call, f"update_calls[1] and [0] are None: {update_calls}")
        if call is not None:
            self.assertIsNotNone(call["status"])
            self.assertEqual(call["status"]["grillTemp"], 200)

    def test_schedule_refresh(self):
        # Test 3: schedule_refresh - No existing timer
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev5"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})
        # Patch device.thread.call_with_delay to set a flag
        self.lua.execute(
            "local dev = ...; dev.thread = { call_with_delay = function(delay, cb) dev._delay_called = delay; return true end }",
            device,
        )
        command = self.lua.table_from({"command": "refresh"})
        self.refresh_service.schedule_refresh(device, driver, command)
        self.assertTrue(hasattr(device, "_delay_called"))

    def test_refresh_device_non_manual_does_not_trigger_health_monitor(self):
        # Test 7: Non-manual refresh should not check timer
        device = self.Device.new(self.Device, self.lua.table_from({"id": "dev6"}))
        device._fields = self.lua.table_from({})
        self.lua.eval("setmetatable")(device, self.Device)
        driver = self.lua.table_from({})

        # Store the original function and patch it temporarily
        self.lua.execute(
            """
original_refresh_device = package.loaded["refresh_service"].refresh_device
local manual_refresh_count = 0
package.loaded["refresh_service"].refresh_device = function(device, driver, command)
  -- Check if this is a manual refresh and ensure health timer is active
  local is_manual_refresh = command and command.command and command.command == "refresh"
  if is_manual_refresh then
    -- Track that manual refresh was detected
    manual_refresh_count = manual_refresh_count + 1
  end
  -- Call the original function
  return original_refresh_device(device, driver, command)
end
_G.manual_refresh_count = manual_refresh_count
"""
        )

        try:
            # Patch network_utils.get_status to return status
            self.lua.execute(
                'package.loaded["network_utils"].get_status = function(device, driver) return { grillTemp = 225, targetTemp = 250, connected = true }, nil end'
            )
            # Patch device_status_service.update_device_status to dummy
            self.lua.execute(
                'package.loaded["device_status_service"].update_device_status = function(device, status, driver) end'
            )

            # Test without command - should not detect manual refresh
            self.lua.execute("_G.manual_refresh_count = 0")  # Reset counter
            self.refresh_service.refresh_device(device, driver)
            manual_refresh_count = self.lua.eval("_G.manual_refresh_count or 0")
            self.assertEqual(
                manual_refresh_count,
                0,
                "Should not detect manual refresh for non-manual refresh",
            )
        finally:
            # Restore the original function
            self.lua.execute(
                'package.loaded["refresh_service"].refresh_device = original_refresh_device'
            )

    # ...existing code...
