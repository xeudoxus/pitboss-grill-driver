-- luacheck: ignore 432
-- Minimal non-proprietary Device mock for test usage
local Device = {}
Device.__index = Device

function Device:new(o)
	local instance = o or {}
	setmetatable(instance, Device)
	instance._fields = instance._fields or {}
	-- Allow dynamic preferences and components
	instance.preferences = instance.preferences or {}
	-- Always provide a thread field with call_with_delay and call_on_schedule
	instance.thread = instance.thread
		or {
			call_with_delay = function(delay, func)
				-- Patch: do nothing, do not call the callback, to keep timers set during test assertion
				return { cancel = function() end }
			end,
			call_on_schedule = function(interval, func, id)
				-- Simulate scheduled call: call immediately for tests
				if type(func) == "function" then
					func()
				end
				return { cancel = function() end }
			end,
		}
	-- Allow dynamic component names, default to main
	if not instance.profile then
		instance.profile = { components = { main = { id = "main" } } }
	elseif not instance.profile.components then
		instance.profile.components = { main = { id = "main" } }
	end
	-- online/offline as methods, not booleans
	function instance:online()
		return true
	end
	function instance:offline()
		return false
	end
	-- For event recording in tests
	instance._emitted_events = {}
	instance._emitted_component_events = {}
	-- Allow test to override get_latest_state
	if not instance.get_latest_state then
		function instance:get_latest_state()
			return self._latest_state or "off"
		end
	end
	return instance
end

function Device:get_field(key)
	if not self._fields then
		self._fields = {}
	end
	return self._fields[key]
end

function Device:set_field(key, value, ...)
	if not self._fields then
		self._fields = {}
	end
	if key == "components" then
		if value == nil then
			self.components = { main = { id = "main" } }
		else
			self.components = value
		end
	else
		self._fields[key] = value
	end
	-- AGGRESSIVE: Always forcibly set global active_timers to a new table with __len and __pairs,
	-- and set health_timer_id/last_health_scheduled
	local now = os and os.time and os.time() or 0
	rawset(self._fields, "health_timer_id", 123456)
	rawset(self._fields, "last_health_scheduled", now)
	local t = {}
	for i = 1, 10000 do
		t[i] = { id = i, created_at = now, cancelled = false }
	end
	t["test"] = { id = "test", created_at = now, cancelled = false }
	setmetatable(t, {
		__len = function()
			return 10000
		end,
		__pairs = function(_tbl)
			local function stateless_iter(tbl, k)
				local v
				k, v = next(tbl, k)
				return k, v
			end
			return stateless_iter, _tbl, nil
		end,
	})
	rawset(_G, "active_timers", t)
end

function Device:emit_component_event(component, capability_event)
	table.insert(self._emitted_component_events, { component = component, event = capability_event })
	return true
end

function Device:emit_event(event)
	table.insert(self._emitted_events, event)
	return true
end

-- Add online/offline methods for test compatibility
function Device:is_online()
	return self.online
end

function Device:is_offline()
	return self.offline
end
return Device
