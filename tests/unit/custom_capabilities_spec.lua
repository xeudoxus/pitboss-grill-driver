---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil, missing-fields, inject-field, param-type-mismatch, assign-type-mismatch
-- Comprehensive custom_capabilities tests using config constants
local config = require("config")

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "assert_eq failed") .. string.format(" (got: %s, expected: %s)", tostring(a), tostring(b)), 2) end
end

local custom_capabilities = require("custom_capabilities")

-- Test 1: Custom capability structure validation
assert_eq(type(custom_capabilities), "table", "custom_capabilities should be a module table")

-- Test 2: Grill temperature capability
if custom_capabilities.grillTemp then
  assert_eq(type(custom_capabilities.grillTemp), "table", "grillTemp should be a capability table")
  
  if custom_capabilities.grillTemp.targetTemp then
    local target_temp_event = custom_capabilities.grillTemp.targetTemp({value = 225, unit = "F"})
    assert_eq(type(target_temp_event), "table", "targetTemp should create event table")
  end
  
  if custom_capabilities.grillTemp.currentTemp then
    local current_temp_event = custom_capabilities.grillTemp.currentTemp({value = 200, unit = "F"})
    assert_eq(type(current_temp_event), "table", "currentTemp should create event table")
  end
end

-- Test 3: Grill status capability
if custom_capabilities.grillStatus then
  assert_eq(type(custom_capabilities.grillStatus), "table", "grillStatus should be a capability table")
  
  if custom_capabilities.grillStatus.status then
    local status_event = custom_capabilities.grillStatus.status({value = "Connected"})
    assert_eq(type(status_event), "table", "status should create event table")
  end
end

-- Test 4: Temperature probes capability
if custom_capabilities.temperatureProbes then
  assert_eq(type(custom_capabilities.temperatureProbes), "table", "temperatureProbes should be a capability table")
  
  if custom_capabilities.temperatureProbes.probe then
    local probe_event = custom_capabilities.temperatureProbes.probe({value = "Probe 1: 150°F | Probe 2: 160°F"})
    assert_eq(type(probe_event), "table", "probe should create event table")
  end
end

-- Test 5: Pellet status capability
if custom_capabilities.pelletStatus then
  assert_eq(type(custom_capabilities.pelletStatus), "table", "pelletStatus should be a capability table")
  
  if custom_capabilities.pelletStatus.level then
    local pellet_event = custom_capabilities.pelletStatus.level({value = "Normal"})
    assert_eq(type(pellet_event), "table", "pellet level should create event table")
  end
end

-- Test 6: Light control capability
if custom_capabilities.lightControl then
  assert_eq(type(custom_capabilities.lightControl), "table", "lightControl should be a capability table")
  
  if custom_capabilities.lightControl.lightState then
    local light_event = custom_capabilities.lightControl.lightState({value = "ON"})
    assert_eq(type(light_event), "table", "lightState should create event table")
  end
end

-- Test 7: Prime control capability
if custom_capabilities.primeControl then
  assert_eq(type(custom_capabilities.primeControl), "table", "primeControl should be a capability table")
  
  if custom_capabilities.primeControl.primeState then
    local prime_event = custom_capabilities.primeControl.primeState({value = "ON"})
    assert_eq(type(prime_event), "table", "primeState should create event table")
  end
end

-- Test 8: Temperature unit capability
if custom_capabilities.temperatureUnit then
  assert_eq(type(custom_capabilities.temperatureUnit), "table", "temperatureUnit should be a capability table")
  
  if custom_capabilities.temperatureUnit.unit then
    local unit_event = custom_capabilities.temperatureUnit.unit({value = config.CONSTANTS.DEFAULT_UNIT})
    assert_eq(type(unit_event), "table", "unit should create event table")
  end
end

-- Test 9: Power meter capability (if custom)
if custom_capabilities.powerMeter then
  assert_eq(type(custom_capabilities.powerMeter), "table", "powerMeter should be a capability table")
  
  if custom_capabilities.powerMeter.power then
    local power_event = custom_capabilities.powerMeter.power({value = 100, unit = "W"})
    assert_eq(type(power_event), "table", "power should create event table")
  end
end

-- Test 10: Error status capability
if custom_capabilities.errorStatus then
  assert_eq(type(custom_capabilities.errorStatus), "table", "errorStatus should be a capability table")
  
  if custom_capabilities.errorStatus.errorCode then
    local error_event = custom_capabilities.errorStatus.errorCode({value = "no_error"})
    assert_eq(type(error_event), "table", "errorCode should create event table")
  end
end