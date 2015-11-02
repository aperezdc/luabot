#! /usr/bin/env lua
--
-- dsa.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local html_title = require("util.html").extract_title
local urlfetch = require("util.urlfetch")

local base_url = "https://www.debian.org/security/dsa-%s"

local function handle_dsa(shortcut)
	local url = base_url:format(shortcut.param)
	urlfetch(url, nil, function (data, code, _, url)
		if code ~= 200 then return end

		local title = html_title(data)
		if title then
			shortcut:post(url .. " - " .. title:sub(35, -1))
		else
			shortcut:post(url)
		end
	end)
	return true
end

return function (bot)
	bot:add_plugin("shortcuts")
	bot:hook("shortcut/dsa", handle_dsa)
end
