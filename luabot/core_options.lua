--
-- core_options.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local option = require "luabot.config" .option
local jid_split = require "util.jid" .split

return function (config_manager)
   config_manager
      - option.jid      { "jid", default = "" }
      - option.secret   { "password", default = "" }
      - option.hostname { "host", nullable = true }
      - option.uint     { "port", nullable = true }
      - option.jidlist  { "rooms", default = {} }
      - option.string   { "nick", default = function (config)
         return (jid_split(config.jid()))
      end }
end

