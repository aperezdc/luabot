#! /usr/bin/env lua
--
-- hello.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local hello_messages = {
	"hi there!",
	"howdy",
	"hello to you, too",
	"hiya, it's a nice day, isn't it?",
	"hello, there!",
	"happy to see you around here, sir!",
}
local function hello(command)
	return hello_messages[math.random(1, #hello_messages)]
end

local bye_messages = {
	"bye!",
	"have a nice day",
	"see you later",
	"until next time",
	"goodbye",
	"see you soon!",
}
local function goodbye(command)
	return bye_messages[math.random(1, #bye_messages)]
end


return function (bot)
	bot:add_plugin("commandevent")
	bot:hook("command/hello", hello)
	bot:hook("command/goodbye", goodbye)
	bot:hook("command/bye", goodbye)
end
