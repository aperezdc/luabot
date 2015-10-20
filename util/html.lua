#! /usr/bin/env lua
--
-- html.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local html_entities = {
	["<" ] = "&lt;";
	[">" ] = "&gt;";
	["&" ] = "&amp;";
	["'" ] = "&apos;";
	["\""] = "&quot;";
}

return {
	escape = function (text)
		return (text:gsub("([<&'\"])", html_entities))
	end;
}
