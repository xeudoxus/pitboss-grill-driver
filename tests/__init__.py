"""
SmartThings Edge Driver Test Suite

This package contains Python tests for the Pit Boss Grill SmartThings Edge driver.
It provides utilities for testing Lua modules from Python using the lupa library.

Key components:
- base_test_classes.py: Base test classes with common setup
- mock_device.py: Mock SmartThings device implementation
- utils_lua_test.py: Utilities for Lua-Python bridging
"""

import os
import sys

tests_dir = os.path.dirname(os.path.abspath(__file__))
if tests_dir not in sys.path:
    sys.path.insert(0, tests_dir)

# Try to import modules, but don't fail if they can't be imported
# This allows test discovery to work even when some modules have issues
try:
    from base_test_classes import (
        CapabilityHandlersTestBase,
        CommandServiceTestBase,
        DeviceStatusServiceTestBase,
        HealthMonitorTestBase,
        LuaTestBase,
        PanicManagerTestBase,
        TemperatureServiceTestBase,
    )
    from mock_device import (
        PyDevice,
        create_default_grill_status,
        create_default_preferences,
    )
    from utils_lua_test import LuaTestUtils

    __all__ = [
        "LuaTestBase",
        "DeviceStatusServiceTestBase",
        "TemperatureServiceTestBase",
        "CapabilityHandlersTestBase",
        "CommandServiceTestBase",
        "PanicManagerTestBase",
        "HealthMonitorTestBase",
        "PyDevice",
        "create_default_grill_status",
        "create_default_preferences",
        "LuaTestUtils",
    ]
except ImportError as e:
    # If imports fail, just provide an empty __all__ list
    # This allows test discovery to continue
    __all__ = []
    import warnings

    warnings.warn(f"Failed to import test modules: {e}", ImportWarning, stacklevel=2)
