#! /usr/bin/env lua
--
-- strutil.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local s_match = string.match
local s_gsub  = string.gsub

--
-- Based on Rici Lake's simple string interpolation
-- See: http://lua-users.org/wiki/StringInterpolation
--
local function interpolate(text, vars)
	local html_escape = require("util.html").escape
	return (text:gsub('([$%%]%b{})', function (w)
		local value = vars[w:sub(3, -2)]
		if value ~= nil then
			value = tostring(value)
			if w:sub(1, 1) == "$" then
				return html_escape(value)
			else
				return value
			end
		else
			return w
		end
	end))
end


local strstrip_pattern = "^%s*(.-)%s*$"
local pattern_magic_chars = "([%^%$%(%)%%%.%[%]%*%+%-%?])"

return {
	strip = function (s)
		return s_match(s, strstrip_pattern)
	end;
	escape_pattern = function (s)
	   return (s_gsub(s, pattern_magic_chars, "%%%1"))
   end;
	interpolate = interpolate;
	template = function (text)
		return function (vars)
			return interpolate(text, vars)
		end
	end;
}
