#! /usr/bin/env lua
--
-- urlfetch.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local http_request = require("net.http").request

local function urlfetch(url, options, callback)
	http_request(url, options, function (data, code, request)
		if (code == 301 or code == 302 or code == 307 or code == 308) and
			request.headers.location
		then
			urlfetch(request.headers.location, options, callback)
		else
			callback(data, code, request, url)
		end
	end)
end

return urlfetch
