-- Minimal JSON mock that supports encode/decode of simple tables
local json = {}

function json.encode(tbl)
  -- naive encoder: numbers and strings only
  local parts = {"{"}
  local first = true
  for k,v in pairs(tbl or {}) do
    if not first then table.insert(parts, ",") end
    first = false
    local key = string.format("\"%s\"", tostring(k))
    local val
    if type(v) == "string" then
      val = string.format("\"%s\"", v)
    else
      val = tostring(v)
    end
    table.insert(parts, key .. ":" .. val)
  end
  table.insert(parts, "}")
  return table.concat(parts)
end

function json.decode(_)
  -- not needed in current tests
  return {}
end

return json