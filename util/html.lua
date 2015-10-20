#! /usr/bin/env lua
--
-- html.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local chr = string.char

-- TODO: Generate the tables of entities from the official HTML spec
local encode_entity_map = {
	["<" ] = "&lt;";
	[">" ] = "&gt;";
	["&" ] = "&amp;";
	["'" ] = "&apos;";
	["\""] = "&quot;";
}

local decode_entity_map = setmetatable({
	amp    = "&"; gt     = ">"; lt     = "<";
	apos   = "'"; quot   = '"'; nbsp   = " ";
	iexcl  = "¡"; cent   = "¢"; pound  = "£";
	curren = "¤"; yen    = "¥"; brvbar = "¦";
	sect   = "§"; copy   = "ⓒ"; ordf   = "ª";
	laquo  = "«"; raquo  = "»"; reg    = "ⓡ";
	deg    = "º"; middot = "·"; iquest = "¿";
	ndash  = "–"; mdash  = "—"; bull   = "·";
}, { __index = function (_, s)
		if s:sub(1, 1) == "#" then
			if s:sub(2, 2) == "x" then
				return chr(tonumber(s:sub(3), 16))
			else
				return chr(tonumber(s:sub(2)))
			end
		end
	end
})


return {
	escape = function (text)
		return (text:gsub("([<&'\"])", encode_entity_map))
	end;
	unescape = function (text)
		return (text:gsub("&(.-);", decode_entity_map))
	end;
}
