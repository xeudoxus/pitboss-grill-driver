-- Minimal mock for custom pelletStatus capability
local pelletStatus = {
	ID = "pelletStatus",
	fanState = function(event)
		return { name = "fanState", value = event.value }
	end,
	augerState = function(event)
		return { name = "augerState", value = event.value }
	end,
	ignitorState = function(event)
		return { name = "ignitorState", value = event.value }
	end,
}
return pelletStatus
