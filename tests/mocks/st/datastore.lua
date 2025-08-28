-- Minimal real datastore mock for tests
local datastore = {}
function datastore.get(_, key)
	return nil
end
function datastore.set(_, key, value)
	return true
end
return datastore
