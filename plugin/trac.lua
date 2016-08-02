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


local function jsonrpc(bot, event, method, params, completed)
   local trac_url = event:config("trac", "url")
   if not trac_url then
      bot:warn("trac: Base URL was not configured")
      return
   end

   trac_url = trac_url .. "/"  -- Ensure that the URL ends in a slash.
   local jsonrpc_url = trac_url .. "login/jsonrpc"
   bot:debug("trac: URL %s, JSON-RPC %s", trac_url, jsonrpc_url)

   local request_id = new_request_id()
   local http_options = {
      headers = {
         ["Content-Type"] = "application/json",
      },
      username = event:config("trac", "http_username"),
      password = event:config("trac", "http_password"),
      body = json.encode {
         id = request_id,
         method = tostring(method),
         params = type(params) == "table" and params or { params },
      }
   }

   urlfetch(jsonrpc_url, http_options, function (data, code)
      if code ~= 200 then
         bot:warn("trac: HTTP error %d: %s", code, data)
         return
      end
      local response = json.decode(data)
      if not response then
         bot:warn("trac: Cannot decode JSON: %q", data)
         return
      end
      if response.error ~= json.null then
         bot:warn("trac: %s error: %s (%d)", response.error.name,
                  response.error.message, response.error.code)
         return
      end
      if response.id ~= request_id then
         bot:warn("trac: JSON-RPC request id=%d, expected=%d", response.id, request_id)
         return
      end
      completed(response.result)
   end)
end


local issue_status_format = "#%d - %s (%s @%s) [P: %s, S: %s]"

local function ticket_info(bot, event, ticket_id, show_url)
   bot:debug("trac: ticket id=%s", ticket_id)
   jsonrpc(bot, event, "ticket.get", ticket_id, function (result)
      if show_url then
         local trac_url = event:config("trac", "url")
         if trac_url then
            event:post(trac_url .. "/ticket/" .. result[1])
         end
      end
      event:post(issue_status_format:format(result[1],
                                            result[4].summary,
                                            result[4].status,
                                            result[4].owner,
                                            result[4].priority,
                                            result[4].severity))
   end)
end


local issue_id_pattern = "%#(%d+)"

local function handle_message_issue_ids(bot, event)
   if not event.body then
      return
   end

   local trac_url = event:config("trac", "url")
   if not trac_url then
      bot:warn("trac: Base URL was not configured")
      return
   end

   local url_pattern = strutil.escape_pattern(trac_url .. "/ticket/") .. "(%d+)"
   bot:debug("trac: url pattern %q", url_pattern)

   -- Try to match issue URLs
   for issue_id in event.body:gmatch(url_pattern) do
      ticket_info(bot, event, issue_id, false)
   end
   -- And now for plain #NNNN identifiers
   for issue_id in event.body:gmatch(issue_id_pattern) do
      ticket_info(bot, event, issue_id, true)
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

   local params = {
      event.param,              -- Summary
      event.param,              -- Description
      (jid.split(sender_jid)),  -- Reporter
   }
   jsonrpc(bot, event, "ticket.create", params, function (result)
      event:reply("#" .. result .. " created by " .. event.sender.nick)
      ticket_info(bot, event, result, true)
   end)
   return true
end


local assign_ticket_param_pattern = "^%s*%#?(%d+)%s+([%a%_%.%-]+)%s*$"

local function assign_ticket(bot, event)
   local trac_url = event:config("trac", "url")
   if not trac_url then
      bot:warn("trac: Base URL was not configured")
      return
   end

   local permissions = event:config("trac", "permissions", {})
   local sender_jid = event.sender.real_jid or event.sender.jid
   if not has_permission(bot, sender_jid, permissions.edit_ticket) then
      return event:reply("You are not allowed to modify tickets")
   end
   if not event.param then
      return event:reply("Usage: trac assign <id> <owner>")
   end
   local ticket_id, owner = event.param:match(assign_ticket_param_pattern)
   if not (ticket_id and owner) then
      return event:reply("Usage: trac assign <id> <owner>")
   end

   local params = {
      tonumber(ticket_id),
      "",                  -- Comment.
      { owner = owner },   -- Attributes.
      true,                -- Notify.
   }
   jsonrpc(bot, event, "ticket.update", params, function (result)
      event:post(trac_url .. "/ticket/" .. result[1])
      event:post(issue_status_format:format(result[1],
                                            result[4].summary,
                                            result[4].status,
                                            result[4].owner,
                                            result[4].priority,
                                            result[4].severity))
   end)
end


return function (bot)
   bot:add_plugin("commandevent")

   local function get_ticket_info(command)
      bot:debug("trac: get: %s", command.param)
      if command.param and #command.param > 0 then
         local ticket_id
         if command.param:sub(1, 1) == "#" then
            ticket_id = tonumber(command.param:sub(2))
         else
            ticket_id = tonumber(command.param)
         end
         if ticket_id then
            ticket_info(bot, command, ticket_id, true)
         else
            event:reply("Invalid ticket ID: '" .. command.param .. "'")
         end
      else
         event:reply("No ticket ID specified")
      end
      return true
   end

   local function add_ticket(command)
      return create_ticket(bot, command)
   end

   bot:hook("command/trac", bot.plugin.commandevent.dispatch {
      assign = function (command) return assign_ticket(bot, command) end;
      add = add_ticket;
      create = add_ticket;
      ticket = get_ticket_info;
      issue = get_ticket_info;
      get = get_ticket_info;
      _ = get_ticket_info;
   })

   local function handle_message(event)
      return handle_message_issue_ids(bot, event)
   end
   bot:hook("message", handle_message)
   bot:hook("groupchat/joined", function (room)
      room:hook("message", handle_message)
   end)
end
