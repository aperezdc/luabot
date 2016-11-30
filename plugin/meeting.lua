#! /usr/bin/env lua
--
-- meeting.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local html_escape = require("util.html").escape
local strutil     = require("util.strutil")
local jid         = require("util.jid")
local lfs         = require("lfs")

-- Table key used to store the plugin config
local CONFIG = "!meeting!config"


-- TODO: Maybe allow overriding (or at least localizing) those messages.
local render_html_minutes_header = strutil.template
[[<DOCTYPE html>
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
      (<a href="${logname}.html">full log</a>).</p>

    <h3>Meeting Summary</h3>
]]
local render_html_minutes_item = strutil.template
[[  <li><span class="itemtype ${kind}">${kind}</span>: ${text}
    <span class="details">(<a href="#nick-${nick}">${nick}</a>, ${time_text})</span>
  </li>
]]
local html_log_header =
[[<DOCTYPE html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <style type="text/css">
      body { font-family: 'Source Code Pro', monospace }
      p { margin: 0 1em 0 1em }
      span.tm { color: #007020 }
      span.nk { color: #062873; font-weight: bold }
      p.command span.ll { color: #007020 }
      p.topic span.ll { color: #007020; font-weight: bold }
    </style>
  </head>
  <body>
]]
local render_html_log_entry = strutil.template
[[
<p class="${kind}">
  <a name="l-${line}"></a>
  <span class="tm">${time}</span>
  &lt;<span class="nk">${nick}</span>&gt;
  <span class="ll">${text}</span>
</p>
]]
local html_footer =
[[
  </body>
</html>
]]

local render_md_minutes_header = strutil.template
[[
# %{title}

_(Meeting started by %{owner} at %{starttime} UTC)_

## Meeting Summary

]]
local render_md_minutes_item = strutil.template
[[* _%{kind}_: %{text} (%{nick}, %{time_text})
]]

local render_msg_startmeeting = strutil.template
  [[Meeting started at %{time_text} (UTC). The chair is %{owner}.
  * Useful commands: #action #agreed #help #info #idea #link #topic]]
local render_msg_endmeeting = strutil.template
  [[Meeting ended at %{time_text} (UTC).
   * Minutes: %{logurl}/%{logname}.log.html
   * Log: %{logurl}/%{logname}.html]]
local render_topic_subject = strutil.template
  "Meeting: %{title} · Topic: %{current_topic}"
local render_topic = strutil.template
  "Meeting: %{title}"
local render_msg_undo = strutil.template
  "Removed item from minutes: #%{kind} %{text}"
local render_log_line = strutil.template
  "%{time_text} <%{nick}> %{text}\n"


local meeting = {}
meeting.__index = meeting

function meeting.new(room, chair, title, time)
	local m = setmetatable({
		owner   = chair;
		title   = title;
		time    = time or os.time();
		room    = room;
		lurk    = false;
		nicks   = {};
		chair   = {};
		log     = {};
		minutes = {};
	}, meeting)
	m.time_text = os.date("!%c", m.time)
	m:add_nick(chair, 0)
	m:add_chair(chair)
	return m
end

function meeting:append(kind, text, nick, time)
	local item = { time = time or os.time(), nick = nick, text = text }
	item.time_text = os.date("!%H:%M:%S", item.time)
	if kind == "log" then
		table.insert(self.log, item)
		self:add_nick(nick, 1)
	else
		if kind == "topic" then
			self.current_topic = text
		end
		item.kind = kind
		table.insert(self.minutes, item)
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
		table.insert(result, nick)
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

local function html_log_line_class(text)
	local match = text:match("^#(%w+)")
	if match then
		return match == "topic" and match or "command"
	else
		return "chat"
	end
end

local function makedirs(path)
   local parts = {}
   if path:sub(1, 1) == "/" then
      parts[1] = ""  -- An empty string ensures that the leading slash is added.
   end
   for part in string.gmatch(path, "[^/]+") do
      parts[#parts + 1] = part
   end
   if #parts > 1 then
      local tail = parts[#parts]
      parts[#parts] = nil
      local head = table.concat(parts, "/")
      local kind = lfs.attributes(head, "mode")
      if not kind then
         makedirs(head)
      elseif kind ~= "directory" then
         error("'" .. head .. "' is not a directory")
      end
   end
   local ok, err = lfs.mkdir(path)
   if not ok and err ~= "File exists" then
      error("creating '" .. path .. "': " .. err)
   end
end

local function dirname(path)
   local parts = {}
   if path:sub(1, 1) == "/" then
      parts[1] = ""  -- An empty string ensures that the leading slash is added.
   end
   for part in string.gmatch(path, "[^/]+") do
      parts[#parts + 1] = part
   end
   parts[#parts] = nil  -- Remove last component
   return table.concat(parts, "/")
end

function meeting:_save_logfile(logdir, logname)
	local textlog = io.open(logdir .. "/" .. logname .. ".log.txt", "w")
	local htmllog = io.open(logdir .. "/" .. logname .. ".log.html", "w")

	htmllog:write(html_log_header)
	local line_number = 0
	for _, item in ipairs(self.log) do
		line_number = line_number + 1
		htmllog:write(render_html_log_entry {
			kind = html_log_line_class(item.text),
			line = line_number,
			time = item.time_text,
			nick = item.nick,
			text = item.text,
		})
		textlog:write(render_log_line(item))
	end
	htmllog:write(html_footer)

	htmllog:close()
	textlog:close()
end

local function reorder_minutes(title, minutes)
	local agenda = {}
	local part = { title = title, items = {} }
	table.insert(agenda, part)
	for _, item in ipairs(minutes) do
		if item.kind == "topic" then
			part = { title = item.text, items = {} }
			table.insert(agenda, part)
		else
			table.insert(part.items, item)
		end
	end
	return agenda
end

function meeting:_save_minutes(logdir, logname)
	local agenda = reorder_minutes(self.title, self.minutes)
	local minutes = io.open(logdir .. "/" .. logname .. ".html", "w")
	local mdminutes = io.open(logdir .. "/" .. logname .. ".md", "w")

	local item = {
		starttime = self.time_text,
		title = self.title,
		owner = self.owner,
		logname = logname,
	}
	minutes:write(render_html_minutes_header(item))
	mdminutes:write(render_md_minutes_header(item))

	minutes:write("<ol>\n")
	for _, topic in ipairs(agenda) do
		mdminutes:write("* **", topic.title, "**\n")
		minutes:write("<li><strong class=\"topic\">",
		              html_escape(topic.title),
		              "</strong>\n")
		if #topic.items > 0 then
			minutes:write("  <ol type=\"a\">\n")
			for _, item in ipairs(topic.items) do
				minutes:write(render_html_minutes_item(item))
				mdminutes:write("  ", render_md_minutes_item(item))
			end
			minutes:write("  </ol>\n")
		end
		minutes:write("</li>\n")
	end
	minutes:write("</ol>\n")

	minutes:write("<h3>Action items</h3>\n",
	              "<ol class=\"actions\">\n")
	mdminutes:write("\n\n## Action items\n\n")
	for _, item in ipairs(self.minutes) do
		if item.kind == "action" then
			minutes:write(render_html_minutes_item(item))
			mdminutes:write(render_md_minutes_item(item))
		end
	end
	minutes:write("</ol>\n")

	minutes:write("<h3>People present (lines said)</h3>\n",
	              "<ol class=\"nicklist\">\n")
	mdminutes:write("\n\n## People present (lines said)\n\n")
	for nick, count in pairs(self.nicks) do
		minutes:write("<li>", nick, " (", tostring(count), ")</li>\n")
		mdminutes:write("* ", nick, " (", tostring(count), ")\n")
	end
	minutes:write("</ol>\n")

	minutes:write(html_footer)

	minutes:close()
	mdminutes:close()
end

function meeting:save(logdir, logname)
	local file_template_vars = {
	   HH   = os.date("!%H", self.time),
	   MM   = os.date("!%M", self.time),
	   SS   = os.date("!%S", self.time),
	   YYYY = os.date("!%Y", self.time),
	   mm   = os.date("!%m", self.time),
	   DD   = os.date("!%d", self.time),
	   time = os.date("!%Y-%m-%dT%H:%M:%SZ", self.time),
	   name = (jid.split(self.room)),
	   jid  = self.room,
   }
	logdir  = strutil.template(logdir) (file_template_vars)
	logname = strutil.template(logname)(file_template_vars)

   -- Ensure that the log directory exists
   makedirs(dirname(logdir .. "/" .. logname))
	self:_save_logfile(logdir, logname)
	self:_save_minutes(logdir, logname)

	return logname
end

local function with_meeting(f)
	return function (event, ...)
		local meeting = event.room.bot.plugin.meeting[event.room]
		if meeting then
			f(meeting, event, ...)
		else
			event:reply("No meeting in progress")
		end
	end
end

local function item_adder(kind)
	return with_meeting(function (meeting, event, text)
		text = strutil.strip(text or "")
		event.room.bot:info("#" .. kind .. " " .. text)
		if #text then
			meeting:append(kind, text, event.sender.nick)
		else
			event:reply("No text to add as " .. kind .. " given; " ..
			            "if you wanted help, use #commands instead")
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
		text = strutil.strip(text or "")
		if #text == 0 then
			return event:reply("No meeting title specified")
		end
		event.room.bot:info("#startmeeting: " .. text)

		local m = event.room.bot.plugin.meeting
		if m[event.room] then
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
		local room = event.room
		local function handle_event_change(event)
			meeting.saved_subject = event.from
			room:unhook("subject-changed", handle_event_change)
		end
		room:hook("subject-changed", handle_event_change)
		room:set_subject(meeting:get_meeting_info_line())
	end;

	endmeeting = chair_only(function (meeting, event, text)
		meeting:append("log", "#endmeeting", event.sender.nick)

		local logdir  = event.room.bot.plugin.meeting[CONFIG].logdir
		local logurl  = event.room.bot.plugin.meeting[CONFIG].logurl
		local logname = event.room.bot.plugin.meeting[CONFIG].logname

		logname = meeting:save(logdir, logname)

		if not meeting.lurk then
			event:post(render_msg_endmeeting {
				time_text = os.date("!%c"),
				logname = logname,
				logurl = logurl,
			})
		end

		event.room.bot.plugin.meeting[event.room] = nil
		event.room:set_subject(meeting.saved_subject)
		event.room.bot:info("#endmeeting")
	end);

	topic = chair_only(function (meeting, event, text)
		text = strutil.strip(text or "")
		event.room.bot:info("#topic: " .. text)
		if #text > 0 then
			meeting:append("topic", text, event.sender.nick)
			if not meeting.lurk then
				event.room:set_subject(meeting:get_meeting_info_line())
			end
		else
			event:reply("No topic specified")
		end
	end);

	agreed = chair_only(function (meeting, event, text)
		text = strutil.strip(text or "")
		event.room.bot:info("#agreed " .. text)
		if #text > 0 then
			meeting:append("agreed", text, event.sender.nick)
		else
			event:reply("No text specified")
		end
	end);

	accepted = chair_only(function (meeting, event, text)
		text = strutil.strip(text or "")
		event.room.bot:info("#accepted " .. text)
		if #text > 0 then
			meeting:append("accepted", text, event.sender.nick)
		else
			event:reply("No text specified")
		end
	end);

	rejected = chair_only(function (meeting, event, text)
		text = strutil.strip(text or "")
		event.room.bot:info("#rejected " .. text)
		if #text > 0 then
			meeting:append("rejected", txt, event.sender.nick)
		else
			event:reply("No text specified")
		end
	end);

	chair = chair_only(function (meeting, event, text)
		text = strutil.strip(text or "")
		if #text > 0 then
			-- FIXME: Validate JID/nick properly
			meeting:add_chair(text)
		end
		if not meeting.lurk then
			event:post("Current chairs: " .. table.concat(meeting:get_chairs(), ", "))
		end
	end);

	unchair = chair_only(function (meeting, event, text)
		text = strutil.strip(text or "")
		if #text > 0 then
			if event.sender.nick == text then
				return event:reply("You cannot unchair yourself")
			end
			-- FIXME: Validate JID/nick properly
			meeting:remove_chair(text)
			if not event.lurk then
				event:post("Current chairs: " .. table.concat(meeting:get_chairs(), ", "))
			end
		else
			event:reply("No nick given")
		end
	end);

	undo = chair_only(function (meeting, event, text)
		event.room.bot:info("#undo")
		-- Manually add log item instead of adding an "undo"
		-- item to avoid having #undo items in the minutes.
		meeting:append("log", "#undo", event.sender.nick)
		local item = table.remove(meeting.minutes, #meeting.minutes)
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

	lurk = chair_only(function (meeting, event, text)
		event.room.bot:info("#lurk")
		meeting:append("log", "#lurk", event.sender.nick)
		meeting.lurk = true
	end);

	unlurk = chair_only(function (meeting, event, text)
		event.room.bot:info("#unlurk")
		meeting:append("log", "#unlurk", event.sender.nick)
		meeting.lurk = false
	end);

	-- XXX: Do we want meetingname/restriclogs/meetingtopic?
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
		table.insert(commands, name)
	end
	table.sort(commands)
	event:reply("Available commands: " .. table.concat(commands, ", "),
	            "Please check http://meetbot.debian.net/Manual.html — " ..
                "I am not a MeetBot, but I can mimic most of its movements" ..
                " like a stealth ninja.")
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
		local meeting = event.room.bot.plugin.meeting[event.room]
		if meeting then
			meeting:append("log", event.body, event.sender.nick)
		end
	end
end

return function (bot)
	bot:hook("groupchat/joined", function (room)
		room:hook("message", handle_message)
	end)
	local logdir  = bot.config.plugin.meeting.logdir or "."
	local logname = bot.config.plugin.meeting.logname or "%{name}/%{time}"
	return {
		[CONFIG] = {
			logdir  = logdir,
			logname = logname,
			logurl  = bot.config.plugin.meeting.logurl or ("file://" .. logdir),
		}
	}
end

