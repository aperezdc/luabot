#! /usr/bin/env lua
--
-- muc.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local jid = require("util.jid")
local stanza = require("util.stanza")
local xmlns_muc = "http://jabber.org/protocol/muc"

return function (bot)
	bot.stream:add_plugin("groupchat")
	bot.rooms = bot.stream.rooms

	-- Forward groupchat/* events to the bot
	local fwevents = {
		"groupchat/joining",
		"groupchat/joined",
		"groupchat/leaving",
		"groupchat/left",
	}
	for i = 1, #fwevents do
		bot.stream:hook(fwevents[i], function (room, ...)
			room.bot = bot
			bot:event(fwevents[i], room, ...)
		end)
	end

	function bot:join_room(room_jid, nick)
		local room = bot.stream:join_room(room_jid, nick)
		room.bot = bot
		room:hook("message", function (event)
			local s = event.stanza
			local replied = false
			if event.nick == room.nick then
				return true
			end
			function event:reply(...)
				if replied then return false end
				replied = true
				for i = 1, select("#", ...) do
					local r = stanza.reply(s)
					if s.attr.type == "groupchat" then
						r.attr.type = s.attr.type
						r.attr.to = jid.bare(s.attr.to)
					end
					local message = select(i, ...)
					if message:sub(1, 4) ~= "/me " and event.sender and r.attr.type == "groupchat" then
						message = (event.reply_to or event.sender.nick) .. ": " .. message
					end
					room:send(r:tag("body"):text(message))
				end
			end
			function event:post(text)
				local m = stanza.reply(s)
				if s.attr.type == "groupchat" then
					m.attr.type = s.attr.type
					m.attr.to = jid.bare(s.attr.to)
				end
				room:send(m:tag("body"):text(text))
			end
			function event:config(plugin_name, setting_name, default)
				return bot:get_config(plugin_name, setting_name, default, self.room_jid)
			end
			function event:room_config(plugin)
				return bot:room_config(self.room_jid, plugin)
			end
		end, 500)
		return room
	end

	function bot:room_config(room_jid, plugin)
		local config = self.config.plugin.muc[room_jid]
		if config ~= nil and plugin ~= nil then
			config = config[plugin]
		end
		return config
	end

	bot.stream:hook("pre-groupchat/joining", function (presence)
		local muc_x = presence:get_child("x", xmlns_muc)
		if muc_x then
			muc_x:tag("history", { maxstanzas = 0 })
		end
	end)

	bot:hook("started", function ()
		for room_jid, room_config in pairs(bot.config.plugin.muc) do
			bot:join_room(room_jid, room_config.nick or bot.config.nick)
		end
	end)
end
