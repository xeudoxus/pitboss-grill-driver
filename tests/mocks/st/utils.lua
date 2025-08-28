-- Minimal real utils module copied from lua_libs-api_v14
local utils = {}

function utils.stringify_table(tbl)
	local result = "{"
	for k, v in pairs(tbl) do
		result = result .. tostring(k) .. ":" .. tostring(v) .. ","
	end
	return result .. "}"
end

return utils
