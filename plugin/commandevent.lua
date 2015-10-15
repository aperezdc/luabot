#! /usr/bin/env lua
--
-- commandevent.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local command_pattern = "^([%a%-%_%d]+)(%s?)(.*)$"
local room_command_pattern = "^([%a%-%_%d]+)[:;,%s]%s*([%a%-%_%d]+)(%s?)(.*)$"

return function (bot)
	local function handle_message(event)
		local body = event.body
		if not body then return end
		if event.delay then return end  -- Skip MUC history messages

		local command, hasparam, param
		if event.room then
			local nick
			nick, command, hasparam, param = body:match(room_command_pattern)
			if nick ~= event.room.nick then
				return
			end
		else
			command, hasparam, param = body:match(command_pattern)
		end

		if hasparam ~= " " then
			param = nil
		end

		if command then
			local command_event = {
				command = command;
				param   = param;
				sender  = event.sender;
				stanza  = event.stanza;
				room    = event.room;
				reply   = event.reply;
				post    = event.post;
			}
			local ret = bot:event("command/" .. command, command_event)
			if ret == nil then
				ret = bot:event("unhandled-command", command_event)
			end
			if type(ret) == "string" then
				if ret:sub(1, 5) == "/say " then
					event:post(ret:sub(6, -1))
				else
					event:reply(ret)
				end
			end
			return ret
		end
	end

	bot:hook("message", handle_message)
	bot:hook("groupchat/joining", function (room)
		room:hook("message", handle_message)
	end)
end
