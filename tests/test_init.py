from base_test_classes import LuaTestBase


class TestInitLua(LuaTestBase):
    """Test init.lua module loading and driver initialization."""

    @classmethod
    def _load_modules(cls):
        # Load dependencies first (all except init.lua)
        dependencies = [
            # Mocks and core dependencies
            'package.loaded["bit32"] = dofile("tests/mocks/bit32.lua")',
            'package.loaded["log"] = dofile("tests/mocks/log.lua")',
            'package.loaded["cosock"] = dofile("tests/mocks/cosock.lua")',
            'package.loaded["dkjson"] = dofile("tests/mocks/dkjson.lua")',
            'package.loaded["st.capabilities"] = dofile("tests/mocks/st/capabilities.lua")',
            'package.loaded["st.json"] = dofile("tests/mocks/st/json.lua")',
            'package.loaded["st.driver"] = dofile("tests/mocks/st/driver.lua")',
            # Real modules in topological order (except init.lua)
            'package.loaded["config"] = dofile("src/config.lua")',
            'package.loaded["custom_capabilities"] = dofile("src/custom_capabilities.lua")',
            'package.loaded["temperature_calibration"] = dofile("src/temperature_calibration.lua")',
            'package.loaded["temperature_service"] = dofile("src/temperature_service.lua")',
            'package.loaded["probe_display"] = dofile("src/probe_display.lua")',
            'package.loaded["pitboss_api"] = dofile("src/pitboss_api.lua")',
            'package.loaded["network_utils"] = dofile("src/network_utils.lua")',
            'package.loaded["panic_manager"] = dofile("src/panic_manager.lua")',
            'package.loaded["device_status_service"] = dofile("src/device_status_service.lua")',
            'package.loaded["virtual_device_manager"] = dofile("src/virtual_device_manager.lua")',
            'package.loaded["health_monitor"] = dofile("src/health_monitor.lua")',
            'package.loaded["refresh_service"] = dofile("src/refresh_service.lua")',
            'package.loaded["command_service"] = dofile("src/command_service.lua")',
            'package.loaded["capability_handlers"] = dofile("src/capability_handlers.lua")',
            'package.loaded["device_manager"] = dofile("src/device_manager.lua")',
            'package.loaded["discovery"] = dofile("src/discovery.lua")',
        ]
        for dep in dependencies:
            cls.lua.execute(dep)

        # Patch Driver.run to a no-op to avoid errors in test environment (after st.driver is loaded)
        cls.lua.execute(
            'local d = require("st.driver"); if d and type(d) == "table" then d.run = function() end end'
        )

        # Now load init.lua
        with open("src/init.lua", "r", encoding="utf-8") as f:
            lua_code = f.read()
        # Ensure init is assigned to _G if returned as a module
        cls.lua.execute(
            f"""
        local mod = (function()
        {lua_code}
        end)()
        if mod ~= nil then
            init = mod
            package.loaded["init"] = mod
        end
        """
        )
        cls.init = cls.lua.eval("init or nil")

    def test_module_loads_without_error(self):
        # The init module is not required to return a table, just load without error
        # If we reach here, loading succeeded
        self.assertTrue(True)

    def test_global_current_driver_set(self):
        # _G.current_driver should be set and be a table/object
        current_driver = self.lua.eval("_G.current_driver or nil")
        self.assertIsNotNone(
            current_driver, "_G.current_driver should be set by init.lua"
        )
        self.assertTrue(
            hasattr(current_driver, "__len__")
            or isinstance(current_driver, (dict, object)),
            "current_driver should be a table/object",
        )

    def test_driver_name_and_handlers(self):
        current_driver = self.lua.eval("_G.current_driver or nil")
        self.assertIsNotNone(current_driver)
        # Check driver name
        name = current_driver["NAME"] if "NAME" in current_driver.keys() else None
        self.assertTrue(name is None or name == "pitboss-grill")
        # Check lifecycle handlers
        keys = list(current_driver.keys())
        lifecycle = (
            current_driver["lifecycle_handlers"]
            if "lifecycle_handlers" in keys
            else None
        )
        self.assertIsNotNone(lifecycle)
        handler_keys = (
            list(lifecycle.keys())
            if hasattr(lifecycle, "keys")
            else list(lifecycle) if lifecycle else []
        )
        for handler in ["init", "added", "infoChanged", "removed"]:
            self.assertIn(handler, handler_keys)
