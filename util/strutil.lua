#! /usr/bin/env lua
--
-- strutil.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local s_match = string.match

local strstrip_pattern = "^%s*(.-)%s*$"

return {
	strip = function (s)
		return s_match(s, strstrip_pattern)
	end;
}
