"""
Comprehensive test to generate full src/ coverage report.
This test exercises all Lua modules in the src/ directory.
"""

import os
import unittest

from base_test_classes import LuaTestBase


class TestFullSrcCoverage(LuaTestBase):
    """Comprehensive test to exercise all Lua modules for full coverage."""

    def setUp(self):
        """Set up test with coverage tracking."""
        super().setUp()
        self.start_lua_coverage()
        self._setup_framework_modules()

    def tearDown(self):
        """Clean up and export coverage data."""
        coverage_data = self.export_lua_coverage("lua_coverage.json")
        if coverage_data:
            print(f"Coverage exported: {len(coverage_data)} files tracked")
        super().tearDown()

    def _setup_framework_modules(self):
        """Preload SmartThings framework modules."""
        self.lua.execute("""
            -- Preload framework modules
            local caps_ok, caps_mod = pcall(dofile, "tests/mocks/st/capabilities.lua")
            if caps_ok and caps_mod then
                package.loaded["st.capabilities"] = caps_mod
            end

            local driver_ok, driver_mod = pcall(dofile, "tests/mocks/st/driver.lua")
            if driver_ok and driver_mod then
                package.loaded["st.driver"] = driver_mod
            end

            local log_ok, log_mod = pcall(dofile, "tests/mocks/log.lua")
            if log_ok and log_mod then
                package.loaded["log"] = log_mod
            end

            local cosock_ok, cosock_mod = pcall(dofile, "tests/mocks/cosock.lua")
            if cosock_ok and cosock_mod then
                package.loaded["cosock"] = cosock_mod
            end
        """)

    def _create_mock_objects(self):
        """Create mock objects for testing."""
        return self.lua.execute("""
            local mock_device = {
                get_field = function(self, field)
                    if field == "unit" then return "F"
                    elseif field == "deviceId" then return "test-device-123"
                    elseif field == "ipAddress" then return "192.168.1.100"
                    end
                    return nil
                end,
                set_field = function(self, field, value) end,
                get_latest_state = function(self) return {} end,
                emit_event = function(self, event) end,
                emit_component_event = function(self, component, event) end,
                offline = function(self) end,
                online = function(self) end,
                profile = {
                    components = {
                        main = {
                            capabilities = {
                                thermostatHeatingSetpoint = true,
                                switch = true,
                                temperatureMeasurement = true
                            }
                        }
                    }
                },
                thread = {
                    call_with_delay = function(self, delay, func) end
                },
                preferences = {
                    ipAddress = "192.168.1.100"
                }
            }
            
            local mock_status = {
                is_fahrenheit = true,
                fan_state = "low",
                grill_temp = 225,
                probe1_temp = 150,
                probe2_temp = 160,
                probe3_temp = 170
            }
            
            local mock_driver = {
                get_device_info = function(self, device_id) return {} end,
                call_with_delay = function(self, delay, func) end,
                get_devices = function(self) return {} end,
                datastore = {
                    discovery_in_progress = false,
                    discovery_start_time = nil
                }
            }
            
            return mock_device, mock_status, mock_driver
        """)

    def test_config_module(self):
        """Test config module functions."""
        self.lua.execute("""
            local config = require("config")
            
            -- Exercise functions
            config.get_temperature_range("F")
            config.get_temperature_range("C")
            config.get_sensor_range("F")
            config.get_sensor_range("C")
            config.get_approved_setpoints("F")
            config.get_approved_setpoints("C")
            config.get_temp_reset_threshold("F")
            config.get_temp_reset_threshold("C")
            
            -- Access constants
            local _ = config.CONSTANTS.DEFAULT_UNIT
            local _ = config.CONSTANTS.MIN_TEMP_F
            local _ = config.CONSTANTS.MAX_TEMP_F
        """)

    def test_capability_handlers_module(self):
        """Test capability handlers module."""
        result = self.lua.execute("""
            local ok = pcall(require, "capability_handlers")
            return ok
        """)
        self.assertTrue(result)

    def test_temperature_service_module(self):
        """Test temperature service module."""
        self.create_lua_device()
        self.lua.execute("""
            local temp_service = require("temperature_service")
            
            pcall(temp_service.process_temperature_data, {})
            pcall(temp_service.convert_temperature, 225, "F", "C")
            pcall(temp_service.convert_temperature, 107, "C", "F")
        """)

    def test_command_service_module(self):
        """Test command service module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("command_service")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        pcall(v, mock_device)
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_device_status_service_module(self):
        """Test device status service module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("device_status_service")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        if k == "update_device_status" or k == "calculate_power_consumption" then
                            pcall(v, mock_device, mock_status)
                        else
                            pcall(v, mock_device)
                        end
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_refresh_service_module(self):
        """Test refresh service module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("refresh_service")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        pcall(v, mock_device)
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_health_monitor_module(self):
        """Test health monitor module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("health_monitor")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        pcall(v, mock_device)
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_device_manager_module(self):
        """Test device manager module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("device_manager")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        pcall(v, mock_device)
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_probe_display_module(self):
        """Test probe display module."""
        self.lua.execute("""
            local mod = require("probe_display")
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        if k == "generate_four_probe_text" then
                            pcall(v, 225, 150, 160, 170, true)
                        else
                            pcall(v)
                        end
                    end
                end
            end
        """)

    def test_network_utils_module(self):
        """Test network utils module."""
        self.lua.execute("""
            local mod = require("network_utils")
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        if k == "get_subnet_prefix" then
                            pcall(v, "192.168.1.100")
                        elseif k == "is_firmware_valid" then
                            pcall(v, "1.2.3")
                        else
                            pcall(v)
                        end
                    end
                end
            end
        """)

    def test_pitboss_api_module(self):
        """Test pitboss API module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("pitboss_api")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        pcall(v, mock_device)
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_virtual_device_manager_module(self):
        """Test virtual device manager module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("virtual_device_manager")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        if k == "initialize_virtual_devices" then
                            pcall(v, mock_driver, mock_device, true)
                        elseif k == "manage_virtual_devices" then
                            pcall(v, mock_driver, mock_device)
                        elseif k == "get_virtual_devices_for_parent" then
                            pcall(v, mock_driver, "test-device-123")
                        else
                            pcall(v, mock_device)
                        end
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_temperature_calibration_module(self):
        """Test temperature calibration module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("temperature_calibration")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        pcall(v, mock_device)
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_panic_manager_module(self):
        """Test panic manager module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("panic_manager")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        pcall(v, mock_device)
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_discovery_module(self):
        """Test discovery module."""
        mock_device, mock_status, mock_driver = self._create_mock_objects()
        self.lua.execute("""
            local mod = require("discovery")
            local mock_device, mock_status, mock_driver = ...
            
            if type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" then
                        if k:find("discover") or k:find("rediscover") then
                            pcall(v, mock_driver)
                        else
                            pcall(v, mock_device)
                        end
                    end
                end
            end
        """, mock_device, mock_status, mock_driver)

    def test_custom_capabilities_module(self):
        """Test custom capabilities module."""
        result = self.lua.execute("""
            local ok, mod = pcall(require, "custom_capabilities")
            return ok
        """)
        self.assertTrue(result)

    def test_init_module_expected_failure(self):
        """Test that init module fails as expected (requires SmartThings runtime)."""
        result = self.lua.execute("""
            local ok, mod = pcall(require, "init")
            return ok
        """)
        # We expect this to fail since init.lua requires SmartThings runtime
        self.assertFalse(result)


if __name__ == "__main__":
    os.environ["LUA_COVERAGE"] = "1"
    unittest.main(verbosity=2)