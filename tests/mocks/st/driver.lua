-- Minimal mock Driver for test usage
local datastore = require("tests.mocks.datastore")

local Driver = {}
Driver.__index = Driver

function Driver:get_device_info(device_uuid)
	return self.device_cache and self.device_cache[device_uuid] or nil
end

-- Make Driver callable: Driver() returns a mock device
setmetatable(Driver, {
	__call = function(_, ...)
		return Driver.init(...)
	end,
})

-- Patch: Add thread field with call_with_delay to device instances
local function add_thread_to_device(device)
	device.thread = {
		call_with_delay = function(delay, func, timer_id)
			-- Simulate timer creation for tests that patch st.timer
			local g = rawget(_G, "active_timers")
			if type(g) == "table" then
				rawset(_G, "timer_id_counter", (rawget(_G, "timer_id_counter") or 0) + 1)
				local id = rawget(_G, "timer_id_counter")
				local timer = {
					id = id,
					delay = delay,
					callback = func,
					created_at = os and os.time and os.time() or 0,
					cancelled = false,
				}
				g[id] = timer
				return timer
			end
			-- Otherwise, just call the function immediately for non-timer tests
			if type(func) == "function" then
				return func()
			elseif type(delay) == "function" then
				return delay()
			end
			return nil
		end,
	}
	return device
end

function Driver.init(name, opts)
	local device = {
		NAME = name or "TestDriver",
		device_cache = {},
		datastore = datastore.init and datastore.init() or {},
		emit_event = function(self, event) end,
		emit_component_event = function(self, component, event) end,
	}
	if type(opts) == "table" then
		for k, v in pairs(opts) do
			device[k] = v
		end
	end
	add_thread_to_device(device)

	-- Add threading capabilities to the driver object for discovery operations
	device.thread = {
		call_with_delay = function(delay, func, timer_id)
			-- Simulate timer creation for tests that patch st.timer
			local g = rawget(_G, "active_timers")
			if type(g) == "table" then
				rawset(_G, "timer_id_counter", (rawget(_G, "timer_id_counter") or 0) + 1)
				local id = rawget(_G, "timer_id_counter")
				local timer = {
					id = id,
					delay = delay,
					callback = func,
					timer_id = timer_id,
				}
				g[id] = timer
				if type(func) == "function" then
					-- For tests, execute immediately or after delay simulation
					if delay == 0 or delay < 0.1 then
						func()
					else
						-- Simulate delayed execution for longer delays
						timer.executed = false
					end
				end
				return timer
			elseif type(delay) == "function" then
				return delay()
			end
			return nil
		end,
		call_on_schedule = function(delay, func, _name)
			-- Similar to call_with_delay but with scheduling name
			return device.thread.call_with_delay(delay, func, _name)
		end,
	}

	setmetatable(device, Driver)
	return device
end

-- Global registry for Python-created devices (for integration tests)
rawset(_G, "PYTHON_CREATED_DEVICES", {})

-- Patch: If try_create_device is called and returns a Python object, store it by key
function Driver:try_create_device(device_info)
	local dbg_fields = {}
	if type(device_info) == "table" then
		for k, v in pairs(device_info) do
			dbg_fields[#dbg_fields + 1] = tostring(k) .. "=" .. tostring(v)
		end
	end
	-- Always set parent_assigned_child_key from key if not present
	if type(device_info) == "table" and not device_info.parent_assigned_child_key and device_info.key then
		device_info.parent_assigned_child_key = device_info.key
	end
	-- Call the Python-side try_create_device if available
	if self._py_try_create_device then
		local pydev = self:_py_try_create_device(device_info)
		if pydev and type(device_info) == "table" and device_info.parent_assigned_child_key then
			local reg = rawget(_G, "PYTHON_CREATED_DEVICES")
			reg[device_info.parent_assigned_child_key] = pydev
		end
		return pydev
	end
	-- Fallback: return a Lua table for pure Lua tests
	return {
		id = device_info and device_info.parent_assigned_child_key or "virtual",
		parent_assigned_child_key = device_info and device_info.parent_assigned_child_key or "virtual",
	}
end

return Driver
