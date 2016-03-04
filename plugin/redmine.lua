#! /usr/bin/env lua
--
-- redmine.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local urlfetch = require "util.urlfetch"
local json     = require "util.json"
local url      = require "socket.url"


local regex_magic_chars = "([%^%$%(%)%%%.%[%]%*%+%-%?])"
local function escape_regex_chars (s)
	return (s:gsub(regex_magic_chars, "%%%1"))
end

local issue_id_pattern = "%#([%d]+)"
local issue_status_format = "%s #%d - %s (%s)"


local function url_add_auth(base_url, api_token, username, password)
	if api_token then
		username = api_token
		password = "-"
	end
	if not (username and password) then
		return
	end
	base_url.user = username
	base_url.password = password
	base_url.userinfo = username .. ":" .. password
	base_url.authority = base_url.userinfo .. "@" .. base_url.authority
end


local function handle_message_issue_ids(bot, event)
	if not event.body then
		return
	end

	local redmine_url = event:config("redmine", "url")
	if not redmine_url then
		bot:warn("redmine: Base URL was not configured")
		return
	end

	local api_token     = event:config("redmine", "api_token")
	local http_username = event:config("redmine", "http_username")
	local http_password = event:config("redmine", "http_password")

	redmine_url = redmine_url .. "/"  -- Ensure that the URL ends in a slash
	bot:debug("redmine: url=" .. redmine_url)

	local base_url = url.parse(redmine_url)
	local url_pattern = escape_regex_chars(url.absolute(base_url, "issues/")) .. "([%d]+)"
	bot:debug("redmine: url pattern=" .. url_pattern)

	url_add_auth(base_url, api_token, http_username, http_password)

	-- Try to match issue URLs
	for issue_id in event.body:gmatch(url_pattern) do
		bot:debug("redmine: issue id=" .. issue_id .. " [url]")
		local json_url = url.absolute(base_url, "issues/" .. issue_id .. ".json")
		urlfetch(json_url, nil, function (data, code)
			if code == 403 then
				bot:debug("redmine: HTTP code=" .. code .. " [forbidden] for " .. json_url)
				return
			end
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

			event:post(issue_status_format:format(issue.tracker.name,
			                                      issue.id,
			                                      issue.subject,
				                                   issue.status.name))
		end)
	end

	-- And now for plain #NNNN identifiers
	for issue_id in event.body:gmatch(issue_id_pattern) do
		bot:debug("redmine: issue id=" .. issue_id)
		local json_url = url.absolute(base_url, "issues/" .. issue_id .. ".json")
		urlfetch(json_url, nil, function (data, code)
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

			event:post(url.absolute(url.parse(redmine_url), "issues/" .. issue.id))
			event:post(issue_status_format:format(issue.tracker.name,
			                                      issue.id,
			                                      issue.subject,
				                                   issue.status.name))
		end)
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
