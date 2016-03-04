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


return function (bot)
	bot:hook("message", function (event)
		local x = event.stanza:get_child("x", xmlns_muc_user)

		-- Try both XEP-45 and XEP-249
		if x then
			local invite = x:get_child("invite")
			if invite then
				bot:join_room(event.stanza.attr.from,
				              event:config("invite", "nick", bot.config.nick))
			end
		else
			x = event.stanza:get_child("x", xmlns_jxc)
			if x and x.attr.jid then
				bot:join_room(x.attr.jid, nick,
				              event:config("invite", "nick", bot.config.nick))
			end
		end
	end)
end
