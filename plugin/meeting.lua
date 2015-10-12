#! /usr/bin/env lua
--
-- meeting.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local tinsert, tconcat, tsort, tremove = table.insert, table.concat, table.sort, table.remove
local os_time, os_date, fopen = os.time, os.date, io.open
local str_match = string.match

-- Table key used to store the plugin config
local CONFIG = "!meeting!config"

local strstrip_pattern = "^%s*(.-)%s*$"
local function strstrip(s)
	return str_match(s, strstrip_pattern)
end


-- TODO: Probably it would be good to move this to a separate
--       module under util/
local html_entities = {
	["<" ] = "&lt;";
	[">" ] = "&gt;";
	["&" ] = "&amp;";
	["'" ] = "&apos;";
	["\""] = "&quot;";
}
local function html_escape(text)
	return (text:gsub("([<&'\"])", html_entities))
end


local html_template = [[<DOCTYPE html>
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <title>${title}</title>
    <style type="text/css">
	  body { font-family: Lato, 'Open Sans', sans-serif; font-size: 16px }
	  a { color: navy; text-decoration: none; border-bottom: 1px dotted navy }
	  a:hover { text-decoration: none; border-color: #0000b9; color: #0000b9 }
      .details { font-size: 90%; font-weight: bold }
      .itemtype { font-weight: bold }
    </style>
  </head>
  <body>
    <h1>${title}</h1>
    <p class="details">Meeting started by ${owner} at ${starttime} (UTC)
      (<a href="${filename}.log.txt">full log</a>).</p>

  </body>
</html>]]


--
-- Based on Rici Lake's simple string interpolation
-- See: http://lua-users.org/wiki/StringInterpolation
--
local function interpolate(text, vars)
	return (text:gsub('([$%%]%b{})', function (w)
		local value = vars[w:sub(3, -2)]
		if value ~= nil then
			if w:sub(1, 1) == "$" then
				return html_escape(value)
			else
				return value
			end
		else
			return w
		end
	end))
end

local function template(text)
	return function (vars)
		return interpolate(text, vars)
	end
end


-- TODO: Maybe allow overriding (or at least localizing) those messages.
local render_msg_startmeeting = template
  [[Meeting started at %{time_text} (UTC). The chair is %{owner}.
  * Useful commands: #action #agreed #help #info #idea #link #topic]]
local render_msg_endmeeting = template
  [[Meeting ended at %{time_text} (UTC).
   * Minutes: %{minutes_url}
   * Log: %{log_url}]]
local render_topic_subject = template
  "Meeting: %{title} · Topic: %{current_topic}"
local render_topic = template
  "Meeting: %{title}"
local render_msg_undo = template
  "Removed item from minutes: #%{kind} %{text}"
local render_log_line = template
  "%{time_text} <%{nick}> %{text}\n"


local meeting = {}
meeting.__index = meeting

function meeting.new(room, chair, title, time)
	local m = setmetatable({
		owner   = chair;
		title   = title;
		time    = time or os_time();
		room    = room;
		nicks   = {};
		chair   = {};
		log     = {};
		minutes = {};
	}, meeting)
	m.time_text = os_date("!%c", m.time)
	m:add_nick(chair, 0)
	m:add_chair(chair)
	return m
end

function meeting:append(kind, text, nick, time)
	local item = { time = time or os_time(), nick = nick, text = text }
	item.time_text = os_date("!%H:%M:%S", item.time)
	if kind == "log" then
		tinsert(self.log, item)
		self:add_nick(nick, 1)
	else
		if kind == "topic" then
			self.current_topic = text
		end
		item.kind = kind
		tinsert(self.minutes, item)
		self:append("log", "#" .. kind .. " " .. text, nick, item.time)
	end
end

function meeting:is_chair(nick)
	return self.chair[nick]
end

function meeting:add_chair(nick)
	self.chair[nick] = true
	return self
end

function meeting:add_nick(nick, increment)
	if self.nicks[nick] == nil then
		self.nicks[nick] = 0
	end
	self.nicks[nick] = self.nicks[nick] + (increment or 0)
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
		return render_topic_subject(self)
	else
		return render_topic(self)
	end
end

function meeting:save_logfile(logdir)
	local timestamp = os_date("!%Y%m%dT%H%S%M", self.time)
	local filename = self.room .. "-" .. timestamp .. ".log.txt"
	local logfile = fopen(logdir .. "/" .. filename, "w")

	for _, item in ipairs(self.log) do
		logfile:write(render_log_line(item))
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
			meeting:append(kind, text, event.sender.nick)
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
		text = strstrip(text or "")
		if #text == 0 then
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
		meeting:append("log", "#startmeeting " .. text, event.sender.nick)
		m[event.room] = meeting

		event:post(render_msg_startmeeting(meeting))

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
		meeting:append("log", "#endmeeting", event.sender.nick)

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

		event:post(render_msg_endmeeting {
			time_text = os_date("!%c"),
			minutes_url = minutesname,
			log_url = logname,
		})
		event.room:set_subject(meeting.saved_subject)
		event.room.bot.meeting[event.room] = nil
		event.room.bot:info("#endmeeting")
	end);

	topic = chair_only(function (meeting, event, text)
		text = strstrip(text or "")
		event.room.bot:info("#topic: " .. text)
		if #text > 0 then
			meeting:append("topic", text, event.sender.nick)
			event.room:set_subject(meeting:get_meeting_info_line())
		else
			event:reply("No topic specified")
		end
	end);

	agreed = chair_only(function (meeting, event, text)
		text = strstrip(text or "")
		event.room.bot:info("#agreed " .. text)
		if #text > 0 then
			meeting:append("agreed", text, event.sender.nick)
		else
			event:reply("No text specified")
		end
	end);

	accepted = chair_only(function (meeting, event, text)
		text = strstrip(text or "")
		event.room.bot:info("#accepted " .. text)
		if #text > 0 then
			meeting:append("accepted", text, event.sender.nick)
		else
			event:reply("No text specified")
		end
	end);

	rejected = chair_only(function (meeting, event, text)
		text = strstrip(text or "")
		event.room.bot:info("#rejected " .. text)
		if #text > 0 then
			meeting:append("rejected", txt, event.sender.nick)
		else
			event:reply("No text specified")
		end
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
		event.room.bot:info("#undo")
		-- Manually add log item instead of adding an "undo"
		-- item to avoid having #undo items in the minutes.
		meeting:append("log", "#undo", event.sender.nick)
		local item = tremove(meeting.minutes, #meeting.minutes)
		if item then
			event:reply(render_msg_undo(item))
		else
			event:reply("Nothing to undo")
		end
	end);

	nick = with_meeting(function (meeting, event, text)
		event.room.bot:info("#nick")
		meeting:add_nick(event.sender.nick, 0)
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
	else
		-- If there is a meeting in progress, add the text as a "chat" item
		local meeting = event.room.bot.meeting[event.room]
		if meeting then
			meeting:append("log", event.body, event.sender.nick)
		end
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

