#! /usr/bin/env lua
--
-- quip.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local QUIP_BUCKET_SIZE = 100
local QUIP_KEY_PREFIX = "plugin.quip."
local QUIP_INDEX_KEY = QUIP_KEY_PREFIX .. "index"

local function quip_bucket(index)
	index = index - 1
	local b = math.floor(index / QUIP_BUCKET_SIZE) * QUIP_BUCKET_SIZE
	local i = (index % QUIP_BUCKET_SIZE) + 1
	return QUIP_KEY_PREFIX .. (b + 1) .. "-" .. (b + QUIP_BUCKET_SIZE), i
end


local no_quip_quips = {
	"return -ENOQUIP;",
	"I don't know about that",
	"I don't know what to say",
	"my answer to that: (╯°□°）╯︵ ┻━┻",
}

local function get_quip(bot, command)
	local qdb = bot.plugin.keystore:get(QUIP_INDEX_KEY)
	if qdb.size > 0 then
		local bucket, index = quip_bucket(math.random(1, qdb.size))
		return "/say " .. bot.plugin.keystore:get(bucket)[index]
	else
		return "/say " .. no_quip_quips[math.random(1, #no_quip_quips)]
	end
end


local function add_quip(bot, command)
	if command.param then
		local qdb = bot.plugin.keystore:get(QUIP_INDEX_KEY)
		qdb.size = qdb.size + 1

		local bucket, index = quip_bucket(qdb.size)
		local items = bot.plugin.keystore:get(bucket) or {}
		items[index] = command.param
		bot.plugin.keystore:set(bucket, items)

		bot.plugin.keystore:set(QUIP_INDEX_KEY, qdb)
		return "I'll remember that, it's quip #" .. qdb.size
	else
		return get_quip(bot, command)
	end
end


return function (bot)
	bot:add_plugin("keystore")

	local qdb = bot.plugin.keystore:get(QUIP_INDEX_KEY)
	if not qdb then
		qdb = { size = 0, holes = {} }
		bot.plugin.keystore:set(QUIP_INDEX_KEY, qdb)
	end

	bot:add_plugin("commandevent")
	bot:hook("command/quip", function (command)
		return add_quip(bot, command)
	end)
	bot:hook("unhandled-command", function (command)
		return get_quip(bot, command)
	end)

	return qdb
end
