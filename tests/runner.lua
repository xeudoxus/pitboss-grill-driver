#!/usr/bin/env lua
-- Main test runner entry point for Pit Boss driver tests
-- Usage: lua tests/runner.lua [options]

-- Parse command line arguments
local args = {...}
local TestRunner = require("tests.test_runner")

-- Check if we're being run directly or required
if arg and arg[0] and string.match(arg[0], "runner%.lua$") then
  -- Running directly, parse args and execute
  local options = TestRunner.parse_args(args)
  TestRunner.run_all(options)
else
  -- Being required, return the module
  return TestRunner
end