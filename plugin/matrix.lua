#! /usr/bin/env lua
--
-- matrix.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local urlescape = require "socket.url" .escape
local urlfetch  = require "util.urlfetch"
local stanza    = require "util.stanza"
local json      = require "util.json"
local jid       = require "util.jid"


local conf_options = {
   { "homeserver_url", nil,        false },
   { "homeserver",     nil,        true  },
   { "as_token",       nil,        true  },
   { "hs_token",       nil,        true  },
   { "room_prefix",    "#jabber_", false },
   { "user_prefix",    "@jabber_", false },
}

local MatrixBridge = {
   NS_ROOM_ALIASES   = "plugin.matrix.room_aliases.",
   NS_ROOM_BY_ALIAS  = "plugin.matrix.room_by_alias.",
   NS_TRANSACTION_ID = "plugin.matrix.transaction_id.",
}
setmetatable(MatrixBridge, { __call = function (self, bot, ready)
   local bridge = setmetatable({ _kvstore = bot.plugin.keystore }, { __index = MatrixBridge })
   for _, conf_option_spec in ipairs(conf_options) do
      local name, default, required = unpack(conf_option_spec)
      bridge[name] = bot:get_config("matrix", name, default)
      if required and bridge[name] == nil then
         local msg = string.format("required option '%s' is undefined", name)
         bot:error("matrix: " .. msg)
         error(msg)
      end
   end
   if bridge.homeserver_url then
      ready(bridge)
   else
      local adns = require "net.adns"
      adns.lookup(function (answer)
         if not answer then
            bot:error("matrix: could not resolve _matrix._tcp.%s", bridge.homeserver)
            require "os" .exit(1)
         end
         local sorted = {}
         for _, record in ipairs(answer) do
            sorted[#sorted + 1] = record.srv
         end
         table.sort(sorted, function (a, b)
            return a.priority < b.priority or (a.priority == b.priority and a.weight > b.weight)
         end)
         bridge.homeserver_url = "https://" .. sorted[1].target .. ":" .. sorted[1].port
         bot:info("matrix: resolved _matrix._tcp.%s -> %s", bridge.homeserver, bridge.homeserver_url)
         ready(bridge)
      end, "_matrix._tcp." .. bridge.homeserver, "SRV", "IN")
   end
   return 
end })

function MatrixBridge:set_room_aliases(room_id, aliases)
   -- Delete old aliases to room ID mappings.
   for _, alias in ipairs(self:get_room_aliases(room_id) or {}) do
      self._kvstore:del(self.NS_ROOM_BY_ALIAS .. alias)
   end
   -- Store new mapping of aliases to room ID.
   for _, alias in ipairs(aliases) do
      self._kvstore:set(self.NS_ROOM_BY_ALIAS .. alias, room_id)
   end
   -- Store aliases.
   self._kvstore:set(self.NS_ROOM_ALIASES .. room_id, aliases)
end

function MatrixBridge:get_room_aliases(room_id)
   return self._kvstore:get(self.NS_ROOM_ALIASES .. room_id)
end

function MatrixBridge:get_room_id_by_alias(alias)
   return self._kvstore:get(self.NS_ROOM_BY_ALIAS .. alias)
end

function MatrixBridge:jid_to_room_alias(room_jid)
   return self.room_prefix .. jid.bare(room_jid) .. ":" .. self.homeserver
end

function MatrixBridge:jid_to_room_id(room_jid)
   return self:get_room_id_by_alias(self:jid_to_room_alias(room_jid))
end

function MatrixBridge:jid_to_user_id(user_jid)
   return self.user_prefix .. jid.bare(user_jid) .. ":" .. self.homeserver
end

function MatrixBridge:get_transaction_id()
   return self._kvstore:get(self.NS_TRANSACTION_ID) or 0
end

function MatrixBridge:set_transaction_id(txn_id)
   self._kvstore:set(self.NS_TRANSACTION_ID, txn_id)
end

function MatrixBridge:increment_transaction_id()
   local txn_id = self:get_transaction_id()
   self:set_transaction_id(txn_id + 1)
   return txn_id
end


local txn_handler = {
   ["m.room.aliases"] = function (bot, bridge, event)
      -- Store the Matrix room ID to aliases mapping
      bot:debug("matrix: save room " .. event.room_id .. " -> " .. table.concat(event.content.aliases, ", "))
      bridge:set_room_aliases(event.room_id, event.content.aliases)
   end,

   ["m.room.message"] = function (bot, bridge, event)
      local room_aliases = bridge:get_room_aliases(event.room_id)
      if not room_aliases then
         bot:warn("matrix: no aliases recorded for room " .. event.room_id)
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
         bot:debug("matrix: message of unsupported type %s", event.content.msgtype)
         return
      end
      bot:debug("matrix: message=\"%q\"", message)
      -- Extract the sender of the message
      local localpart, hs = event.user_id:match("^@([^:]+):(.+)$")
      bot:debug("matrix: message from localpart=%s hs=%s", localpart, hs)

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

local function handle_matrix_transactions(bot, bridge, request, response)
   bot:debug("matrix: payload: " .. request.body)

   local data = json.decode(request.body)
   if not (data and data.events) then
      return 400  -- Bad request
   end

   for _, event in ipairs(data.events) do
      local handle = txn_handler[event.type]
      if handle then
         bot:debug("matrix: handling " .. event.type ..  " with " .. tostring(handle))
         handle(bot, bridge, event)
      else
         bot:debug("matrix: no handler for " .. event.type)
      end
   end

   return json.encode({})
end

local function handle_muc_message(bot, bridge, event)
   -- Get the corresponding Matrix room ID
   local room_id = bridge:jid_to_room_id(event.room_jid)
   bot:debug("matrix: message from %s -> %s", event.room_jid, room_id)
   if not room_id then
      bot:debug("matrix: no Matrix room ID for %s", event.room_jid)
      return
   end
   -- Turn the sender JID into a Matrix user ID
   local user_id = bridge:jid_to_user_id(event.room.occupants[event.nick].real_jid)
   -- PUT /_matrix/client/r0/rooms/{roomId}/send/{eventType}/{txnId}?access_token={token}&user_id={user}
   -- FIXME: Hardcoded API version
   local payload = json.encode { msgtype = "m.text", body = event.body }
   local url = table.concat { bridge.homeserver_url,
      "/_matrix/client/r0/rooms/", room_id,
      "/send/m.room.message/", bridge:increment_transaction_id(),
      "?access_token=", urlescape(bridge.as_token),
      "&user_id=", urlescape(user_id)
   }
   bot:debug("matrix: PUT URL=%s", url)
   bot:debug("matrix: payload=%q", payload)
   -- Do the request to the homeserver
   urlfetch(url, { method = "PUT", body = body }, function (data, code)
      if code ~= 200 then
         bot:warn("matrix: HTTP code=%d for %s, body=%q", code, url, data)
         return
      end
      bot:debug("matrix: HTTP request returned %q", data)
   end)
end

return function (bot)
   bot:add_plugin("httpevent")
   bot:add_plugin("keystore")
   return MatrixBridge(bot, function (bridge)
      bot:hook("http/put/transactions/*", function (event)
         return handle_matrix_transactions(bot, bridge, event.request, event.response)
      end)
      bot:hook("groupchat/joined", function (room)
         room:hook("message", function (event)
            if event.body then
               return handle_muc_message(bot, bridge, event)
            end
         end)
      end)
   end)
end
