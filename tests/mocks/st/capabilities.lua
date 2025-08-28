local capabilities = {}

capabilities.panicAlarm = {
	ID = "st.panicAlarm",
	panicAlarm = function(args)
		return { capability = "panicAlarm", attribute = "panicAlarm", value = args.value }
	end,
}
capabilities["{{NAMESPACE}}.grillStatus"] = {
	ID = "{{NAMESPACE}}.grillStatus",
	lastMessage = function(args)
		if type(args) == "table" and args.value then
			return { attribute = "lastMessage", value = args.value }
		else
			return { attribute = "lastMessage", value = args }
		end
	end,
	panic = { NAME = "panic" },
	commands = {
		panic = { NAME = "panic" },
	},
}

capabilities["{{NAMESPACE}}.temperatureProbes"] = {
	ID = "{{NAMESPACE}}.temperatureProbes",
	probe = function(args)
		return { name = "probe", value = args.value }
	end,
	commands = {},
}

capabilities["{{NAMESPACE}}.pelletStatus"] = {
	ID = "{{NAMESPACE}}.pelletStatus",
	fanState = function(args)
		return { name = "fanState", value = args.value }
	end,
	augerState = function(args)
		return { name = "augerState", value = args.value }
	end,
	ignitorState = function(args)
		return { name = "ignitorState", value = args.value }
	end,
	commands = {},
}

capabilities["{{NAMESPACE}}.lightControl"] = {
	ID = "{{NAMESPACE}}.lightControl",
	lightState = function(args)
		return { name = "lightState", value = args.value }
	end,
	commands = {
		setLightState = {
			NAME = "setLightState",
		},
	},
}

capabilities["{{NAMESPACE}}.grillTemp"] = {
	ID = "{{NAMESPACE}}.grillTemp",
	currentTemp = function(args)
		return { name = "currentTemp", value = args.value, unit = args.unit }
	end,
	targetTemp = function(args)
		return { name = "targetTemp", value = args.value, unit = args.unit }
	end,
	commands = {
		targetTemp = {
			NAME = "targetTemp",
		},
	},
}

capabilities["{{NAMESPACE}}.temperatureUnit"] = {
	ID = "pitboss-grill-driver.temperatureUnit",
	unit = function(args)
		return { name = "unit", value = args.value }
	end,
	commands = {
		setTemperatureUnit = {
			NAME = "setTemperatureUnit",
		},
	},
}

capabilities["{{NAMESPACE}}.primeControl"] = {
	ID = "pitboss-grill-driver.primeControl",
	primeState = function(args)
		return { name = "primeState", value = args.value }
	end,
	commands = {
		setPrimeState = {
			NAME = "setPrimeState",
		},
	},
}

capabilities.refresh = {
	ID = "st.refresh",
	commands = {
		refresh = {
			NAME = "refresh",
		},
	},
}

capabilities.switch = {
	ID = "st.switch",
	switch = {
		NAME = "switch",
		on = function()
			return { name = "switch", value = "on", capability = "st.switch" }
		end,
		off = function()
			return { name = "switch", value = "off", capability = "st.switch" }
		end,
	},
	commands = {
		on = {
			NAME = "on",
		},
		off = {
			NAME = "off",
		},
	},
}

capabilities.thermostatHeatingSetpoint = {
	ID = "st.thermostatHeatingSetpoint",
	heatingSetpoint = function(args)
		return { name = "heatingSetpoint", value = args.value, unit = args.unit }
	end,
	heatingSetpointRange = function(args)
		return { name = "heatingSetpointRange", value = args.value, unit = args.unit }
	end,
	commands = {
		setHeatingSetpoint = {
			NAME = "setHeatingSetpoint",
		},
	},
}

capabilities.powerMeter = {
	ID = "st.powerMeter",
	power = function(args)
		if args == nil then
			args = {}
		end
		local event = { name = "power", value = args.value, unit = args.unit, capability = "st.powerMeter" }
		return event
	end,
}

capabilities.temperatureMeasurement = {
	ID = "st.temperatureMeasurement",
	temperature = function(args)
		if args == nil then
			args = {}
		end
		local event =
			{ name = "temperature", value = args.value, unit = args.unit, capability = "st.temperatureMeasurement" }
		return event
	end,
	temperatureRange = function(args)
		if args == nil then
			args = {}
		end
		local event = {
			name = "temperatureRange",
			value = args.value,
			unit = args.unit,
			capability = "st.temperatureMeasurement",
		}
		return event
	end,
}

return capabilities
