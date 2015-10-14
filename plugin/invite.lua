#! /usr/bin/env lua
--
-- invite.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local xmlns_muc = "http://jabber.org/protocol/muc"
local xmlns_muc_user = xmlns_muc .. "#user"
local xmlns_jxc = "jabber:x:conference"


local function handle_message(event)
	local x = event.stanza:get_child("x", xmlns_muc_user)

	-- Try both XEP-45 and XEP-249
	if x then
		local invite = x:get_child("invite")
		if invite then
			local nick = bot.config.plugin.invite.nick or bot.config.nick
			event.bot:join_room(event.stanza.attr.from, nick)
		end
	else
		x = event.stanza:get_child("x", xmlns_jxc)
		if x and x.attr.jid then
			local nick = bot.config.plugin.invite.nick or bot.config.nick
			event.bot:join_room(x.attr.jid, nick)
		end
	end
end


return function (bot)
	bot:hook("message", handle_message)
end
