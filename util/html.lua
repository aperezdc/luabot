#! /usr/bin/env lua
--
-- html.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local strstrip = require("util.strutil").strip
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


local function unescape(text)
	return (text:gsub("&(.-);", decode_entity_map))
end

local html_title_pattern = "<[tT][iI][tT][lL][eE][^>]*>([^<]+)"

return {
	unescape = unescape;
	escape = function (text)
		return (text:gsub("([<&'\"])", encode_entity_map))
	end;

	extract_title = function (text)
		local title = text:match(html_title_pattern)
		if title then
			title = unescape(strstrip(title:gsub("%s+", " ")))
			if #title == 0 then
				title = nil
			end
		end
		return title
	end;
}
