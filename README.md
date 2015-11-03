Luabot
======

Lua-based XMPP (Jabber) bot.


Requirements
------------

* [Lua](http://www.lua.org) 5.2, or 5.3
* [LuaSocket](https://github.com/diegonehab/luasocket).
* [LuaFilesystem](https://github.com/keplerproject/luafilesystem).
* [LuaSec](https://github.com/brunoos/luasec/), for TLS/SSL support.
* [LuaExpat](http://matthewwild.co.uk/projects/luaexpat/), for XML parsing.


Installation
------------

1. Install the dependencies. In Debian, this is
   `apt-get install lua5.2 lua-{sec,expat,socket,filesystem} git-core`
2. Clone the Git repository: `git clone git://github.com/aperezdc/luabot`
3. Edit the configuration: `$EDITOR luabot/config.lua`
4. *(Optional)* Depending on the enabled options, you may need to create
   additional directories, e.g. if the `keystore` plugin is enabled, create
   the directory configured for the `path` setting.
5. *(Optional)* Depending on the enabled options, you may need to build
   the optional modules.
6. Start the bot:


Optional Modules
----------------

The `thirdparty/` subdirectory contains Git submodules for optional Lua
modules which can be needed depending on the options enabled in the
configuration file. The following commands will setup them all:

```sh
git submodule init
make -C thirdparty
```

If you only want to build a certain module, you can use instead:

```sh
make -C thirdparty <modulename>
```


Licensing
---------

Please see the [LICENSE.md](LICENSE.md) file.
