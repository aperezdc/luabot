#! /usr/bin/env lua
--
-- urltitles.lua
-- Copyright (C) 2015 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local html_title = require "util.html" .extract_title;
local urlfetch = require "util.urlfetch"

local default_max_cache_time = 3 * 60 * 60  -- Three hours.
local default_cache_recheck_time = 3 * 60   -- Three minutes.
local default_max_fetch_size = 1024 * 1024  -- One megabyte.

local weekdays = {
   "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
}
local months = {
   "Jan", "Feb", "Mar", "Apr",
   "May", "Jun", "Jul", "Aug",
   "Sep", "Oct", "Nov", "Dec",
}

local http_date_fmt = "%s, %d %s %d %02d:%02s:%02d GMT"
local function http_date(t)
   local t = os.date("!*t", t)
   return http_date_fmt:format(weekdays[t.wday],
                               t.day,
                               months[t.month],
                               t.year,
                               t.hour,
                               t.min,
                               t.sec)
end

local mime_type_pattern = "^%s*([%w%-%.]+/[%w%-%.]+).*$"
local supported_mime_types = {
   ["text/html"] = true;
}
local allow_missing_length_mime_types = {
   ["text/html"] = true;
}

local function identity(x) return x end

local function iterate_patterns(...)
   local pattern_tables = { ... }
   return coroutine.wrap(function ()
      for _, patterns in ipairs(pattern_tables) do
         if patterns ~= nil then
            for k, v in pairs(patterns) do
               if type(k) == "number" then
                  coroutine.yield(v, identity)
               else
                  coroutine.yield(k, v)
               end
            end
         end
      end
   end)
end

local function match_url(url, include, exclude)
   local has_include_patterns = false
   for pattern, postprocess in include do
      has_include_patterns = true
      if url:match(pattern) then
         return true, postprocess
      end
   end

   for pattern, _ in exclude do
      if url:match(pattern) then
         return false, nil
      end
   end

   return not has_include_patterns, identity
end


local function handle_urltitles(bot, cache, event)
   local url = event.body and event.body:match("https?://%S+")
   if url then
      local include_patterns, exclude_patterns
      local room_config = event:room_config("urltitles")

      if room_config then
         include_patterns = iterate_patterns(room_config.include,
         bot.config.plugin.urltitles.include)
         exclude_patterns = iterate_patterns(room_config.exclude,
         bot.config.plugin.urltitles.exclude)
      else
         include_patterns = iterate_patterns(bot.config.plugin.urltitles.include)
         exclude_patterns = iterate_patterns(bot.config.plugin.urltitles.exclude)
      end

      local should_expand, postprocess = match_url(url, include_patterns, exclude_patterns)
      if not should_expand then
         bot:debug("urltitles: URL skipped: " .. url)
         return
      end

      local max_cache_time = tonumber(bot:get_config("urltitles",
            "max_cache_time", default_max_cache_time))
      local cache_recheck_time = tonumber(bot:get_config("urltitles",
            "cache_recheck_time", default_cache_recheck_time))

      local now = os.time()
      local cached = cache:get(url)

      local last_fetch_time = 0
      if cached then
         local elapsed = now - cached.time
         last_fetch_time = cached.time
         if elapsed > max_cache_time then
            bot:debug("urltitles: cache expired: %s", url)
            cache:set(url, nil)  -- Remove from cache.
            last_fetch_time, cached = 0, nil
         elseif cached.fetch_error then
            bot:debug("urltitles: error in cache: %s: %s", tostring(cached.fetch_error), url)
            return
         elseif elapsed < cache_recheck_time then
            bot:debug("urltitles: cached: %s", url)
            event:post(cached.info)
            return
         end
      end

      local max_fetch_size = tonumber(bot:get_config("urltitles",
            "max_fetch_size", default_max_fetch_size, event.room_jid))

      local http_options = {
         method = "HEAD",
         headers = {
            ["If-Modified-Since"] = http_date(last_fetch_time),
            ["Range"] = "0-" .. max_fetch_size,
         },
      }
      -- Make a HEAD request first.
      urlfetch(url, http_options, function (data, code, response)
         -- Valid cached info.
         if last_fetch_time > 0 and code == 304 then
            bot:debug("urltitles: not modified: HEAD %s", url)
            cached.time = now  -- Update last fetch time.
            event:post(cached.info)
            return
         end

         if code ~= 200 then
            bot:warn("urltitles: HTTP code %d: %s", code, url)
            cache:set(url, { fetch_error = code, time = now })
            return
         end

         local content_type = response.headers["content-type"]
         if not content_type then
            bot:warn("urltitles: no Content-Type in HEAD %s", url)
            cache:set(url, { fetch_error = "No Content-Type in HEAD", time = now })
            return
         end
         content_type = content_type:match(mime_type_pattern)
         if not supported_mime_types[content_type] then
            bot:warn("urltitles: unsupported MIME type %s: %s", content_type, url)
            cache:set(url, { fetch_error = "Unsupported Content-Type", time = now })
            return
         end

         local content_length = response.headers["content-length"]
         if content_length then
            if tonumber(content_length) > max_fetch_size then
               bot:debug("urltitles: Content-Length is %d (max %d): %s",
               content_length, max_fetch_size, url)
               cache:set(url, { fetch_error = "Content-Length too big", time = now })
               return
            end
         elseif not allow_missing_length_mime_types[content_type] then
            bot:warn("urltitles: no Content-Length in HEAD is large: %s (%s)",
                  url, content_type)
            cache:set(url, { fetch_error = "No Content-Length in HEAD", time = now })
            return
         end

         -- Passed the sanity checks: do the actual GET.
         http_options.method = "GET"

         urlfetch(url, http_options, function (data, code)
            if last_fetch_time > 0 and code == 304 then
               bot:debug("urltitles: not modified: GET %s", url)
               cached.time = now  -- Update last fetch time.
               event:post(cached.info)
            elseif code ~= 200 then
               bot:warn("urltitles: HTTP code %d: %s", code, url)
               cache:set(url, { fetch_error = code, time = now })
            else
               local title = html_title(data)
               if title then
                  title = postprocess(title)
                  if type(title) == "string" and #title > 0 then
                     cached = { info = title, time = now }
                     cache:set(url, cached)
                     event:post(cached.info)
                  else
                     cache:set(url, { fetch_error = "empty title", time = now })
                  end
               else
                  cache:set(url, { fetch_error = "cannot extract title", time = now })
               end
            end
         end)
      end)
   end
end

local dummy_cache = {
   set = function (self, k, v) return true end;
   get = function (self, k) return nil end;
   count = function (self) return 0 end;
   items = function (self) end;
}

local function make_cache(size)
   if size == 0 then
      return dummy_cache
   else
      return require "util.cache" .new(size)
   end
end

return function (bot)
   local cache_size = tonumber(bot:get_config("urltitles", "cache_size", 500))
   local cache = make_cache(cache_size)
   local function handle_message(event)
      handle_urltitles(bot, cache, event)
   end
   bot:hook("message", handle_message)
   bot:hook("groupchat/joined", function (room)
      room:hook("message", handle_message)
   end)
end
