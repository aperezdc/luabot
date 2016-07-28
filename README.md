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
5. *(Optional)* Depending on the enabled options, you may need to install
   the optional dependencies.
6. Start the bot:

```sh
lua bot.lua config.lua
```


Optional Dependencies
---------------------

* [lightningmdb](https://github.com/shmul/lightningmdb) can be used as a
  backend for the `keystore` plugin. It is [available in
  LuaRocks](https://luarocks.org/modules/shmul/lightningmdb).


Licensing
---------

Please see the [LICENSE.md](LICENSE.md) file.
