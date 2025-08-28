-- Minimal cosock mock based on lua_libs-api_v14/cosock.lua for test environment
local cosock = {}
cosock.socket = {}
cosock.channel = {}
cosock.timer = {}
cosock.ssl = {}
cosock.bus = {}
cosock.asyncify = function(f)
	return f
end
cosock.spawn = function(f)
	return coroutine.create(f)
end
cosock.run = function() end
cosock.socket.tcp = function()
	return { settimeout = function() end, connect = function() end, close = function() end }
end
return cosock
