-- Minimal dkjson mock for Lua tests
local dkjson = {}
dkjson.encode = function(val)
	return "{}"
end
dkjson.decode = function(str)
	return {}
end
return dkjson
