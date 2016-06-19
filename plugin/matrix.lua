#! /usr/bin/env lua
--
-- matrix.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local stanza = require "util.stanza"
local json   = require "util.json"
local jid    = require "util.jid"

local KEYSTORE_NS = "plugin.matrix."

local txn_handler = {
   ["m.room.aliases"] = function (bot, event)
      -- Store the Matrix room ID to aliases mapping
      bot:debug("matrix: save room " .. event.room_id .. " -> " .. table.concat(event.content.aliases, ", "))
      bot.plugin.keystore:set(KEYSTORE_NS .. event.room_id, event.content.aliases)
      -- Store the aliases to Matrix room ID (reverse) mappings
      for _, alias in ipairs(event.content.aliases) do
         bot:debug("matrix: save alias %s -> %s", alias, event.room_id)
         bot.plugin.keystore:set(KEYSTORE_NS .. "roomid." .. alias, event.room_id)
      end
   end,

   ["m.room.message"] = function (bot, event)
      local room_aliases = bot.plugin.keystore:get(KEYSTORE_NS .. event.room_id)
      if not room_aliases then
         bot:debug("matrix: no aliases recorded for room " .. event.room_id)
         return
      end
      bot:debug("matrix: room %s -> %s", event.room_id, table.concat(room_aliases, ", "))
      -- Find the #jabber_.* alias
      local room_jids = {}
      for _, room_alias in ipairs(room_aliases) do
         local jid, hs = room_alias:match("^%#jabber_([^:]+):(.+)$")
         bot:debug("matrix:  * %s -> %s", room_alias, jid)
         if jid then
            room_jids[#room_jids + 1] = jid
         end
      end
      bot:debug("matrix: room %s -> %s", event.room_id, table.concat(room_jids, ", "))
      -- Get the message
      local message
      if event.content.msgtype == "m.text" then
         message = event.content.body
      end
      if not message then
         bot:debug("matrix: message of unsupported type " .. event.content.msgtype)
         return
      end
      bot:debug("matrix: message=\"%q\"", message)
      -- Extract the sender of the message
      local localpart, hs = event.user_id:match("^@([^:]+):(.+)$")
      bot:debug("matrix: message from localpart=" .. localpart .. " hs=" .. hs)

      for _, room_jid in ipairs(room_jids) do
         if bot.rooms[room_jid] then
            local attr = {
               from = bot.rooms[room_jid].nick,
               type = "groupchat",
               to   = room_jid,
            }
            bot:send(stanza.message(attr, message))
         end
      end
   end,
}

local function handle_matrix_transactions(bot, request, response)
   bot:debug("matrix: payload: " .. request.body)

   local data = json.decode(request.body)
   if not (data and data.events) then
      return 400  -- Bad request
   end

   for _, event in ipairs(data.events) do
      local handle = txn_handler[event.type]
      if handle then
         bot:debug("matrix: handling " .. event.type ..  " with " .. tostring(handle))
         handle(bot, event)
      else
         bot:debug("matrix: no handler for " .. event.type)
      end
   end

   return json.encode({})
end

local function handle_muc_message(bot, event)
   -- TODO: XMPP-MUC -> Matrix
end

return function (bot)
   bot:add_plugin("httpevent")
   bot:add_plugin("keystore")

   bot:hook("http/put/transactions/*", function (event)
      return handle_matrix_transactions(bot, event.request, event.response)
   end)

   bot:hook("groupchat/joined", function (room)
      room:hook("message", function (event)
         return handle_muc_message(bot, event)
      end)
   end)
end
