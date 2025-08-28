-- Minimal mock for custom temperatureUnit capability
local temperatureUnit = {
	ID = "temperatureUnit",
	unit = function(event)
		return { name = "unit", value = event.value }
	end,
}
return temperatureUnit
