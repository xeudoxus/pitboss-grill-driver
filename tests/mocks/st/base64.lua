-- Forwarder for base64 to top-level mock

-- Always return the top-level base64 mock directly to avoid require errors
return require("base64")
