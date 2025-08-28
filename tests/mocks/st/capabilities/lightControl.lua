-- Minimal mock for custom lightControl capability
local lightControl = {
	ID = "lightControl",
	lightState = function(event)
		return { name = "lightState", value = event.value }
	end,
}
return lightControl
