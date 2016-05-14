#! /usr/bin/env lua
--
-- httpserver.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

return function (bot)
   local port = bot:get_config("httpevent", "port")
   local host = bot:get_config("httpevent", "host", "*")
   if not port then
      bot:debug("httpserver: No port configured, plugin disabled")
      return
   end

   local server = require "net.http.server"
   server.listen_on(port, host)

   -- At least one host is always needed, otherwise the server won't work
   server.add_host(host)
   server.set_default_host(host)

   -- Patch up bot:hook() in order to add HTTP handlers to the server
   -- whenever hooking up to a "http/..." event.
   local old_hook = bot.hook
   function bot:hook(name, ...)
      if #name > 6 and name:sub(1, 5) == "http/" then
         local method, uri = name:sub(6):match("^([^/]+)(.*)$")
         if not (method and uri) then
            bot:error("httpevent: cannot hook '" .. name .. "', both method and URI pattern are needed")
            return
         end
         local http_event_name = method:upper() .. " " .. host .. uri
         server.add_handler(http_event_name, function (...)
            return bot:event(name, ...)
         end)
         bot:debug("httpevent: added HTTP handler '" .. http_event_name .. "'")
      end
      old_hook(bot, name, ...)
   end
end
