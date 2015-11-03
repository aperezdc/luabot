#! /usr/bin/env lua
--
-- lmdb.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local lmdb = require("lightningmdb")

local lmdbstore = {}
lmdbstore.__index = lmdbstore

function lmdbstore.new(bot)
	if type(bot.config.plugin.keystore.path) ~= "string" then
		bot:fatal("keystore: lmdb: no 'path' specified, or it is not a string")
	end
	local db = { env = lmdb.env_create(); }
	db.db = db.env:open(bot.config.plugin.keystore.path, 0, 420)
	return setmetatable(db, lmdbstore)
end

function lmdbstore:get(key)
	assert(type(key) == "string")

	local t = self.env:txn_begin(nil, lmdb.MDB_RDONLY)
	local v = nil
	if t then
		local d = t:dbi_open(nil, lmdb.MDB_CREATE)
		if d then
			v = t:get(d, key)
		end
	end
	t:commit()

	return v
end

function lmdbstore:set(key, value)
	assert(type(key) == "string")
	assert(type(value) == "string")

	local t = self.env:txn_begin(nil, 0)
	local d = t:dbi_open(nil, lmdb.MDB_CREATE)
	local r = t:put(d, key, value, 0)
	t:commit()
end

function lmdbstore:del(key)
	assert(type(key) == "string")

	local t = self.env:txn_begin(nil, 0)
	local d = t:dbi_open(nil, lmdb.MDB_CREATE)
	local r = t:del(d, key, 0)
	t:commit()
end

return lmdbstore.new
