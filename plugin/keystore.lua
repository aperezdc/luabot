#! /usr/bin/env lua
--
-- keystore.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

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


local factories = {
	filesystem = fsdir.new;
	memory     = inmem.new;
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
