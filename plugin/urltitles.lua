#! /usr/bin/env lua
--
-- urltitles.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--
local http_request = require("net.http").request
local tonumber = tonumber
local chr = string.char


-- TODO: Generate the table of entities from the official HTML spec
local entity_map = setmetatable({
	amp    = "&"; gt     = ">"; lt     = "<";
	apos   = "'"; quot   = '"'; nbsp   = " ";
	iexcl  = "¡"; cent   = "¢"; pound  = "£";
	curren = "¤"; yen    = "¥"; brvbar = "¦";
	sect   = "§"; copy   = "ⓒ"; ordf   = "ª";
	laquo  = "«"; raquo  = "»"; reg    = "ⓡ";
	deg    = "º"; middot = "·"; iquest = "¿";
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

local function html_unescape(str)
	return (str:gsub("&(.-);", entity_map))
end


local function handle_urltitles(message)
	local url = message.body and message.body:match("https?://%S+")
	if url then
		http_request(url, nil, function (data, code)
			if code ~= 200 then
				return
			end

			local title = data:match("<[tT][iI][tT][lL][eE][^>]*>([^<]+)")
			if title then
				title = html_unescape(title:gsub("\n", " "))
				if message.room then
					message.room:send_message(title)
				else
					message:reply(title)
				end
			end
		end)
	end
end

return function (bot)
	bot:hook("message", handle_urltitles)
	bot:hook("groupchat/joined", function (room)
		room:hook("message", handle_urltitles)
	end)
end
