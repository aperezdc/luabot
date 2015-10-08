#! /usr/bin/env lua
--
-- meeting.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local tinsert, tconcat, tsort = table.insert, table.concat, table.sort
local os_time, os_date, fopen = os.time, os.date, io.open
local str_match = string.match

-- TODO: Maybe allow overriding (or at least localizing) those messages.
local msg_meeting_start = [[Meeting started at %s (UTC). The chair is %s.
   * Useful commands: #action #agreed #help #info #idea #link #topic]]
local msg_meeting_end = [[Meeting ended at %s (UTC).
   * Minutes: %s
   * Log: %s]]
local msg_subject = [[Meeting: %s]]
local msg_subject_topic = [[Meeting: %s · Topic: %s]]

-- Table key used to store the plugin config
local CONFIG = "!meeting!config"

local strstrip_pattern = "^%s*(.-)%s*$"
local function strstrip(s)
	return str_match(s, strstrip_pattern)
end


local logitem = {}
logitem.__index = logitem

function logitem.new(kind, nick, line, timestamp)
	return setmetatable({
		kind = kind;
		nick = nick;
		line = line;
		time = time or os_time();
	}, logitem)
end

function logitem:is_minutes()
	return self.kind ~= "chat"
end

local text_chat_fmt = "%s <%s> %s"
function logitem:logfile_text()
	if self.kind == "chat" then
		return text_chat_fmt:format(os_date("!%H:%M:%S", self.time),
		                            self.nick, self.line)
	end
end


local meeting = {}
meeting.__index = meeting

function meeting.new(room, chair, title, time)
	local m = setmetatable({
		nick  = chair;
		title = title;
		time  = time or os_time();
		room  = room;
		nicks = {};
		chair = {};
	}, meeting)
	m:add_chair(chair)
	return m
end

function meeting:append(item)
	if item.kind == "topic" then
		self.current_topic = item.text
	end
	if item.nick then
		self:add_nick(item.nick)
	end
	tinsert(self, item)
end

function meeting:is_chair(nick)
	return self.chair[nick]
end

function meeting:add_chair(nick)
	self.chair[nick] = true
	return self
end

function meeting:add_nick(nick)
	self.nicks[nick] = true
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

function meeting:save_logfile(logdir)
	local timestamp = os_date("!%Y%m%dT%H%S%M", self.time)
	local filename = self.room .. "-" .. timestamp .. ".log.txt"
	local logfile = fopen(logdir .. "/" .. filename, "w")

	for _, item in ipairs(self) do
		local text = item:logfile_text()
		if text then
			logfile:write(text, "\n")
		end
	end
	logfile:close()
	return filename
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
			meeting:append(logitem.new(kind, event.sender.nick, text))
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
		local meeting = meeting.new(event.room_jid, event.sender.nick, text)
		m[event.room] = meeting

		event:post(msg_meeting_start:format(os_date("!%c", meeting.timestamp),
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
		local logdir = event.room.bot.meeting[CONFIG].logdir
		local logurl = event.room.bot.meeting[CONFIG].logurl
		local logname = meeting:save_logfile(logdir)
		local minutesname = "n/a"

		if logurl then
			logname = logurl .. logname
			-- TODO: minutesname = logurl .. minutesname
		else
			logname = "n/a"
			minutesname = "n/a"
		end

		event:post(msg_meeting_end:format(os_date("!%c"),
		                                  minutesname,
		                                  logname))
		event.room:set_subject(meeting.saved_subject)
		event.room.bot.meeting[event.room] = nil
		event.room.bot:info("#endmeeting")
	end);

	topic = chair_only(function (meeting, event, text)
		if not text then
			return event:reply("No topic specified")
		end
		event.room.bot:info("#topic: " .. text)
		meeting:append(logitem.new("topic", event.sender.nick, text))
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
		event:post("Current chairs: " .. tconcat(m:get_chairs(), ", "))
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
			event:post("Current chairs: " .. tconcat(m:get_chairs(), ", "))
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
	if not event.room then
		event:reply("meeting commands are only available in chatrooms")
	end
	if not event.body then
		return
	end

	local command = event.body:match(command_pattern)
	if command and command_handlers[command] then
		command_handlers[command](event, event.body:match(argument_pattern))
	end

	-- If there is a meeting in progress, add the text as a "chat" item
	local meeting = event.room.bot.meeting[event.room]
	if meeting then
		meeting:append(logitem.new("chat", event.sender.nick, event.body))
	end
end

return function (bot, plugin_config, global_config)
	bot.meeting = {}
	bot.meeting[CONFIG] = {
		logdir = plugin_config.logdir or ".";
		logurl = plugin_config.logurl or nil;
	}
	bot:hook("groupchat/joined", function (room)
		room:hook("message", handle_message)
	end)
end

