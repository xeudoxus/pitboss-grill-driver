-- Minimal mock for custom grillStatus capability
local grillStatus = {
	ID = "grillStatus",
	lastMessage = function(event)
		return { name = "lastMessage", value = event }
	end,
}
return grillStatus
