#! /usr/bin/env lua
--
-- bot.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local stanza = require("util.stanza")
local verse = require("verse")
require("verse.client")

local function new_connection()
	local c = verse.new()
	c:add_plugin("version")
	return c
end

local bot = {
	stream = new_connection();
	__hooks_configured = false;

	add_plugin = function (self, name)
		local f = require("plugin." .. name)
		if type(f) == "function" then
			f(self)
		end
		return self
	end;

	set_debug = function (self, debug_log, print_raw)
		if debug_log then
			verse.set_log_handler(print)
			if print_raw then
				self.stream:hook("incoming-raw", function (raw)
					print("<-- raw --")
					print(raw)
					print("<---------")
				end)
				self.stream:hook("outgoing-raw", function (raw)
					print("-- raw -->")
					print(raw)
					print("--------->")
				end)
			end
		else
			verse.set_log_handler(print, {"info", "warn", "error"})
		end
	end;

	send = function (self, s)
		return self.stream:send(s)
	end;

	send_iq = function (self, s, callback, errback)
		return self.stream:send_iq(s, callback, errback)
	end;

	event = function (self, name, ...)
		return self.stream:event("bot/" .. name, ...)
	end;

	hook = function (self, name, ...)
		return self.stream:hook("bot/" .. name, ...)
	end;

	send_message = function (self, to, type, text)
		self:send(stanza.message({ to = to, type = type }):tag("body"):text(text))
	end;

	send_presence = function (self, to, type)
		self:send(stanza.presence { to = to, type = type })
	end;

	start = function (self)
		self.stream:hook("stanza", function (s)
			local body = s:get_child("body")
			local event = {
				sender = { jid = s.attr.from };
				body = (body and body:get_text()) or nil;
				stanza = s;
			}
			if s.name == "message" then
				local replied = false
				local bot = self
				function event:reply(reply)
					if replied then
						return false
					end
					replied = true
					return bot:send_message(s.attr.from,
					                        s.attr.type,
					                        reply)
				end
			end

			local ret = nil
			if s.name == "iq" and (s.attr.type == "get" or
				                   s.attr.type == "set")
			then
				local xmlns = s.tags[1] and s.tags[1].attr.xmlns
				if xmlns then
					event.xmlns = xmlns
					ret = self:event("iq/" .. xmlns, event)
				end
			end

			if not ret then
				ret = self:event(s.name, event)
			end
			if ret and type(ret) == "table" then
				self:send(ret)
			end
			return ret
		end, 1)
		self:event("started")
	end;

	connect = function (self, jid, password)
		-- Hook up things
		if not self.__hooks_configured then
			self:hook("started", function ()
				local presence = verse.presence()
				if self.stream.caps then
					presence:add_child(self.stream:caps())
				end
				self:send(presence)
			end)

			self.stream:hook("ready", function ()
				self.stream.version:set {
					name = "Igalia XMPP Bot (Verse/Lua)"
				}
				self:start()
			end)

			self.stream:hook("authentication-success", function ()
				print("logged in successfully")
			end)

			self.stream:hook("authentication-failure", function (err)
				print("login failed: " .. tostring(err.condition))
			end)

			self.stream:hook("disconnected", function ()
				print("disconnected")
				verse.quit()
			end)
		end

		-- Connect & Run the event loop
		self.stream:connect_client(jid, password)
		verse.loop()

		return self
	end;
}

-- bot:set_debug(true, true)
-- bot:set_debug(true, false)

local function echo_message (event)
	if event.body:match("^luabot[:,]") then
		event:reply(event.body)
	end
end

for _, name in ipairs { "muc", "urltitles" } do
	bot:add_plugin(name)
end

bot:hook("bot/message", echo_message)
bot:hook("groupchat/joining", function (room)
	room:hook("message", echo_message)
end)
bot:hook("started", function ()
	bot:join_room("room@conference.server", "luabot")
end)

bot:connect("user@server", "password")
