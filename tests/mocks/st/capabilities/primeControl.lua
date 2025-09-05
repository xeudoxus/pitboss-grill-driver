-- Minimal mock for custom primeControl capability
local primeControl = {
	ID = "primeControl",
	primeState = function(event)
		return { name = "primeState", value = event.value }
	end,
}
return primeControl
