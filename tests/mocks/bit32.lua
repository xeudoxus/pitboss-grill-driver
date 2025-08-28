-- Minimal bit32 mock for Lua 5.4+ compatibility in tests
local bit32 = {}
bit32.band = function(a, b)
	return a & b
end
bit32.bor = function(a, b)
	return a | b
end
bit32.bnot = function(a)
	return ~a
end
bit32.lshift = function(a, b)
	return a << b
end
bit32.rshift = function(a, b)
	return a >> b
end
bit32.arshift = function(a, b)
	return a >> b
end
bit32.bxor = function(a, b)
	return a ~ b
end
bit32.extract = function(a, f, w)
	w = w or 1
	return (a >> f) & ((1 << w) - 1)
end
bit32.replace = function(a, v, f, w)
	w = w or 1
	local mask = ((1 << w) - 1) << f
	return (a & ~mask) | ((v << f) & mask)
end
return bit32
