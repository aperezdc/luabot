#! /usr/bin/env lua
--
-- urltitles.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--
local http_request = require("net.http").request
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

local function html_unescape(str)
	return (str:gsub("&(.-);", entity_map))
end


local function should_expand(url, include, exclude)
	if include then
		for _, pattern in ipairs(include) do
			if url:match(pattern) then
				return true
			end
		end
		if not exclude then
			return false
		end
	end
	if exclude then
		for _, pattern in ipairs(exclude) do
			if url:match(pattern) then
				return false
			end
		end
	end
	return true
end


local function handle_urltitles(bot, event)
	local url = event.body and event.body:match("https?://%S+")
	if url then
		local include_patterns, exclude_patterns = nil, nil
		if event.room_jid then
			local room_config = bot.config.plugin.muc[event.room_jid]
			if room_config and room_config.urltitles then
				include_patterns = room_config.urltitles.include
				exclude_patterns = room_config.urltitles.exclude
			end
		else
			include_patterns = bot.config.plugin.urltitles.include
			exclude_patterns = bot.config.plugin.urltitles.exclude
		end

		if not should_expand(url, include_patterns, exclude_patterns) then
			return
		end

		http_request(url, nil, function (data, code)
			if code ~= 200 then
				return
			end

			local title = data:match("<[tT][iI][tT][lL][eE][^>]*>([^<]+)")
			if title then
				event:post(html_unescape(title:gsub("\n", " ")))
			end
		end)
	end
end

return function (bot)
	local function handle_message(event) handle_urltitles(bot, event) end
	bot:hook("message", handle_message)
	bot:hook("groupchat/joined", function (room)
		room:hook("message", handle_message)
	end)
end
