-- Minimal real net_utils mock for tests
local net_utils = {}
function net_utils.get_ip()
	return "127.0.0.1"
end
return net_utils
