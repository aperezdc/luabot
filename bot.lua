#! /usr/bin/env lua
--
-- bot.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local stanza = require("util.stanza")
local verse = require("verse").init("client")


local bot = {}
bot.__index = bot

bot.new = (function ()
	local bot_id = 0

	return function ()
		local stream = verse.new()
		for _, name in ipairs { "version", "keepalive" } do
			stream:add_plugin(name)
		end

		bot_id = bot_id + 1
		local self = setmetatable({
			logger = verse.new_logger("bot" .. tostring(bot_id));
			stream = stream;
		}, bot)

		self:hook("started", function ()
			local presence = verse.presence()
			if self.stream.caps then
				presence:add_child(self.stream:caps())
			end
			self:send(presence)
		end)

		self.stream:hook("ready", function ()
			self.stream.version:set {
				-- XXX: Should this be configurable?
				name = "Igalia XMPP Bot (Verse/Lua)"
			}
			self:start()
		end)

		self.stream:hook("authentication-success", function ()
			self:info("logged in successfully")
		end)

		self.stream:hook("authentication-failure", function (err)
			self:error("login failed: " .. tostring(err.condition))
		end)

		self.stream:hook("disconnected", function ()
			self:info("disconnected")
			verse.quit()
		end)

		return self
	end
end)()

-- Logging
function bot:debug(...) return self.logger("debug", ...) end
function bot:error(...) return self.logger("error", ...) end
function bot:info(...)  return self.logger("info", ...)  end
function bot:warn(...)  return self.logger("warn", ...)  end

function bot:add_plugin(name)
	local f = require("plugin." .. name)
	if type(f) == "function" then
		f(self)
		self:info("plugin '" .. name .. "' activated")
	end
	return self
end

function bot:set_debug(debug_log, print_raw)
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
end

function bot:send(s)
	return self.stream:send(s)
end

function bot:send_iq(s, callback, errback)
	return self.stream:send_iq(s, callback, errback)
end

function bot:event(name, ...)
	return self.stream:event("bot/" .. name, ...)
end

function bot:hook(name, ...)
	return self.stream:hook("bot/" .. name, ...)
end

function bot:send_message(to, type, text)
	self:send(stanza.message({ to = to, type = type }):tag("body"):text(text))
end

function bot:send_presence(to, type)
	self:send(stanza.presence { to = to, type = type })
end

function bot:start()
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
				return bot:send_message(s.attr.from, s.attr.type, reply)
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
end

function bot:connect(jid, password)
	self.stream:connect_client(jid, password)
	verse.loop()
	return self
end

-- bot:set_debug(true, true)
-- bot:set_debug(true, false)

local function echo_message (event)
	if event.body:match("^luabot[:,]") then
		event:reply(event.body)
	end
end

local luabot = bot.new()
for _, name in ipairs { "muc", "invite", "urltitles", "meeting" } do
	luabot:add_plugin(name)
end

luabot:hook("bot/message", echo_message)
luabot:hook("groupchat/joining", function (room)
	room:hook("message", echo_message)
end)
luabot:hook("started", function ()
	luabot:join_room("tmp@conference.igalia.com", "luabot-testing")
end)

luabot:connect("user@server", "password")
