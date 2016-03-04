#! /usr/bin/env lua
--
-- cve.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local urlfetch = require("util.urlfetch")
local json = require("util.json")

local base_url = "https://cve.circl.lu/cve/CVE-%s"
local api_url = "https://cve.circl.lu/api/cve/CVE-%s"

local function handle_cve(shortcut)
	local url = api_url:format(shortcut.param)
	urlfetch(url, nil, function (data, code, _, url)
		if code ~= 200 or not data or #data == 0 then return end

		data = json.decode(data)
		if not data then return end

		local score = data.cvss and " (Score: " .. data.cvss .. ")" or " (no score)"
		shortcut:post("CVE " .. shortcut.param .. ": " ..
                    data.summary .. score)
		shortcut:post(base_url:format(shortcut.param))
	end)
	return true
end

return function (bot)
	bot:add_plugin("shortcuts")
	bot:hook("shortcut/cve", handle_cve)
end
