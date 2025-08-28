-- Minimal mock for custom temperatureProbes capability
local temperatureProbes = {
	ID = "temperatureProbes",
	probe = function(event)
		return { name = "probe", value = event.value }
	end,
}
return temperatureProbes
