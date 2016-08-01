--
-- config.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local Set = require "Set"
local json_encode, json_decode, json_null = (function ()
   local json = require "util.json"
   return json.encode, json.decode, json.null
end)()

local setmetatable, type, error, assert = setmetatable, type, error, assert
local tonumber, tostring, ipairs, pcall = tonumber, tostring, ipairs, pcall
local t_insert, t_concat = table.insert, table.concat
local s_match, s_sub, s_upper = string.match, string.sub, string.upper
local s_gmatch, sprintf = string.gmatch, string.format
local print = print

local _ENV = nil

local int_pattern = "^(%-)?(0x)?([%x]+)$"
local function tointeger(str)
   local negative, hex, digits = s_match(str, int_pattern)
   if not digits then
      return nil
   end
   local value
   if hex then
      value = tonumber(digits, 16)
   elseif s_sub(digits, 1, 1) == "0" then
      value = tonumber(digits, 8)
   else
      value = tonumber(digits, 10)
   end
   if negative then
      value = -value
   end
   return value
end

local function identity(x) return x end

local option_types = {}

local function define_option_type(name, of_string, to_string)
   name = s_upper(name)
   if option_types[name] then
      error(sprintf("Option type %s already defined", name))
   end
   option_types[name] = {
      name = name,
      of_string = of_string,
      to_string = to_string or tostring,
   }
end

local function toformat(format)
   return function (value)
      return sprintf(format, value)
   end
end

local function jidset_of_string(str)
end

local function string_of_jidset(set)
   local n, jids = 0, {}
   for jid, _ in pairs(set) do
      n = n + 1
      jids[n] = jid
   end
   return "<" .. t_concat(jids, " ") .. ">"
end

define_option_type("number", tonumber)
define_option_type("int",    tointeger)
define_option_type("hex",    tointeger, toformat "0x%X")
define_option_type("octal",  tointeger, toformat "0%o")
define_option_type("string", tostring,  toformat "%q")
define_option_type("jidset", jidset_of_string, string_of_jidset)

local path_component_pattern = "^%a[%w_]*$"
local function check_path(path)
   if type(path) == "string" then
      local r = {}
      for component in s_gmatch(path, "[^%.]+") do
         t_insert(r, component)
      end
      path = r
   end
   if type(path) ~= "table" then
      error("option path must be a table or string")
   end
   -- Check that each component is valid.
   local num_components = 0
   for _, component in ipairs(path) do
      if not s_match(component, path_component_pattern) then
         error(sprintf("invalid option path component: %q", component))
      end
      num_components = num_components + 1
   end
   if num_components == 0 then
      error("option path has no components")
   end
   return path
end


local option_path = {}
option_path.__index = option_path

setmetatable(option_path, { __call = function (self, path, copy)
   return setmetatable(check_path(path), self)
end })

local function option_path_copy(path)
   local new_path = setmetatable({}, option_path)
   local n = 0
   for i, component in ipairs(path) do
      new_path[i] = component
      n = n + 1
   end
   return new_path, n
end

function option_path:__tostring()
   return t_concat(self, ".")
end

function option_path:__eq(other)
   if type(other) ~= "table" then
      return false
   end
   for i, value in ipairs(self) do
      if value ~= other[i] then
         return false
      end
   end
   return true
end

function option_path:child(component)
   local new_path, n = option_path_copy(self)
   new_path[n + 1] = component
   return new_path
end

function option_path:parent()
   local new_path, n = option_path_copy(self)
   new_path[n] = nil
   return new_path
end

function option_path:sibling(component)
   local new_path, n = option_path_copy(self)
   new_path[n] = component
   return new_path
end


local option = {}
option.__index = option

setmetatable(option, { __call = function (self, opt)
   local opt_type = opt.type or option_types.STRING
   if not opt.path and opt[1] then
      opt.path, opt[1] = opt[1], nil
   end
   if type(opt_type) == "string" then
      opt_type = s_upper(opt_type)
      if not option_types[opt_type] then
         local type_names = {}
         for name, _ in pairs(option_types) do
            t_insert(type_names)
         end
         error(sprintf("Invalid option type: %q (available: %s)",
                       opt_type, t_concat(type_names, ", ")))
      end
      opt_type = option_types[opt_type]
   end
   local nullable, default = opt.nullable and true or false, opt.default
   if not (nullable or default) then
      error("Non-nullable options must have a default value")
   end
   return setmetatable({
      type      = opt_type,
      default   = default,
      nullable  = nullable,
      per_room  = opt.per_room and true or false,
      path      = option_path(opt.path)
   }, self)
end })

function option:__tostring()
   local items = { s_upper(self.type.name) }
   if self.default then
      t_insert(items, "default=" .. self.type.to_string(self.default))
   end
   if self.per_room then t_insert(items, "PER_ROOM") end
   if self.nullable then t_insert(items, "NULLABLE") end
   return sprintf("option <%s %s>", self.path, t_concat(items, " "))
end


local option_path_builder = {}
option_path_builder.__index = option_path_builder

setmetatable(option_path_builder, { __call = function (self, manager, ...)
   return setmetatable({ manager = manager, ... }, self)
end })

function option_path_builder:__tostring()
   return sprintf("path_builder<%s>", option_path.__tostring(self))
end

function option_path_builder:__index(key)
   t_insert(self, key)
   return self
end

function option_path_builder:__call(context)
end


local manager = {}
manager.__index = manager

setmetatable(manager, { __call = function (self)
   return setmetatable({
      _options = {},
   }, self)
end })

function manager:__sub(option)
   self._options[tostring(option.path)] = option
   return self
end

function manager:__index(key)
   return option_path_builder(self, key)
end


return {
   option_path = option_path,
   option_path_builder = option_path_builder,
   option = option,
   manager = manager,
}
