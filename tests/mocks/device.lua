local Device = {}
Device.__index = Device

function Device:new(o)
  o = o or {}
  o._fields = o._fields or {}
  o.preferences = o.preferences or {}
  -- Ensure all needed components for tests, including Grill_Error for error reporting
  o.profile = o.profile or { components = { ["Standard_Grill"] = {id="Standard_Grill"}, probe1 = {id="probe1"}, probe2 = {id="probe2"}, error = {id="error"}, Grill_Error = {id="Grill_Error"} } }
  o.driver = o.driver or { get_child_devices = function() return {} end, get_devices = function() return {} end }
  o.thread = o.thread or { 
    call_on_schedule = function(_, _, fn) fn() end,
    call_with_delay = function(_, delay, fn) 
      if package.loaded["st.timer"] and package.loaded["st.timer"].set_timeout then
        return package.loaded["st.timer"].set_timeout(delay, fn)
      end
      return {cancel = function() end} -- Return mock timer
    end
  }
  -- For test assertions, store all emitted events
  o.events = {}
  o.component_events = {}
  return setmetatable(o, self)
end

function Device:get_field(k) return self._fields[k] end
function Device:set_field(k, v) self._fields[k] = v end
function Device:emit_event(evt)
  self.last_event = evt
  table.insert(self.events, evt)
end
function Device:emit_component_event(component, evt)
  self.last_component_event = evt
  table.insert(self.component_events, {component = component, event = evt})
end
function Device:online() self.is_connected = true end
function Device:offline() self.is_connected = false end

return Device