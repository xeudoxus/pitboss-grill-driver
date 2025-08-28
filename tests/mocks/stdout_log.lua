-- Minimal, non-proprietary mock for stdout_log
local stdout_log = {}

function stdout_log.info(...) end
function stdout_log.warn(...) end
function stdout_log.error(...) end
function stdout_log.debug(...) end
function stdout_log.trace(...) end

return stdout_log
