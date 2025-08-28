-- Enhanced Lua test runner for Pit Boss driver modules
-- Provides better organization, filtering, and reporting capabilities
---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global, undefined-global, need-check-nil

local TestRunner = {}

-- Configuration
local config = {
  colors = {
    reset = "\27[0m",
    green = "\27[32m",
    red = "\27[31m",
    yellow = "\27[33m",
    blue = "\27[34m",
    cyan = "\27[36m",
    bold = "\27[1m"
  },
  verbose = false,
  filter_pattern = nil,
  show_timing = true
}

-- Test suite registry - organized by functional groups
local test_suites = {
  all_tests = {
    name = "All Tests",
    tests = {
      -- Core Services
      {"temperature_service", "tests/unit/temperature_service_spec.lua"},
      {"device_status_service", "tests/unit/device_status_service_spec.lua"},
      {"command_service", "tests/unit/command_service_spec.lua"},
      {"command_service.comprehensive", "tests/unit/command_service_comprehensive_spec.lua"},
      {"health_monitor", "tests/unit/health_monitor_spec.lua"},
      
      -- API and Communication
      {"pitboss_api", "tests/unit/pitboss_api_spec.lua"},
      {"network_utils", "tests/unit/network_utils_spec.lua"},
      
      -- Integration Layer
      {"capability_handlers", "tests/unit/capability_handlers_spec.lua"},
      {"device_manager", "tests/unit/device_manager_spec.lua"},
      {"discovery", "tests/unit/discovery_spec.lua"},
      {"panic_manager", "tests/unit/panic_manager_spec.lua"},
      {"refresh_service", "tests/unit/refresh_service_spec.lua"},
      {"virtual_device_manager", "tests/unit/virtual_device_manager_spec.lua"},
      
      -- Infrastructure and Utilities
      {"custom_capabilities", "tests/unit/custom_capabilities_spec.lua"},
      {"command_service.light", "tests/unit/command_service_light_spec.lua"},
      {"command_service.prime", "tests/unit/command_service_prime_spec.lua"},
      {"temperature_service.states", "tests/unit/temperature_service_states_spec.lua"},
      {"temperature_service.snapping", "tests/unit/temperature_service_snapping_spec.lua"},
      {"temperature_calibration", "tests/unit/temperature_calibration_spec.lua"},
      {"health_monitor.intervals", "tests/unit/health_monitor_intervals_spec.lua"},
      {"health_monitor.timer_detection", "tests/unit/health_monitor_timer_detection_spec.lua"},
      {"encryption", "tests/unit/encryption_spec.lua"},
      {"api_communication", "tests/unit/api_communication_spec.lua"},
      {"error_handling", "tests/unit/error_handling_spec.lua"},
      {"probe_management", "tests/unit/probe_management_spec.lua"},
      {"power_management", "tests/unit/power_management_spec.lua"}
    }
  }
}

-- Test execution state
local test_results = {
  passed = 0,
  failed = 0,
  skipped = 0,
  failures = {},
  suite_results = {},
  start_time = nil,
  end_time = nil
}

-- Utility functions
local function get_time()
  return os.clock()
end

local function format_duration(duration)
  if duration < 1 then
    return string.format("%.0fms", duration * 1000)
  else
    return string.format("%.2fs", duration)
  end
end

local function should_run_test(test_name)
  if not config.filter_pattern then
    return true
  end
  return string.match(test_name, config.filter_pattern) ~= nil
end

local function print_colored(color, text)
  print(config.colors[color] .. text .. config.colors.reset)
end

local function print_header(text)
  print_colored("bold", "\n" .. string.rep("=", 60))
  print_colored("bold", text)
  print_colored("bold", string.rep("=", 60))
end

local function print_suite_header(suite_name)
  print_colored("cyan", "\n" .. config.colors.bold .. "Suite: " .. suite_name .. config.colors.reset)
  print_colored("cyan", string.rep("-", 40))
end

-- Test execution
function TestRunner.run_test(test_name, test_file)
  if not should_run_test(test_name) then
    test_results.skipped = test_results.skipped + 1
    if config.verbose then
      print_colored("yellow", "[SKIP] " .. test_name)
    end
    return true
  end

  local start_time = get_time()
  
  -- Suppress output during test execution unless verbose
  local original_print = print
  if not config.verbose then
    print = function() end
  end
  
  local ok, err = pcall(dofile, test_file)
  
  -- Restore print
  print = original_print
  
  local duration = get_time() - start_time
  local timing_info = config.show_timing and (" (" .. format_duration(duration) .. ")") or ""
  
  if ok then
    print_colored("green", "[PASS] " .. test_name .. timing_info)
    test_results.passed = test_results.passed + 1
    return true
  else
    print_colored("red", "[FAIL] " .. test_name .. timing_info)
    if config.verbose or true then -- Always show errors
      print_colored("yellow", "       " .. tostring(err))
    end
    test_results.failed = test_results.failed + 1
    table.insert(test_results.failures, {
      name = test_name,
      error = tostring(err),
      duration = duration
    })
    return false
  end
end

