#! /usr/bin/env lua
--
-- meeting.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local tinsert, tconcat, tsort = table.insert, table.concat, table.sort
local os_time, os_date = os.time, os.date
local str_match = string.match

-- TODO: Maybe allow overriding (or at least localizing) those messages.
local msg_meeting_start = [[/me Meeting started at %s (UTC). The chair is %s.
	* Useful commands: #action #agreed #help #info #idea #link #topic]]
local msg_meeting_end = [[/me Meeting ended at %s (UTC).
	* Minutes: %s
	* Log: %s]]
local msg_subject = [[Meeting: %s]]
local msg_subject_topic = [[Meeting: %s · Topic: %s]]


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

function meeting:get_meeting_info_line()
	if self.current_topic then
		return msg_subject_topic:format(self.title, self.current_topic)
	else
		return msg_subject:format(self.title)
	end
end

function meeting:set_topic(topic)
	-- XXX: Does this need to put a line to the log, or is this called
	--      automatically when a "topic" log item is added?
	self.current_topic = topic
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
		local room = event.room
		room.bot:info("#startmeeting: " .. text)

		local m = room.bot.meeting
		if m[room] then
			return event:reply("A meeting is already in progress!")
		end

		-- Create a new meeting
		local meeting = meeting.new(event.sender.nick, text)
		m[event.room] = meeting

		event:reply(msg_meeting_start:format(os_date("!%c", meeting.timestamp),
		                                     meeting:get_chairs()[1]))

		-- We need to listen for chat room subject changes in order
		-- to be able to know what the subject used to be, to restore
		-- it at the end of the meeting.
		local function handle_event_change(event)
			meeting.saved_subject = event.from
			room:unhook("subject-changed", handle_event_change)
		end
		room:hook("subject-changed", handle_event_change)
		event.room:set_subject(meeting:get_meeting_info_line())
	end;

	endmeeting = chair_only(function (meeting, event, text)
		-- TODO: Write meeting logs
		event.room.bot:info("#endmeeting")

		-- Restore chat root topic
		event.room:set_subject(meeting.saved_subject)

		-- TODO: Format URLs in which the logs are available
		event:reply(msg_meeting_end:format(os_date("!%c"),
		                                   "n/a",
		                                   "n/a"))
		event.room.bot.meeting[event.room] = nil
	end);

	topic = chair_only(function (meeting, event, text)
		if not text then
			return event:reply("No topic specified")
		end
		event.room.bot:info("#topic: " .. text)
		meeting:set_topic(text)
		event.room:set_subject(meeting:get_meeting_info_line())
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

function command_handlers.commands(event, text)
	local commands = {}
	for name, _ in pairs(command_handlers) do
		tinsert(commands, name)
	end
	tsort(commands)
	event:reply("Available commands: " .. tconcat(commands, ", "))
end


local command_pattern = "^#([%w]+)"
local argument_pattern = "^#[%w]+%s+(.*)$"
local function handle_message(event)
	if not event.body then
		return
	end
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

