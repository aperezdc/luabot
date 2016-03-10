#! /usr/bin/env lua
--
-- urlfetch.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local http_request = require("net.http").request
local url          = require("socket.url")

local function urlfetch(u, options, callback)
	if options and options.username and options.password then
		local parsed = url.parse(u)
		parsed.user = options.username
		parsed.password = options.password
		parsed.userinfo = options.username .. ":" .. options.password
		parsed.authority = parsed.userinfo .. "@" .. parsed.authority
		u = url.absolute(parsed)
	end

	http_request(u, options, function (data, code, request)
		if (code == 301 or code == 302 or code == 307 or code == 308) and
			request.headers.location
		then
			urlfetch(request.headers.location, options, callback)
		else
			callback(data, code, request, u)
		end
	end)
end

return urlfetch
