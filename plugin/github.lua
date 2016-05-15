#! /usr/bin/env lua
--
-- github.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local template = require "util.strutil" .template
local decode   = require "util.json" .decode
local hmac     = require "util.sha1" .hmac
local stanza   = require "util.stanza"
local jid      = require "util.jid"


local format_render = {}
local format_data = {}
local function format(name, text, func)
   if type(text) == "table" then
      for index, item in ipairs(text) do
         text[index] = template(item)
      end
      format_render[name] = text
   else
      format_render[name] = { template(text) }
   end
   if type(func) == "string" then
      format_data[name] = format_data[func]
   else
      format_data[name] = func
   end
end


format("create",
   "github: %{repo}: %{ref_type} '%{ref}' created by @%{user}",
   function (data)
      return {
         ref      = data.ref,
         ref_type = data.ref_type,
         user     = data.sender.login,
         repo     = data.repository.full_name,
      }
   end)

format("delete",
   "github: %{repo}: %{ref_type} '%{ref}' deleted by @%{user}",
   "create")

format("member",
   "github: %{repo}: @%{user} %{action} collaborator @%{member}",
   function (data)
      return {
         action = data.action,
         user   = data.sender.login,
         member = data.member.login,
         repo   = data.repository.full_name,
      }
   end)

format("pull_request",
   "github: %{repo}: @%{user} %{action} PR '%{summary}'%{extra}%{state} - %{url}",
   function (data)
      local extra, state = "", data.pull_request.state
      if action == "closed" or action == "opened" then
         state = nil
      elseif action == "assigned" then
         extra = " to @" .. data.pull_request.assignee.login
      end
      return {
         action  = data.action,
         number  = data.number,
         user    = data.sender.login,
         repo    = data.repository.full_name,
         url     = data.pull_request.html_url,
         summary = data.pull_request.title,
         state   = state and (" (" .. state .. ")"),
         extra   = extra,
      }
   end)


local function make_stanza(bot, room, body)
   local bot_jid = bot.rooms[room.jid]
end

local function handle_webhook(bot, room, request, response)
   local secret = bot:get_config("github", "webhook", {}, room.jid).secret
   if secret and request.headers.x_hub_signature then
      local calculated = "sha1=" .. hmac(secret, request.body)
      -- TODO: Use a timing-safe comparison function.
      if request.headers.x_hub_signature ~= calculated then
         return 401  -- Unauthorized
      end
   end
   response:send()  -- Signal the request as accepted early

   local event = request.headers.x_github_event
   bot:debug("github: webhook event=" .. event)
   bot:debug("github: webhook payload:\n" .. request.body)

   if not format_data[event] then
      bot:warn("github: no formatter for event: " .. event)
      return
   end

   local data = format_data[event](decode(request.body))
   local attr = { from = bot.rooms[room.jid].nick }
   for _, render_message in ipairs(format_render[event]) do
      room:send(stanza.message(attr, render_message(data)))
   end
end

return function (bot)
   bot:hook("groupchat/joined", function (room)
      local webhook = bot:get_config("github", "webhook", {}, room.jid)
      if webhook.repo then
         bot:add_plugin("httpevent")
         bot:debug("github: webhook listener for " .. webhook.repo)
         bot:hook("http/post/github/" .. webhook.repo, function (event)
            return handle_webhook(bot, room, event.request, event.response)
         end)
      end
   end)
end
