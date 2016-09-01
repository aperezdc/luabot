#! /usr/bin/env lua
--
-- webhook.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

--[[

The accepted JSON payload must have the following shape:

   {
      "jids": [
         "person1@domain.com",
         "person2@domain.com"
      ],
      "mucs": [
         "room1@conference.domain.com",
         "room2@conference.domain.com"
      ],
      "text": "Message content",
      "url": "http://related-url.com/is/optional",
   }

--]]

local json_decode = require "util.json" .decode
local json_null   = require "util.json" .null
local hmac        = require "util.sha1" .hmac
local stanza      = require "util.stanza"


local function handle_webhook(bot, request, response)
   local secret = bot:get_config("webhook", "secret")
   if not secret then
      bot:warn("webhook: no secret configured")
      return 500  -- Internal server error
   end

   local signature = request.headers.x_webhook_signature
   if not signature then
      bot:debug("webhook: request does not have a X-WebHook-Signature header")
      return 400  -- Bad Request
   end

   -- TODO: Use a timing-safe comparison function.
   if signature ~= "sha1=" .. hmac(secret, request.body) then
      bot:debug("webhook: secret %q, body %q", secret, request.body)
      return 401  -- Unauthorized
   end

   local data, err = json_decode(request.body)
   if not data then
      bot:debug("webhook: invalid JSON body: %s", err)
      return 400  -- Bad request
   end

   -- Signal the request as accepted
   response:send()

   -- TODO: Allow HTML when XHTML-IM is implemented.
   local body = data.text

   local already_notified = {}
   if data.mucs and bot.rooms then
      for _, jid in ipairs(data.mucs) do
         if not already_notified[jid] then
            already_notified[jid] = true
            local room = bot.rooms[jid]
            if room then
               local attr = { from = room.nick }
               if data.url then
                  room:send(stanza.message(attr, data.url))
               end
               room:send(stanza.message(attr, body))
               bot:debug("webhook: notified MUC %q", jid)
            else
               bot:warn("webhook: skipping non-joined MUC %q", jid)
            end
         end
      end
   end

   if data.jids then
      for _, jid in ipairs(data.jids) do
         if not already_notified[jid] then
            already_notified[jid] = true
            local attr = { to = jid, type = "chat" } 
            if data.url then
               room:send(stanza.message(attr, data.url))
            end
            bot:send(stanza.message(attr, body))
            bot:debug("webhook: notified JID %q", jid)
         end
      end
   end
end

return function (bot)
   bot:add_plugin("httpevent")
   bot:debug("webhook: listener at /webhook")
   bot:hook("http/post/webhook", function (event)
      return handle_webhook(bot, event.request, event.response)
   end)
end
