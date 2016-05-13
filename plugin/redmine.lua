#! /usr/bin/env lua
--
-- redmine.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local urlfetch = require "util.urlfetch"
local strutil  = require "util.strutil"
local json     = require "util.json"

local issue_id_pattern = "%#([%d]+)"
local issue_status_format = "%s #%d - %s (%s)"

local function handle_message_issue_ids(bot, event)
	if not event.body then
		return
	end

	local redmine_url = event:config("redmine", "url")
	if not redmine_url then
		bot:warn("redmine: Base URL was not configured")
		return
	end

	local http_options = nil
	local api_token = event:config("redmine", "api_token")
	if api_token then
		http_options = { username = api_token, password = "-" }
	else
		local u = event:config("redmine", "http_username")
		local p = event:config("redmine", "http_password")
		if u and p then
			http_options = { username = u, password = p }
		end
	end

	redmine_url = redmine_url .. "/"  -- Ensure that the URL ends in a slash
	bot:debug("redmine: url=" .. redmine_url)

	local url_pattern = strutil.escape_pattern(redmine_url .. "issues/") .. "([%d]+)"
	bot:debug("redmine: url pattern=" .. url_pattern)

	local handle_issue = function (issue_id, add_url)
		bot:debug("redmine: issue id=" .. issue_id)
		local json_url = redmine_url .. "issues/" .. issue_id .. ".json"
		urlfetch(json_url, http_options, function (data, code)
			if code ~= 200 then
				bot:warn("redmine: HTTP code=" .. code .. " for " .. json_url)
				return
			end

			local issue = json.decode(data)
			issue = issue and issue.issue

			if not issue then
				bot:warn("redmine: no issue for id=" .. issue_id)
				return
			end

			if add_url then
				event:post(redmine_url .. "issues/" .. issue.id)
			end
			event:post(issue_status_format:format(issue.tracker.name,
			                                      issue.id,
			                                      issue.subject,
				                                   issue.status.name))
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

return function (bot)
	local function handle_message(event)
		return handle_message_issue_ids(bot, event)
	end
	bot:hook("message", handle_message)
	bot:hook("groupchat/joined", function(room)
		room:hook("message", handle_message)
	end)
end
