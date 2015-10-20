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


local function qdb_add_hole(qdb, index)
	if qdb.nholes == nil then
		qdb.nholes = 0
	end
	qdb.nholes = qdb.nholes + 1
	if not qdb.holes then
		qdb.holes = {}
	end
	qdb.holes[index] = true
end


local function qdb_del_hole(qdb)
	assert(qdb.nholes > 0)
	for num, _ in pairs(qdb.holes) do
		qdb.nholes = qdb.nholes - 1
		qdb.holes[num] = nil
		return num
	end
end


local function qdb_get_nholes(qdb)
	if qdb.nholes == nil then
		qdb.nholes = 0
	end
	return qdb.nholes
end


local no_quip_quips = {
	"return -ENOQUIP;",
	"I don't know about that",
	"I don't know what to say",
	"my answer to that: (╯°□°）╯︵ ┻━┻",
}

local function get_quip(bot, command)
	local qdb = bot.plugin.keystore:get(QUIP_INDEX_KEY)

	if (qdb.size - qdb_get_nholes(qdb)) > 0 then
		local num = nil
		if command.param then
			-- With a parameter, pick a particular quip
			num = tonumber(command.param)
			if num == nil then
				return "Invalid number: " .. command.param
			end
			if num < 0 or num > qdb.size then
				return "Number out of bounds (max: " .. qdb.size .. ")"
			end
		else
			-- Without a parameter, pick a random quip
			repeat
				num = math.random(1, qdb.size)
			until not qdb.holes[num]
		end

		local bucket, index = quip_bucket(num)
		local text = bot.plugin.keystore:get(bucket)[index]
		return text and ("/say " .. text) or "That quip was deleted"
	else
		return "/say " .. no_quip_quips[math.random(1, #no_quip_quips)]
	end
end


local function add_quip(bot, command)
	if command.param then
		local qdb = bot.plugin.keystore:get(QUIP_INDEX_KEY)

		local num
		if qdb_get_nholes(qdb) > 0 then
			num = qdb_del_hole(qdb)
		else
			qdb.size = qdb.size + 1
			num = qdb.size
		end

		local bucket, index = quip_bucket(num)
		local items = bot.plugin.keystore:get(bucket) or {}
		items[index] = command.param
		bot.plugin.keystore:set(QUIP_INDEX_KEY, qdb):set(bucket, items)

		return "I'll remember that, it's quip #" .. num
	else
		return "So… what would be the text of the quip? (hint: use “quip add <text>”)"
	end
end


local function del_quip(bot, command)
	if command.param then
		local num = tonumber(command.param)
		local qdb = bot.plugin.keystore:get(QUIP_INDEX_KEY)
		if num then
			if num < 1 or num > qdb.size then
				return "Number out of bounds (max: " .. qdb.size .. ")"
			end

			local bucket, index = quip_bucket(num)
			local items = bot.plugin.keystore:get(bucket)
			qdb_add_hole(qdb, num)
			items[index] = nil
			bot.plugin.keystore:set(QUIP_INDEX_KEY, qdb):set(bucket, items)

			return "Quip #" .. num .. " has been deleted"
		else
			return "Invalid number: " .. command.param
		end
	else
		return "No quip number specified"
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

	bot:hook("command/quip", bot.plugin.commandevent.dispatch {
		add = function (command) return add_quip(bot, command) end;
		del = function (command) return del_quip(bot, command) end;
		get = function (command) return get_quip(bot, command) end;
		_   = function (command) return get_quip(bot, command) end;
	})
	bot:hook("unhandled-command", function (command)
		command.param = nil
		return get_quip(bot, command)
	end)

	return qdb
end
