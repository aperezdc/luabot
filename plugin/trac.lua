#! /usr/bin/env lua
--
-- trac.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local urlfetch = require "util.urlfetch"
local strutil  = require "util.strutil"
local json     = require "util.json"
local jid      = require "util.jid"


-- Generator for JSON-RPC request identifiers
local request_id_counter = 0
local function new_request_id()
   request_id_counter = request_id_counter + 1
   return request_id_counter
end


local json_get_ticket_template = [[{
   "id"    : %d,
   "method": "ticket.get",
   "params": [%s]
}]]
local function json_request_get_ticket(issue_id)
   local request_id = new_request_id()
   return json_get_ticket_template:format(request_id, issue_id), request_id
end


local function json_request_create_ticket(summary, description, user_jid)
   local request_id = new_request_id()
   return json.encode {
      id = request_id,
      method = "ticket.create",
      params = {
         summary,
         description or summary,
         { reporter = user_jid and (jid.split(user_jid)) }
      }
   }, request_id
end


local issue_id_pattern = "%#(%d+)"
local issue_status_format = "#%d - %s (%s @%s) [P: %s, S: %s]"


local function handle_message_issue_ids(bot, event)
   if not event.body then
      return
   end

   local trac_url = event:config("trac", "url")
   if not trac_url then
      bot:warn("trac: Base URL was not configured")
      return
   end

   local http_options = { headers = { ["Content-Type"] = "application/json" } }
   do
      local u = event:config("trac", "http_username")
      local p = event:config("trac", "http_password")
      if u and p then
         http_options.username, http_options.password = u, p
      end
   end

   trac_url = trac_url .. "/"  -- Ensure that the URL ends in a slash
   local jsonrpc_url = trac_url .. "login/jsonrpc"
   bot:debug("trac url=" .. trac_url .. " jsonrpc=" .. jsonrpc_url)

   local url_pattern = strutil.escape_pattern(trac_url .. "ticket/") .. "(%d+)"
   bot:debug("trac url pattern=" .. url_pattern)

   local handle_issue = function (issue_id, add_url)
      bot:debug("trac: issue id=" .. issue_id)
      local request_id
      http_options.body, request_id = json_request_get_ticket(issue_id)
      urlfetch(jsonrpc_url, http_options, function (data, code)
         if code ~= 200 then
            bot:warn("trac: HTTP error code=" .. code)
            return
         end

         local result = json.decode(data)
         if result.error ~= json.null then
            bot:warn("trac: JSON-RPC error=".. tostring(result.error))
            return
         end
         if result.id ~= request_id then
            bot:warn("trac: JSON-RPC request_id=" .. result.id .. " (expected=" .. request_id .. ")")
            return
         end

         result = result.result
         if add_url then
            event:post(trac_url .. "ticket/" .. result[1])
         end
         event:post(issue_status_format:format(result[1],
                                               result[4].summary,
                                               result[4].status,
                                               result[4].owner,
                                               result[4].priority,
                                               result[4].severity))
      end)
   end

   -- Try to match issue URLs
   for issue_id in event.body:gmatch(url_pattern) do
      handle_issue(issue_id, false)
   end

   -- And now for plain #NNNN identifiers
   for issue_id in event.body:gmatch(issue_id_pattern) do
      handle_issue(issue_id, true)
   end
end


local function has_permission(bot, jid, allowed_patterns)
   if allowed_patterns then
      for _, pattern in ipairs(allowed_patterns) do
         bot:debug("trac: check match(%q, %q)", jid, pattern)
         if strutil.simple_match(jid, pattern) then
            return true
         end
      end
   end
   return false
end


local function create_ticket(bot, event)
   local trac_url = event:config("trac", "url")
   if not trac_url then
      bot:warn("trac: Base URL was not configured")
      return
   end

   local permissions = event:config("trac", "permissions", {})
   local sender_jid = event.sender.real_jid or event.sender.jid
   if not has_permission(bot, sender_jid, permissions.create_ticket) then
      return event:reply("You are not allowed to create tickets")
   end

   if not event.param then
      return event:reply("No description was given")
   end

   local http_options = { headers = { ["Content-Type"] = "application/json" } }
   do
      local u = event:config("trac", "http_username")
      local p = event:config("trac", "http_password")
      if u and p then
         http_options.username, http_options.password = u, p
      end
   end

   trac_url = trac_url .. "/"  -- Ensure that the URL ends in a slash
   local jsonrpc_url = trac_url .. "login/jsonrpc"
   bot:debug("trac: URL %s, JSON-RPC endpoint %s", trac_url, jsonrpc_url)

   local request_id
   http_options.body, request_id = json_request_create_ticket(event.param, nil, sender_jid)
   urlfetch(jsonrpc_url, http_options, function (data, code)
      if code ~= 200 then
         bot:warn("trac: HTTP error code=" .. code)
         return
      end

      local result = json.decode(data)
      if result.error ~= json.null then
         bot:warn("trac: JSON-RPC error=".. tostring(result.error))
         return
      end
      if result.id ~= request_id then
         bot:warn("trac: JSON-RPC request_id=" .. result.id .. " (expected=" .. request_id .. ")")
         return
      end

      result = result.result
      event:post("Issue #" .. result .. " created: " .. trac_url .. "ticket/" .. result)
   end)
   return true
end


return function (bot)
   bot:add_plugin("commandevent")

   bot:hook("command/trac", bot.plugin.commandevent.dispatch {
      add = function (command) return create_ticket(bot, command) end;
   })

   local function handle_message(event)
      return handle_message_issue_ids(bot, event)
   end
   bot:hook("message", handle_message)
   bot:hook("groupchat/joined", function (room)
      room:hook("message", handle_message)
   end)
end
