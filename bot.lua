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
			plugin = {};
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

function bot:fatal(...)
	self:error(...)
	self:disconnect()
	os.exit(1)
end

function bot:disconnect()
	self.stream:close()
end

-- Logging
function bot:debug(...) return self.logger("debug", ...) end
function bot:error(...) return self.logger("error", ...) end
function bot:info(...)  return self.logger("info", ...)  end
function bot:warn(...)  return self.logger("warn", ...)  end

function bot:add_plugin(name, plugin_config, global_config)
	if not self.plugin[name] then
		local f = require("plugin." .. name)
		if type(f) == "function" then
			self.plugin[name] = f(self, plugin_config, global_config) or true
			self:info("plugin '" .. name .. "' activated")
		end
	end
	return self
end


local log_stream = io.stderr
local stdio_log_map = {
	info  = "[1;1m%-5s[0;0m[0;36m %-10s[0;0m %s\n";
	warn  = "[1;33m%-5s[0;0m[0;36m %-10s[0;0m %s\n";
	error = "[1;32m%-5s[0;0m[0;36m %-10s[0;0m %s\n";
	debug = "[1;35m%-5s[0;0m[0;36m %-10s[0;0m %s\n";
}
local function stdio_color_log(what, level, message)
	local fmt = stdio_log_map[level]
	log_stream:write(fmt:format(level, what, message))
	log_stream:flush()
end
local log_format = "%-5s %-10s %s\n";
local function stdio_log(what, level, message)
	log_stream:write(log_format:format(level, what, message))
	log_stream:flush()
end


function bot:set_debug(debug_log, print_raw, color_log)
	local log_func = color_log and stdio_color_log or stdio_log
	if debug_log then
		verse.set_log_handler(log_func)
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
		verse.set_log_handler(log_func, {"info", "warn", "error"})
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


local b = bot.new()

local rooms = {}
local plugins = {}
local config = setmetatable({}, { __index = {
	room = function (name)
		return function (cfg)
			if type(cfg) ~= "table" then
				error("options for room '" .. name .. "' must be a table")
			end
			rooms[name] = cfg
		end
	end;
	plugin = function (name)
		return function (cfg)
			if type(cfg) ~= "table" then
				error("options for plugin '" .. name .. "' must be a table")
			end
			plugins[name] = cfg
		end
	end;
}})
local config_chunk, err = loadfile("config.lua", "t", config)
if not config_chunk then
	b:error("Cannot load 'config.lua': " .. tostring(err))
	return 1
end
local ok, err = pcall(config_chunk)
if not ok then
	b:error("Cannot process 'config.lua': " .. tostring(err))
	return 1
end

if not config.jid then
	b:error("No 'jid' in configuration")
	return 1
end
if not config.password then
	b:error("No 'password' in configuration")
	return 1
end
config.rooms, config.plugins = rooms, plugins

-- Configure debugging log
b:set_debug(config.debug_log, config.raw_log, config.color_log)

-- Load the MUC plug-in first, with the given configuration (if any)
b:add_plugin("muc", config.plugins.muc or {}, config)
config.plugins.muc = nil
for name, cfg in pairs(config.plugins) do
	b:add_plugin(name, cfg, config)
end

if not config.nick then
	b:warn("No 'nick' in configuration, using 'luabot'")
	config.nick = "luabot"
end

b:hook("started", function ()
	for room_jid, cfg in pairs(config.rooms) do
		b:join_room(room_jid, cfg.nick or config.nick)
	end
end)

if config.host then b.stream.connect_host = config.host end
if config.port then b.stream.connect_port = config.port end
b:connect(config.jid, config.password)