function TestRunner.run_suite(suite_name, suite_config)
  print_suite_header(suite_config.name)
  
  local suite_results = {
    name = suite_config.name,
    passed = 0,
    failed = 0,
    skipped = 0,
    start_time = get_time()
  }
  
  for _, test_info in ipairs(suite_config.tests) do
    local test_name, test_file = test_info[1], test_info[2]
    
    if should_run_test(test_name) then
      local success = TestRunner.run_test(test_name, test_file)
      if success then
        suite_results.passed = suite_results.passed + 1
      else
        suite_results.failed = suite_results.failed + 1
      end
    else
      suite_results.skipped = suite_results.skipped + 1
    end
  end
  
  suite_results.duration = get_time() - suite_results.start_time
  test_results.suite_results[suite_name] = suite_results
  
  -- Print suite summary
  local total = suite_results.passed + suite_results.failed + suite_results.skipped
  local status_color = suite_results.failed == 0 and "green" or "red"
  print_colored(status_color, string.format(
    "Suite completed: %d/%d passed (%s)",
    suite_results.passed,
    total,
    format_duration(suite_results.duration)
  ))
end

function TestRunner.print_final_summary()
  print_header("TEST SUMMARY")
  
  local total_duration = test_results.end_time - test_results.start_time
  local total_tests = test_results.passed + test_results.failed + test_results.skipped
  
  print(string.format("Total tests: %d", total_tests))
  print_colored("green", string.format("Passed: %d", test_results.passed))
  if test_results.failed > 0 then
    print_colored("red", string.format("Failed: %d", test_results.failed))
  end
  if test_results.skipped > 0 then
    print_colored("yellow", string.format("Skipped: %d", test_results.skipped))
  end
  print(string.format("Duration: %s", format_duration(total_duration)))
  
  -- Suite breakdown
  if next(test_results.suite_results) then
    print_colored("cyan", "\nSuite Breakdown:")
    for suite_name, suite_result in pairs(test_results.suite_results) do
      local status_icon = suite_result.failed == 0 and "✓" or "✗"
      local status_color = suite_result.failed == 0 and "green" or "red"
      print_colored(status_color, string.format(
        "  %s %s: %d/%d passed (%s)",
        status_icon,
        suite_result.name,
        suite_result.passed,
        suite_result.passed + suite_result.failed,
        format_duration(suite_result.duration)
      ))
    end
  end
  
  -- Failure details
  if #test_results.failures > 0 then
    print_colored("red", "\nFailed Tests:")
    for _, failure in ipairs(test_results.failures) do
      print_colored("red", "  ✗ " .. failure.name)
      if config.verbose then
        print_colored("yellow", "    " .. failure.error)
      end
    end
  end
  
  -- Final status
  print_colored("bold", string.rep("=", 60))
  if test_results.failed == 0 then
    print_colored("green", "✓ ALL TESTS PASSED!")
  else
    print_colored("red", "✗ SOME TESTS FAILED")
  end
  print_colored("bold", string.rep("=", 60))
end

function TestRunner.setup_environment()
  -- Set package paths with real source modules first, then mocks for platform components
  package.path = table.concat({
    "src/?.lua",
    "../src/?.lua",
    "tests/mocks/?.lua",
    "tests/mocks/?/init.lua", 
    "tests/mocks/?/?.lua",
    "mocks/?.lua",
    "mocks/?/init.lua",
    "mocks/?/?.lua", 
    package.path
  }, ";")
  
  -- Ensure core temperature_service is loaded for modules that expect it in package.loaded
  package.loaded["temperature_service"] = nil
  require("temperature_service")
  
  -- Load real custom capabilities from src (not mocked)
  package.loaded["custom_capabilities"] = require("custom_capabilities")
  
  -- Ensure st module structure is available
  if not package.loaded["st"] then
    package.loaded["st"] = {}
  end
  if not package.loaded["st"].capabilities then
    package.loaded["st"].capabilities = require("tests.mocks.st.capabilities")
  end
  
  -- Load shared test helpers to provide DRY helpers and common mocks
  package.loaded["tests.test_helpers"] = require("tests.test_helpers")
end

function TestRunner.run_all(options)
  options = options or {}
  
  -- Apply configuration
  config.verbose = options.verbose or false
  config.filter_pattern = options.filter
  config.show_timing = options.timing ~= false
  
  TestRunner.setup_environment()
  
  test_results.start_time = get_time()
  
  print_header("PITBOSS GRILL DRIVER - TEST SUITE")
  
  if config.filter_pattern then
    print_colored("yellow", "Filter: " .. config.filter_pattern)
  end
  
  -- Run all test suites
  for suite_name, suite_config in pairs(test_suites) do
    TestRunner.run_suite(suite_name, suite_config)
  end
  
  test_results.end_time = get_time()
  
  TestRunner.print_final_summary()
  
  -- Exit with appropriate code
  if test_results.failed > 0 then
    os.exit(1)
  end
end

-- Parse command line arguments
function TestRunner.parse_args(args)
  local options = {}
  
  for i, arg in ipairs(args) do
    if arg == "--verbose" or arg == "-v" then
      options.verbose = true
    elseif arg == "--filter" or arg == "-f" then
      options.filter = args[i + 1]
    elseif arg == "--no-timing" then
      options.timing = false
    elseif arg == "--help" or arg == "-h" then
      TestRunner.print_help()
      os.exit(0)
    end
  end
  
  return options
end

function TestRunner.print_help()
  print("Pit Boss Grill Driver Test Runner")
  print("")
  print("Usage: lua tests/runner.lua [options]")
  print("")
  print("Options:")
  print("  -v, --verbose     Show verbose output including test execution details")
  print("  -f, --filter      Run only tests matching the given pattern")
  print("  --no-timing       Disable timing information")
  print("  -h, --help        Show this help message")
  print("")
  print("Examples:")
  print("  lua tests/runner.lua")
  print("  lua tests/runner.lua --verbose")
  print("  lua tests/runner.lua --filter temperature")
  print("  lua tests/runner.lua --filter command_service")
end

return TestRunner