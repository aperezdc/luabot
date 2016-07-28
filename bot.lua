#! /usr/bin/env lua
--
-- bot.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

-- Determine whether loading one of the modules without additional
-- dependencies can be successfully loaded with the "luabot" prefix.
-- In that case, we are using libraries installed by LuaRocks, and
-- we need to modify "package.path" to prefix /luabot/ to the paths
-- in order for the thirdparty modules to work.
if (pcall(require, "luabot.util.basexx")) then
   local prefixed_paths = {}
   for path in package.path:gmatch("[^;]+") do
      table.insert(prefixed_paths, (path:gsub("^([^%?]*)%?(.*)$", "%1luabot/?%2")))
   end
   package.path = table.concat(prefixed_paths, ";") .. package.path
end

-- Lua 5.2 needs this to be able to load Verse
if _VERSION:match("^Lua 5%.2") then
	package.path = package.path .. ";./?/init.lua"
	require("verse.client")
end

-- Allow loading modules from thirdparty/<name>/<name>.so
package.cpath = package.cpath .. ";./thirdparty/?/?.so"


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
			config = {};  -- Replaced by :configure()
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

function bot:add_plugin(name)
	if not self.plugin[name] then
		local f = require("plugin." .. name)
		if type(f) == "function" then
			if not self.config.plugin[name] then
				self.config.plugin[name] = {}
			end
			self.plugin[name] = f(self) or true
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
		local bot = self
		local body = s:get_child("body")
		local event = {
			config = function (self, plugin_name, setting_name, default)
				local value = bot.config.plugin[plugin_name]
				if not value then return nil end
				if setting_name then
					return value[setting_name] or default
				else
					return value
				end
			end;
			room_config = function () return nil end;
			sender = { jid = s.attr.from };
			body = (body and body:get_text()) or nil;
			stanza = s;
		}
		if s.name == "message" then
			local replied = false
			function event:reply(...)
				if replied then
					return false
				end
				replied = true
				for i = 1, select("#", ...) do
					bot:send_message(s.attr.from, s.attr.type, (select(i, ...)))
				end
			end
			event.post = event.reply
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
	self.stream:connect_client(jid or self.config.jid,
	                           password or self.config.password)
	verse.loop()
	return self
end

function bot:_reconfigure()
	--
	-- XXX: Technically those shouldn't be changed while the stream is open,
	--      but anyway after :connect() is called those are not used anymore.
	--      Anyway, it is good to do this here to allow multiple :configure()
	--      calls before :connect()
	--
	if self.config.host then
		self.stream.connect_host = self.config.host
	else
		self.stream.connect_host = nil
	end
	if self.config.port then
		self.stream.connect_port = self.config.port
	else
		self.stream.connect_port = nil
	end

	-- Configure debugging log
	self:set_debug(self.config.debug_log,
	               self.config.raw_log,
	               self.config.color_log)

	--
	-- We can safely call :add_plugin() each time that reconfiguration is
	-- requested; only the first call for a plugin will cause it being loaded.
	--
	for name, _ in pairs(self.config.plugin) do
		self:add_plugin(name)
	end
end

function bot:configure(config)
	-- TODO: Instead of replacing, merge configuration items.
	self.config = config
	-- TODO: Fire event(s) informing that the bot has been reconfigured.
	self:_reconfigure()
	return self
end

function bot:load_config(path)
	local rooms = {}
	local plugin = {}
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
				plugin[name] = cfg
			end
		end;
	}})
	local config_chunk, err = loadfile(path, "t", config)
	if not config_chunk then
		self:fatal("Cannot load config: " .. tostring(err))
	end
	local ok, err = pcall(config_chunk)
	if not ok then
		self:fatal("Cannot process '" .. path .. "': " .. tostring(err))
	end

	if not config.jid then
		self:fatal("No 'jid' in configuration")
	end
	if not config.password then
		self:fatal("No 'password' in configuration")
	end
	if not config.nick then
		self:warn("No 'nick' in configuration, using 'luabot'")
		config.nick = "luabot"
	end
	config.plugin = plugin

	-- If any "room" statement was seen, ensure that the MUC plugin is loaded
	for room_jid, room_config in pairs(rooms) do
		if not config.plugin.muc then
			config.plugin.muc = {}
		end
		if config.plugin.muc[room_jid] then
			self:warn("MUC room '" .. room_jid .. "' configured more than once")
		else
			config.plugin.muc[room_jid] = room_config
		end
	end

	return self:configure(config)
end

function bot:get_config(plugin_name, setting_name, default, room_jid)
   local global_config = self.config.plugin[plugin_name]
   if not global_config then
      return nil
   end
   if room_jid then
      local room_config = self:room_config(room_jid, plugin_name)
      if room_config then
         if setting_name then
            return room_config[setting_name] or global_config[setting_name] or default
         else
            return room_config or global_config
         end
      end
   end
   if setting_name then
      return global_config[setting_name] or default
   else
      return global_config
   end
end


-- Run, Forrest, run!
local config_file = "config.lua"
if #arg > 0 then config_file = arg[1] end
local b = bot.new():load_config(config_file):connect()
