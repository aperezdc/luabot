#! /usr/bin/env lua
--
-- facts.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local function fact_forget(bot, command)
	local key = "facts." .. command.param:lower()
	local fact = bot.plugin.keystore:get(key)
	if fact then
		bot.plugin.keystore:del(key)
		return ("Okay, I'll forget that %s is %s"):format(command.param, fact)
	end
end

local function maybe_fact(bot, command)
	local name, param = command.command, command.param
	local fact = bot.plugin.keystore:get("facts." .. name:lower())
	if fact then
		return fact
	elseif param and #param > 4 and param:match("^is ") then
		bot.plugin.keystore:set("facts." .. name:lower(), param:sub(4))
		return "I'll remember that"
	end
end

return function (bot)
	bot:add_plugin("keystore")
	bot:add_plugin("commandevent")
	bot:hook("command/forget", function (cmd) return fact_forget(bot, cmd) end)
	bot:hook("unhandled-command", function (cmd) return maybe_fact(bot, cmd) end)
end
