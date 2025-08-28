local datastore = {}
datastore.save = function(...)
	return true
end
datastore.load = function(...)
	return {}
end
return datastore
