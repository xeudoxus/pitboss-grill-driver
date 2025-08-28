-- Minimal cosock mock for tests
local cosock = {}

-- Mock spawn function for concurrent operations
function cosock.spawn(func)
  -- In test environment, just return without executing to avoid infinite loops
  -- The network scanning functionality is tested elsewhere
  return
end

cosock.socket = {
  sleep = function(_) end,
  -- minimal TCP socket placeholder with basic methods used by pitboss_api in tests
  tcp = function()
    local sock = {}
    function sock:settimeout(_) end
    function sock:connect(host, port) return true end
    function sock:send(_) return true end
    function sock:receive(_) return nil end
    function sock:close() end
    return sock
  end,
}
return cosock
