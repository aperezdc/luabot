#! /usr/bin/env lua
--
-- meeting.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local tinsert   = table.insert
local tconcat   = table.concat
local os_time   = os.time
local str_match = string.match

local strstrip_pattern = "^%s*(.-)%s*$"
local function strstrip(s)
	return str_match(s, strstrip_pattern)
end


local logitem = {}
logitem.__index = logitem

function logitem.new(nick, line, timestamp)
	return setmetatable({
		nick = nick;
		line = line;
		time = time or os_time();
	}, logitem)
end


local meeting = {}
meeting.__index = meeting

function meeting.new(chair, title, time)
	return setmetatable({
		chair = { [chair]=true };
		title = title;
		time  = time or os_time();
	}, meeting)
end

function meeting:append(item)
	tinsert(self, item)
end

function meeting:is_chair(nick)
	return self.chair[nick]
end

function meeting:add_chair(nick)
	self.chair[nick] = true
	return self
end

function meeting:remove_chair(nick)
	self.chair[nick] = nil
	return self
end

function meeting:get_chairs()
	local result = {}
	for nick, _ in pairs(self.chair) do
		tinsert(result, nick)
	end
	return result
end


local function with_meeting(f)
	return function (event, ...)
		local meeting = event.room.bot.meeting[event.room]
		if meeting then
			f(meeting, event, ...)
		else
			event:reply("No meeting in progress")
		end
	end
end

local function item_adder(kind)
	return with_meeting(function (meeting, event, text)
		text = strstrip(text or "")
		event.room.bot:info("#" .. kind .. " " .. text)
		if #text then
			meeting:append(kind, event, text)
		else
			event:reply("No text to add as " .. kind .. " given")
		end
	end)
end

local function chair_only(f)
	return with_meeting(function (meeting, event, ...)
		if meeting:is_chair(event.sender.nick) then
			f(meeting, event, ...)
		else
			event:reply("Only chairs can do that!")
		end
	end)
end


local command_handlers = {
	startmeeting = function (event, text)
		if not text then
			return event:reply("No meeting title specified")
		end
		event.room.bot:info("#startmeeting: " .. text)

		local m = event.room.bot.meeting
		if m[event.room] then
			return event:reply("A meeting is already in progress!")
		end
		m[event.room] = meeting.new(event.sender.nick, text)
	end;

	endmeeting = chair_only(function (meeting, event, text)
		event.room.bot.meeting[event.room] = nil
		-- TODO: Write meeting logs
		event.room.bot:info("#endmeeting")
	end);

	topic = chair_only(function (meeting, event, text)
		if not text then
			return event:reply("No topic specified")
		end
		-- TODO: Actually change topic and record it
		event.room.bot:info("#topic: " .. text)
	end);

	agreed = chair_only(function (meeting, event, text)
		if not text then
			return event:reply("No text specified")
		end
		-- TODO: Actually record agreement
		event.room.bot:info("#agreed " .. text)
	end);

	accepted = chair_only(function (meeting, event, text)
		if not text then
			return event:reply("No text specified")
		end
		-- TODO: Actually record accepted item
		event.room.bot:info("#accepted " .. text)
	end);

	rejected = chair_only(function (meeting, event, text)
		if not text then
			return event:reply("No text specified")
		end
		-- TODO: Actually record rejected item
		event.room.bot:info("#rejected " .. text)
	end);

	chair = chair_only(function (meeting, event, text)
		text = strstrip(text or "")
		if #text > 0 then
			-- FIXME: Validate JID/nick properly
			m:add_chair(text)
		end
		event:reply("/me Current chairs: " .. tconcat(m:get_chairs(), ", "))
	end);

	unchair = chair_only(function (meeting, event, text)
		text = strstrip(text or "")
		if #text > 0 then
			if not m:is_chair(event.sender.nick) then
				return event:reply("Only chairs can remove other chairs")
			end
			if event.sender.nick == text then
				return event:reply("You cannot unchair yourself")
			end
			-- FIXME: Validate JID/nick properly
			m:remove_chair(text)
			event:reply("/me Current chairs: " .. tconcat(m:get_chairs(), ", "))
		else
			event:reply("No nick given")
		end
	end);

	undo = chair_only(function (meeting, event, text)
		-- TODO: Implement
		event.room.bot:info("#undo")
	end);

	nick = with_meeting(function (meeting, event, text)
		-- TODO: Implement
		event.room.bot:info("#nick")
	end);

	-- TODO: Do we want lurk/unlurk/meetingname/restriclogs/meetingtopic?
}

-- Item adders
for _, kind in ipairs { "action", "info", "idea", "help", "link" } do
	command_handlers[kind] = item_adder(kind)
end

-- Some aliases
command_handlers.agree = command_handlers.agreed
command_handlers.accept = command_handlers.accepted
command_handlers.reject = command_handlers.rejected


local command_pattern = "^#([%w]+)"
local argument_pattern = "^#[%w]+%s+(.*)$"
local function handle_message(event)
	local command = event.body:match(command_pattern)
	if not command or not command_handlers[command] then
		return
	end
	if not event.room then
		event:reply("meeting commands are only available in chatrooms")
	end
	command_handlers[command](event, event.body:match(argument_pattern))
end

return function (bot, plugin_config, global_config)
	bot.meeting = {}
	bot:hook("groupchat/joined", function (room)
		room:hook("message", handle_message)
	end)
end

