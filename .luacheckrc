-- .luacheckrc
std = "lua51"

-- Global ignore rules
ignore = {
   "611",  -- line contains only whitespace
}

-- File-specific overrides
files = {
   ["tests/"] = {
      ignore = {
         "211", -- unused variable
         "212", -- unused argument
         "213", -- unused loop variable
         "214", -- value assigned to variable is unused
         "231", -- variable is never accessed
         "311", -- value assigned to variable is unused
         "421", -- shadowing
         "431", -- shadowing upvalue
      }
   },
   ["tests/mocks/"] = {
      ignore = {
         "211", -- unused variable
         "212", -- unused argument
         "213", -- unused loop variable
         "214", -- value assigned to variable is unused
         "231", -- variable is never accessed
         "311", -- value assigned to variable is unused
         "421", -- shadowing
         "431", -- shadowing upvalue
      }
   }
}

-- You can add more targeted ignores if needed, e.g.:
-- files["tests/"] = { ignore = { "212" } }
