---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Tests probe-specific functionality including offset handling, caching, and event emission
local config = require("config")
local Device = require("device")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

package.loaded["st.capabilities"] = require("tests.mocks.st.capabilities")
local capabilities = require "st.capabilities"


package.loaded["log"] = require("tests.mocks.log")


package.loaded["custom_capabilities"] = nil
package.loaded["custom_capabilities"] = require("custom_capabilities")

-- Mock temperature service with probe-specific behavior


-- panic_manager mock is provided by shared mocks

-- Clear any cached device_status_service to ensure fresh load
package.loaded["device_status_service"] = nil
local device_status_service = require("device_status_service")

-- Test 1: Probe temperature offset application
local dev = Device:new({})
dev.preferences = { 
  probe1Offset = 5,
  probe2Offset = -3
}

-- Mock profile components for probe testing
dev.profile = {
  components = {
    probe1 = { id = "probe1" },
    probe2 = { id = "probe2" }
  }
}

-- Track emitted events
local emitted_events = {}
local emitted_component_events = {}

dev.emit_event = function(self, event)
  table.insert(emitted_events, event)
end

dev.emit_component_event = function(self, component, event)
  table.insert(emitted_component_events, {component = component, event = event})
end

-- Test probe 1 with valid temperature and offset
local status = {
  p1_temp = 100,  -- Valid temperature
  p2_temp = config.CONSTANTS.DISCONNECT_VALUE,  -- Disconnected probe
  grill_temp = 225,
  set_temp = 250,
  is_fahrenheit = true
}

device_status_service.update_device_status(dev, status)

-- Verify probe 1 offset was applied using Steinhart-Hart calibration
-- With Steinhart-Hart, 100°F + 5°F offset should be close to 105°F but may differ slightly
local probe1_cached = dev:get_field("cached_p1_temp")
local expected_range_min = 104
local expected_range_max = 107
assert_eq(probe1_cached >= expected_range_min and probe1_cached <= expected_range_max, true, 
         string.format("Probe 1 Steinhart-Hart calibration should be in range %d-%d°F (got: %d)", 
                      expected_range_min, expected_range_max, probe1_cached))

-- Test 2: Probe disconnection handling
-- Reset events
emitted_events = {}
emitted_component_events = {}

-- Test with disconnected probe 1 but cached value exists
dev:set_field("cached_p1_temp", 95)  -- Set cached value
status.p1_temp = config.CONSTANTS.DISCONNECT_VALUE

device_status_service.update_device_status(dev, status)

-- Should use cached value when probe is disconnected
local found_probe_event = false
for _, event in ipairs(emitted_events) do
  if event.name == "probe" and type(event.value) == "string" then
    -- The unified probe display should contain the cached temperature value (95)
    if event.value:find("95") then
      found_probe_event = true
      break
    end
  end
end
assert_eq(found_probe_event, true, "Should emit cached value when probe is disconnected")

-- Test 3: Probe temperature validation ranges
local sensor_range = config.get_sensor_range("F")

-- Test temperature below sensor range
status.p1_temp = sensor_range.min - 10
device_status_service.update_device_status(dev, status)

-- Should treat out-of-range temperature as invalid and use cache
local probe1_cached_after_invalid = dev:get_field("cached_p1_temp")
assert_eq(probe1_cached_after_invalid, 95, "Should maintain cached value when temperature is out of range")

-- Test 4: Multiple probe management
status.p1_temp = 150
status.p2_temp = 140

-- Reset events
emitted_events = {}
emitted_component_events = {}

device_status_service.update_device_status(dev, status)

-- Verify both probes are updated with their respective offsets using Steinhart-Hart
local probe1_final = dev:get_field("cached_p1_temp")  -- ~150 + 5 with Steinhart-Hart scaling
local probe2_final = dev:get_field("cached_p2_temp")  -- ~140 + (-3) with Steinhart-Hart scaling

