---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Set up package path - prioritize src over mocks for this test
package.path = "src/?.lua;tests/mocks/?.lua;tests/mocks/?/init.lua;" .. package.path

-- Clear any previously loaded health_monitor to ensure we get the real one
package.loaded["health_monitor"] = nil

local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

-- Use real custom_capabilities and existing mocks
package.loaded["st.capabilities"] = require("tests.mocks.st.capabilities")
package.loaded["custom_capabilities"] = nil
package.loaded["custom_capabilities"] = require("custom_capabilities")
package.loaded["log"] = require("tests.mocks.log")

package.loaded["network_utils"] = {
  get_status = function(device, driver)
    return { grillTemp = 225, targetTemp = 250, connected = true }, nil
  end
}

-- Use real panic_manager module
package.loaded["panic_manager"] = nil

-- Use real device_status_service module
package.loaded["device_status_service"] = nil

-- Use real virtual_device_manager module
package.loaded["virtual_device_manager"] = nil

-- Load health_monitor after mocks are set up
local health_monitor = require("health_monitor")

-- Test interval computation with config constants
local dev = Device:new({})
dev.preferences = { refreshInterval = config.CONSTANTS.DEFAULT_REFRESH_INTERVAL }
local base_interval = config.get_refresh_interval(dev)

-- Test inactive grill interval
dev:set_field("is_preheating", false)
local inactive_interval = health_monitor.compute_interval(dev, false)
local expected_inactive = math.max(
  config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL,
  math.min(base_interval * config.CONSTANTS.INACTIVE_GRILL_MULTIPLIER, config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL)
)
assert_eq(inactive_interval, expected_inactive, "inactive interval should use config multiplier")

-- Test active grill interval
dev:set_field("is_preheating", false)
local active_interval = health_monitor.compute_interval(dev, true)
local expected_active = math.max(
  config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL,
  math.min(base_interval * config.CONSTANTS.ACTIVE_GRILL_MULTIPLIER, config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL)
)
assert_eq(active_interval, expected_active, "active interval should use config multiplier")

-- Test preheating grill interval
dev:set_field("is_preheating", true)
local preheat_interval = health_monitor.compute_interval(dev, true)
local expected_preheat = math.max(
  config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL,
  math.min(base_interval * config.CONSTANTS.PREHEATING_GRILL_MULTIPLIER, config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL)
)
assert_eq(preheat_interval, expected_preheat, "preheating interval should use config multiplier")

-- Verify interval bounds are respected
assert_eq(inactive_interval >= config.CONSTANTS.MIN_HEALTH_CHECK_INTERVAL, true, "interval should be >= minimum")
assert_eq(active_interval <= config.CONSTANTS.MAX_HEALTH_CHECK_INTERVAL, true, "interval should be <= maximum")
assert_eq(preheat_interval <= active_interval, true, "preheating should be fastest")
