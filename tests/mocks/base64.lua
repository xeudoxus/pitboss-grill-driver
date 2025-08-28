-- Minimal base64 mock for test environment, based on lua_libs-api_v14/base64.lua interface
local base64 = {}
base64.encode = function(val)
	return ""
end
base64.decode = function(str)
	return ""
end
return base64
