-- Test configuration and constants for Pit Boss driver tests
-- Centralizes test-specific configuration and provides consistent test data

local TestConfig = {}

-- Test execution configuration
TestConfig.execution = {
  default_timeout = 5.0, -- seconds
  slow_test_threshold = 1.0, -- seconds
  memory_threshold = 1024, -- KB
  max_retries = 3
}

-- Test data constants
TestConfig.test_data = {
  valid_ip_addresses = {
    "192.168.1.100",
    "10.0.0.50",
    "172.16.0.10"
  },
  
  invalid_ip_addresses = {
    "",
    "invalid",
    "256.256.256.256",
    "192.168.1",
    "192.168.1.256"
  },
  
  temperature_ranges = {
    fahrenheit = {
      min = 70,
      max = 500,
      typical = {180, 225, 250, 300, 350, 400}
    },
    celsius = {
      min = 21,
      max = 260,
      typical = {82, 107, 121, 149, 177, 204}
    }
  },
  
  device_states = {
    "off",
    "on",
    "heating",
    "cooling",
    "error"
  },
  
  probe_configurations = {
    single_probe = {1, 0, 0, 0},
    dual_probe = {1, 1, 0, 0},
    triple_probe = {1, 1, 1, 0},
    quad_probe = {1, 1, 1, 1}
  }
}

-- Mock response templates
TestConfig.mock_responses = {
  grill_status = {
    power_on = {
      power_state = "on",
      grill_temp = 225,
      target_temp = 250,
      probe_temps = {165, 0, 0, 0},
      pellet_level = 75,
      light_state = "off"
    },
    
    power_off = {
      power_state = "off",
      grill_temp = 70,
      target_temp = 0,
      probe_temps = {70, 0, 0, 0},
      pellet_level = 75,
      light_state = "off"
    },
    
    heating = {
      power_state = "on",
      grill_temp = 180,
      target_temp = 250,
      probe_temps = {120, 0, 0, 0},
      pellet_level = 70,
      light_state = "off"
    },
    
    at_temperature = {
      power_state = "on",
      grill_temp = 250,
      target_temp = 250,
      probe_temps = {165, 0, 0, 0},
      pellet_level = 65,
      light_state = "off"
    }
  },
  
  network_commands = {
    power_on = {cmd = "power", arg = "on"},
    power_off = {cmd = "power", arg = "off"},
    set_temp = {cmd = "set_temp", arg = 250},
    light_on = {cmd = "light", arg = "on"},
    light_off = {cmd = "light", arg = "off"}
  }
}

-- Test environment presets
TestConfig.environments = {
  minimal = {
    network = false,
    timers = false,
    device_status = true
  },
  
  standard = {
    network = true,
    timers = false,
    device_status = true,
    network_options = {
      should_fail = false
    }
  },
  
  full = {
    network = true,
    timers = true,
    device_status = true,
    network_options = {
      should_fail = false,
      responses = {}
    }
  },
  
  failure_simulation = {
    network = true,
    timers = true,
    device_status = true,
    network_options = {
      should_fail = true
    }
  }
}

-- Test categories and their configurations
TestConfig.categories = {
  unit = {
    name = "Unit Tests",
    timeout_multiplier = 1.0,
    memory_limit = 512 -- KB
  },
  
  integration = {
    name = "Integration Tests", 
    timeout_multiplier = 2.0,
    memory_limit = 1024 -- KB
  },
  
  performance = {
    name = "Performance Tests",
    timeout_multiplier = 5.0,
    memory_limit = 2048 -- KB
  },
  
  stress = {
    name = "Stress Tests",
    timeout_multiplier = 10.0,
    memory_limit = 4096 -- KB
  }
}

-- Helper functions for test configuration
function TestConfig.get_environment(name)
  return TestConfig.environments[name] or TestConfig.environments.standard
end

function TestConfig.get_category_config(name)
  return TestConfig.categories[name] or TestConfig.categories.unit
end

function TestConfig.get_test_timeout(category)
  local cat_config = TestConfig.get_category_config(category)
  return TestConfig.execution.default_timeout * cat_config.timeout_multiplier
end

function TestConfig.get_memory_limit(category)
  local cat_config = TestConfig.get_category_config(category)
  return cat_config.memory_limit
end

-- Generate test device configurations
function TestConfig.create_device_config(preset_name, overrides)
  overrides = overrides or {}
  local preset = TestConfig.mock_responses.grill_status[preset_name] or TestConfig.mock_responses.grill_status.power_off
  
  local config = {}
  for k, v in pairs(preset) do
    config[k] = v
  end
  
  for k, v in pairs(overrides) do
    config[k] = v
  end
  
  return config
end

-- Generate test scenarios
function TestConfig.create_test_scenario(name, config)
  return {
    name = name,
    description = config.description or ("Test scenario: " .. name),
    setup = config.setup or function() end,
    teardown = config.teardown or function() end,
    data = config.data or {},
    expectations = config.expectations or {},
    category = config.category or "unit"
  }
end

-- Common test scenarios
TestConfig.scenarios = {
  power_cycle = TestConfig.create_test_scenario("power_cycle", {
    description = "Test power on/off cycle",
    data = {
      initial_state = "off",
      target_state = "on",
      final_state = "off"
    },
    category = "integration"
  }),
  
  temperature_control = TestConfig.create_test_scenario("temperature_control", {
    description = "Test temperature setting and monitoring",
    data = {
      initial_temp = 70,
      target_temp = 250,
      tolerance = 5
    },
    category = "integration"
  }),
  
  probe_monitoring = TestConfig.create_test_scenario("probe_monitoring", {
    description = "Test temperature probe monitoring",
    data = {
      probe_count = 4,
      probe_temps = {165, 140, 0, 0}
    },
    category = "unit"
  }),
  
  network_failure = TestConfig.create_test_scenario("network_failure", {
    description = "Test network failure handling",
    data = {
      failure_type = "timeout",
      retry_count = 3
    },
    category = "integration"
  })
}

return TestConfig