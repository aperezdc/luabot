--
-- config_spec.lua
-- Copyright (C) 2016 Adrian Perez <aperez@igalia.com>
--
-- Distributed under terms of the MIT license.
--

local config = require "luabot.config"

describe("config.option_path", function ()
   it("can be instantiated with valid path strings", function ()
      for _, path_string in ipairs { "a", "a.b", "a.b.c_d", "a1" } do
         assert.message(string.format("input: %q", path_string))
            .not_has_error(function ()
               config.option_path(path_string)
            end)
      end
   end)

   it("can be instantiated using tables", function ()
      for _, path_table in ipairs {
         { "a" }, { "a", "b" }, { "a", "b", "c_d" }
      } do
         assert.message("input: " .. table.concat(path_table, ", "))
            .not_has_error(function ()
               config.option_path(path_table)
            end)
      end
   end)

   it("errors on invalid path strings", function ()
      for _, path_string in ipairs {
         "",       -- empty string
         "_a",     -- leading underscore
         "a._b",   -- leading underscore in a component
         "a/b",    -- invalid component separator
         "1abc",   -- leading number
         "a b c",  -- spaces
      } do
         assert.message(string.format("input: %q", path_string))
            .has_error(function ()
               config.option_path(path_string)
            end)
      end
   end)

   it("errors on invalid path tables", function ()
      for _, path_table in ipairs {
         { },           -- no components
         { "" },        -- empty component
         { "a", "" },   -- ditto
         { "", "a" },   -- ditto
         { " foo"  },   -- space in component
         { "a", "." },  -- period in component
      } do
         assert.message("input: " .. table.concat(path_table, ", "))
            .has_error(function ()
               config.option_path(path_table)
            end)
      end
   end)

   it("properly converts with tostring()", function ()
      local items = {
         ["a.b.c.d"] = {
            config.option_path { "a", "b", "c", "d" },
            config.option_path "a.b.c.d",
         },
         ["foobar"] = {
            config.option_path { "foobar" },
            config.option_path "foobar",
         },
         ["a_b.c_d"] = {
            config.option_path { "a_b", "c_d" },
            config.option_path "a_b.c_d",
         },
      }
      for expected, option_paths in pairs(items) do
         for _, option_path in ipairs(option_paths) do
            assert.message("path: " .. table.concat(option_path, ", "))
               .equal(expected, tostring(option_path))
         end
      end
   end)

   it("can be compared", function ()
      assert.equal(config.option_path "a.b.c.d", config.option_path "a.b.c.d")
   end)

   describe(".child()", function ()
      it("creates child paths", function ()
         local base_path = config.option_path "base.path"
         local child_path = base_path:child "child"
         assert.not_same(base_path, child_path)
         assert.equal(config.option_path "base.path.child", child_path)
      end)
      it("can be chained", function ()
         local base_path = config.option_path "base.path"
         local child_path = base_path:child "foo" :child "bar"
         assert.not_same(base_path, child_path)
         assert.equal(config.option_path "base.path.foo.bar", child_path)
      end)
   end)
end)

describe("config.option", function ()
   it("can have a default value", function ()

   end)
end)
