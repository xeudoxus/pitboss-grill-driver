local timer = {}

function timer.set_timeout(seconds, fn)
  -- For tests, run immediately and return a handle with cancel()
  local cancelled = false
  local handle = { cancel = function() cancelled = true end }
  -- In a real test you might schedule; here we invoke immediately for determinism
  fn()
  return handle
end

return timer