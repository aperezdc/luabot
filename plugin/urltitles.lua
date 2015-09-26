#! /usr/bin/env lua
--
-- urltitles.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--
local http_request = require("net.http").request

local function handle_urltitles(message)
	local url = message.body and message.body:match("https?://%S+")
	if url then
		http_request(url, nil, function (data, code)
			if code ~= 200 then
				return
			end

			local title = data:match("<[tT][iI][tT][lL][eE][^>]*>([^<]+)")
			if title then
				title = title:gsub("\n", " ")
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