-- Probe 1: 150°F + 5°F offset should be close to 155°F but may differ due to Steinhart-Hart
assert_eq(probe1_final >= 154 and probe1_final <= 158, true, 
         string.format("Probe 1 Steinhart-Hart calibration should be in range 154-158°F (got: %d)", probe1_final))

-- Probe 2: 140°F + (-3)°F offset should be close to 137°F but may differ due to Steinhart-Hart  
assert_eq(probe2_final >= 136 and probe2_final <= 139, true,
         string.format("Probe 2 Steinhart-Hart calibration should be in range 136-139°F (got: %d)", probe2_final))

-- Verify both probes emitted events
local probe1_event_found = false
local probe_display_event_found = false

for _, event in ipairs(emitted_events) do
  if event.name == "probe" and type(event.value) == "string" then
    -- Check that the unified probe display contains calibrated values (allowing for Steinhart-Hart differences)
    local contains_probe1 = event.value:find(tostring(probe1_final))
    local contains_probe2 = event.value:find(tostring(probe2_final))
    if contains_probe1 and contains_probe2 then
      probe_display_event_found = true
    end
  end
end

assert_eq(probe_display_event_found, true, "Unified probe display should contain both calibrated values")

-- Test 5: Probe component event emission
local probe1_component_event_found = false
local probe2_component_event_found = false

for _, comp_event in ipairs(emitted_component_events) do
  if comp_event.component and comp_event.component.id == "probe1" and comp_event.event.value == probe1_final then
    probe1_component_event_found = true
  elseif comp_event.component and comp_event.component.id == "probe2" and comp_event.event.value == probe2_final then
    probe2_component_event_found = true
  end
end

assert_eq(probe1_component_event_found, true, "Probe 1 should emit component event")
assert_eq(probe2_component_event_found, true, "Probe 2 should emit component event")

-- Test 6: Probe display formatting for disconnected probes
status.p1_temp = config.CONSTANTS.DISCONNECT_VALUE
status.p2_temp = config.CONSTANTS.DISCONNECT_VALUE

-- Clear cached values to test true disconnection
dev:set_field("cached_p1_temp", nil)
dev:set_field("cached_p2_temp", nil)

-- Reset events
emitted_events = {}

device_status_service.update_device_status(dev, status)

-- Should emit disconnect display value
local disconnect_display_found = false
for _, event in ipairs(emitted_events) do
  if event.name == "probe" and type(event.value) == "string" then
    -- The unified probe display should contain the disconnect display constant
    if event.value:find(config.CONSTANTS.DISCONNECT_DISPLAY) then
      disconnect_display_found = true
      break
    end
  end
end

assert_eq(disconnect_display_found, true, "Should emit disconnect display value for truly disconnected probes")

status.p3_temp = 120  -- Probe 3
status.p4_temp = 130  -- Probe 4

-- Reset events to ensure no p3/p4 events are emitted
emitted_events = {}
emitted_component_events = {}

device_status_service.update_device_status(dev, status)

-- Verify no individual events are emitted for probes 3&4 (they only appear in unified display)
local future_probe_events = 0
for _, event in ipairs(emitted_events) do
  if event.name == "probeC" or event.name == "probeD" then
    future_probe_events = future_probe_events + 1
  end
end

assert_eq(future_probe_events, 0, "Probes 3&4 should not emit individual events (only in unified display)")

-- Verify probes 3&4 ARE included in the unified probe display
local unified_display_includes_p3_p4 = false
for _, event in ipairs(emitted_events) do
  if event.name == "probe" and type(event.value) == "string" then
    -- Should include probe 3 (120°F) and probe 4 (130°F) values
    if event.value:find("120") and event.value:find("130") then
      unified_display_includes_p3_p4 = true
      break
    end
  end
end

assert_eq(unified_display_includes_p3_p4, true, "Unified probe display should include probes 3&4 values")