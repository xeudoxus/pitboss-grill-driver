-- Minimal mock JSON module for test usage
local json = {}

-- Simple encode/decode for testing
json.encode = function(val)
	if type(val) == "table" then
		return "{}"
	elseif type(val) == "string" then
		return '"' .. val .. '"'
	else
		return tostring(val)
	end
end

json.decode = function(str)
	if str == "{}" or str == "[]" then
		return {}
	elseif str:sub(1, 1) == '"' and str:sub(-1) == '"' then
		return str:sub(2, -2)
	else
		return {}
	end
end

return json
