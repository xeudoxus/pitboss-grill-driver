from base_test_classes import LuaTestBase


class TestDiscovery(LuaTestBase):
    """Test discovery module using standard test infrastructure."""

    @classmethod
    def _load_modules(cls):
        # Load discovery module - it returns a function
        result = cls.lua.eval('require("discovery")')
        if isinstance(result, tuple):
            cls.discovery = result[0]  # Take the first element if it's a tuple
        else:
            cls.discovery = result
        cls.config = cls.lua.globals().config

    def test_module_loaded(self):
        self.assertIsNotNone(
            self.discovery, "discovery module not loaded or not returned as a table"
        )
        self.assertTrue(
            callable(self.discovery), "discovery should be callable (a function)"
        )

    def test_discovery_handler_basic(self):
        """Test basic discovery handler functionality."""
        # Mock driver with required fields and methods
        self.lua.execute(
            """
        mock_driver = {
            environment_info = { hub_ipv4 = "192.168.1.50" },
            try_create_device = function(device_info)
                return { id = "test-device-id", device_network_id = device_info.device_network_id }
            end,
            thread = { call_with_delay = function(delay, callback) if type(callback)=="function" then callback() end end },
            datastore = {}
        }
        should_continue = function() return true end
        opts = {}
        """
        )

        mock_driver = self.lua.eval("mock_driver")
        should_continue = self.lua.eval("should_continue")
        opts = self.lua.eval("opts")

        # Should not raise an error
        self.discovery(mock_driver, opts, should_continue)

    def test_discovery_handler_nil_opts(self):
        """Test discovery handler with nil options."""
        self.lua.execute(
            """
        mock_driver = {
            environment_info = { hub_ipv4 = "192.168.1.50" },
            try_create_device = function(device_info)
                return { id = "test-device-id", device_network_id = device_info.device_network_id }
            end,
            thread = { call_with_delay = function(delay, callback) if type(callback)=="function" then callback() end end },
            datastore = {}
        }
        should_continue = function() return true end
        """
        )

        mock_driver = self.lua.eval("mock_driver")
        should_continue = self.lua.eval("should_continue")

        # Should not raise an error with nil opts
        self.discovery(mock_driver, None, should_continue)

    def test_discovery_handler_should_continue_false(self):
        """Test discovery handler when should_continue returns false."""
        self.lua.execute(
            """
        mock_driver = {
            environment_info = { hub_ipv4 = "192.168.1.50" },
            try_create_device = function(device_info)
                return { id = "test-device-id", device_network_id = device_info.device_network_id }
            end,
            thread = { call_with_delay = function(delay, callback) if type(callback)=="function" then callback() end end },
            datastore = {}
        }
        should_continue_false = function() return false end
        opts = {}
        """
        )

        mock_driver = self.lua.eval("mock_driver")
        should_continue_false = self.lua.eval("should_continue_false")
        opts = self.lua.eval("opts")

        # Should not raise an error when should_continue is false
        self.discovery(mock_driver, opts, should_continue_false)
