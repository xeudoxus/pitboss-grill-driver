---@diagnostic disable: duplicate-set-field, different-requires, undefined-field, lowercase-global
-- Type definitions for test environment

---@class Device
---@field id string
---@field preferences table
---@field profile table
---@field driver table
---@field thread table
---@field events table
---@field component_events table
---@field last_event table
---@field last_component_event table
---@field is_connected boolean
---@field _fields table
---@field _latest_state string
local Device = {}

---@param o table?
---@return Device
function Device:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

---@param k string
---@return any
function Device:get_field(k) end

---@param k string
---@param v any
function Device:set_field(k, v) end

---@param evt table
function Device:emit_event(evt) end

---@param component string
---@param evt table
function Device:emit_component_event(component, evt) end

function Device:online() end
function Device:offline() end

---@param component string?
---@param cap_id string?
---@param attr string?
---@return string
function Device:get_latest_state(component, cap_id, attr)
  return self._latest_state or ""
end

-- Global test functions
---@param a any
---@param b any
---@param msg string?
function assert_eq(a, b, msg) end

-- Global test variables
---@type table
sent_commands = {}

---@type boolean
network_should_fail = false

-- Mock modules
---@class log
local log = {}
function log.debug(msg) end
function log.info(msg) end
function log.warn(msg) end
function log.error(msg) end

---@class config
local config = {}

---@class temperature_service
local temperature_service = {}

---@class device_status_service
local device_status_service = {}

---@class network_utils
local network_utils = {}

---@class custom_capabilities
local custom_capabilities = {}

---@class panic_manager
local panic_manager = {}

---@class command_service
local command_service = {}

---@class health_monitor
local health_monitor = {}

---@class pitboss_api
local pitboss_api = {}

---@class capability_handlers
local capability_handlers = {}

---@class device_manager
local device_manager = {}

---@class discovery
local discovery = {}

---@class refresh_service
local refresh_service = {}

---@class virtual_device_manager
local virtual_device_manager = {}

return {}