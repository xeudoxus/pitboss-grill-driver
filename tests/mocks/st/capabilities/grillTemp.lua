-- Minimal mock for custom grillTemp capability
local grillTemp = {
	ID = "grillTemp",
	currentTemp = function(event)
		return { name = "currentTemp", value = event.value, unit = event.unit }
	end,
	targetTemp = function(event)
		return { name = "targetTemp", value = event.value, unit = event.unit }
	end,
}
return grillTemp
