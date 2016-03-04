#! /usr/bin/env lua
--
-- shortcuts.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local shortcut_pattern = "([a-zA-Z]+)[%#%-]([%d-]+)"

return function (bot)
	local function handle_message(event)
		local body = event.body
		if not body then return end
		if event.delay then return end  -- Skip MUC history messages

		for name, identifier in body:gmatch(shortcut_pattern) do
			name = name:lower()

			local config = event:config("shortcuts")
			if config == nil then
				config = bot.config.plugin.shortcuts.enabled
			end
			if type(config) == "table" then
				if not config[name] then
					return
				end
			elseif not config then
				return
			end

			local shortcut = {
				name   = name;
				param  = identifier;
				sender = event.sender;
				stanza = event.stanza;
				room   = event.room;
				reply  = event.reply;
				post   = event.post;
			}
			local ret = bot:event("shortcut/" .. name, shortcut)
			if ret == nil then
				ret = bot:event("unhandled-shortcut", shortcut)
			end
			if type(ret) == "string" then
				if ret:sub(1, 5) == "/say " then
					event:post(ret:sub(6, -1))
				else
					event:reply(ret)
				end
			end
		end
	end

	bot:hook("message", handle_message)
	bot:hook("groupchat/joining", function (room)
		room:hook("message", handle_message)
	end)
end
