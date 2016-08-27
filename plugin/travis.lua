#! /usr/bin/env lua
--
-- travis.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local template   = require "util.strutil" .template
local formdecode = require "util.http" .formdecode
local sha2       = require "util.sha2" .hash256
local jsondecode = require "util.json" .decode
local jsonnull   = require "util.json" .null
local stanza     = require "util.stanza"
local jid        = require "util.jid"

-- TODO: Improve this template.
local format_event = template
"[%{repository.owner_name}/%{repository.name}] Build %{status_message} - %{build_url}"

local function handle_webhook(bot, room, request, response)
   local token = bot:get_config("travis", "token", nil, room.jid)
   if not token then
      bot:debug("travis: no token configured for room %s", room.jid)
      return
   end

   local repo = request.headers.travis_repo_slug
   if not (token and repo and request.headers.authorization) then
      return 401  -- Unauthorized
   end
   -- TODO: Use a timing safe comparison algorithm.
   if request.headers.authorization ~= sha2(repo .. token) then
      return 401  -- Unaithorized
   end

   local data = formdecode(request.body)
   if not (data and data.payload) then
      return 400  -- Bad Request
   end

   bot:debug("travis: notification for room %q, repo %q", room.jid, repo)

   data = jsondecode(data.payload)
   if not data then
      return 400  -- Bad Request
   end

   response:send()  -- Signal the request as accepted early

   local attr = { from = bot.rooms[room.jid].nick }
   local body = format_event(data)
   room:send(stanza.message(attr, body))
end

return function (bot)
   bot:hook("groupchat/joined", function (room)
      local token = bot:get_config("travis", "token", nil, room.jid)
      if token then
         bot:add_plugin("httpevent")
         bot:debug("travis: webhook listener at /travis/%s", room.jid)
         bot:hook("http/post/travis/" .. room.jid, function (event)
            return handle_webhook(bot, room, event.request, event.response)
         end)
      end
   end)
end
