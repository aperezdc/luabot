#! /usr/bin/env lua
--
-- keystore.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

-- TODO: Right now the "filesystem" backend does its own caching, which never
--       performs eviction of values. It would be good to have a generic cache
--       (LRU, likely) which can be used to decorate any backend, in the same
--       way that wrap_serial() decorates a backend by adding serialization
--       support.

local to_base32 = require("util.basexx").to_base32

-- Recipe from:
--   http://www.lua.org/pil/12.1.2.html
--
local function serialize_basic(o)
	if type(o) == "number" then
		return tostring(o)
	else
		return string.format("%q", o)
	end
end

local function serialize(f, name, value, saved)
	saved = saved or {}
	f:write(name, " = ")
	if type(value) == "number" or type(value) == "string" then
		f:write(serialize_basic(value), "\n")
	elseif type(value) == "boolean" then
		f:write(value and "true" or "false", "\n")
	elseif type(value) == "table" then
		if saved[value] then
			f:write(saved[value], "\n")
		else
			saved[value] = name
			f:write("{}\n")
			for k, v in pairs(value) do
				local fieldname = string.format("%s[%s]", name, serialize_basic(k))
				serialize(f, fieldname, v, saved)
			end
		end
	else
		error("cannot serialize '" .. type(value) .. "' value")
	end
end


--
-- The following functions reuse the implementation of the serialization
-- scheme above to read/write values to/from strings in memory. This is
-- to be used as built-in fallback serialization if no better way is
-- available/configured.
--
-- XXX: Concatenating strings in memory might be horribly inefficient.
--
local function filelike_write(self, ...)
	for i = 1, select("#", ...) do
		self.data = self.data .. select(i, ...)
	end
end

local simpleserial = {
	serialize = function (value)
		local filelike = { data = "local "; write = filelike_write }
		serialize(filelike, "_", value)
		return filelike.data .. "return _\n"
	end;

	deserialize = function (value)
		local chunk, err = load(value, nil, "t", {})
		if not chunk then
			return nil
		end
		local ok, value = pcall(chunk)
		if ok then
			return value
		else
			return nil
		end
	end;
}


local fsdir = {}
fsdir.__index = fsdir

function fsdir:get(key)
	local chunk, err = loadfile(self.path .. "/" .. to_base32(key), "t", {})
	if not chunk then
		return nil
	end
	local ok, value = pcall(chunk)
	if ok then
		self.cache[key] = value
		return value
	else
		return nil
	end
end

function fsdir:set(key, value)
	local f = io.open(self.path .. "/" .. to_base32(key), "w")
	f:write("local ")
	serialize(f, "_", value)
	f:write("return _\n")
	f:close()
	self.cache[key] = value
	return self
end


function fsdir.new(bot)
	if type(bot.config.plugin.keystore.path) ~= "string" then
		bot:fatal("keystore: fsdir: no 'path' specified, or it is not a string")
	end
	local obj = { cache = {}, path = bot.config.plugin.keystore.path }
	return setmetatable(obj, fsdir)
end


local inmem = {}
inmem.__index = inmem

function inmem:set(key, value)
	self.data[key] = value
	return self
end

function inmem:get(key)
	return self.data[key]
end

function inmem.new(bot)
	return setmetatable({ data = {} }, inmem)
end


local function lazy_backend(name)
	return function (bot)
		return require("plugin.keystore." .. name)(bot)
	end
end


local serdedecorator = {}
serdedecorator.__index = serdedecorator

function serdedecorator.new(bot, backend)
	-- TODO: Allow loading other serialization methods here.
	local self = {
		deserialize = simpleserial.deserialize;
		serialize = simpleserial.serialize;
		backend = backend;
	}
	return setmetatable(self, serdedecorator)
end

function serdedecorator:get(key)
	local value = self.backend:get(key)
	if value then
		value = self.deserialize(value)
	end
	return value
end

function serdedecorator:set(key, value)
	self.backend:set(key, self.serialize(value))
	return self
end


local function wrap_serial(factory)
	return function (bot)
		return serdedecorator.new(bot, factory(bot))
	end
end

local factories = {
	filesystem = fsdir.new;
	memory     = inmem.new;
	lmdb       = wrap_serial(lazy_backend("lmdb"));
}

return function (bot)
	local backend = factories.memory
	if not bot.config.plugin.keystore.backend then
		bot:warn("keystore: no backend specified")
	else
		backend = factories[bot.config.plugin.keystore.backend]
		if not backend then
			bot:warn("keystore: '" .. bot.config.plugin.keystore.backend ..
				     "' is not a valid backend")
		end
	end
	if not backend then
		bot:warn("keystore: no backend specified, using 'memory'")
		backend = factories.memory
	end

	assert(type(backend) == "function",
	       "no backend factory, this shouldn't happen!")
	return backend(bot)
end
