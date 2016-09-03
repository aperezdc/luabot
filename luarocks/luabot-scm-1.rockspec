package = "luabot"
version = "scm-1"
source = {
   url = "git://github.com/aperezdc/luabot"
}
description = {
   maintainer = "Adrián Pérez de Castro <aperez@igalia.com>",
   homepage = "https://github.com/aperezdc/luabot",
   summary = "XMPP (Jabber) bot",
   license = "MIT/X11",
}
supported_platforms = {
   "!windows",
   "!cygwin"
}
dependencies = {
   "lua >= 5.2",
   "luasec >= 0.6",
   "luaexpat >= 1.2",
   "luafilesystem >= 1.6",
}
build = {
   type = "builtin",
   modules = {
      ["luabot.net.adns"]                = "net/adns.lua",
      ["luabot.net.dns"]                 = "net/dns.lua",
      ["luabot.net.http"]                = "net/http.lua",
      ["luabot.net.http.codes"]          = "net/http/codes.lua",
      ["luabot.net.http.parser"]         = "net/http/parser.lua",
      ["luabot.net.http.server"]         = "net/http/server.lua",
      ["luabot.net.server"]              = "net/server.lua",
      ["luabot.net.server_select"]       = "net/server_select.lua",

      ["luabot.plugin.commandevent"]     = "plugin/commandevent.lua",
      ["luabot.plugin.cve"]              = "plugin/cve.lua",
      ["luabot.plugin.dsa"]              = "plugin/dsa.lua",
      ["luabot.plugin.facts"]            = "plugin/facts.lua",
      ["luabot.plugin.github"]           = "plugin/github.lua",
      ["luabot.plugin.hello"]            = "plugin/hello.lua",
      ["luabot.plugin.httpevent"]        = "plugin/httpevent.lua",
      ["luabot.plugin.invite"]           = "plugin/invite.lua",
      ["luabot.plugin.keystore"]         = "plugin/keystore.lua",
      ["luabot.plugin.keystore.lmdb"]    = "plugin/keystore/lmdb.lua",
      ["luabot.plugin.meeting"]          = "plugin/meeting.lua",
      ["luabot.plugin.muc"]              = "plugin/muc.lua",
      ["luabot.plugin.quip"]             = "plugin/quip.lua",
      ["luabot.plugin.redmine"]          = "plugin/redmine.lua",
      ["luabot.plugin.shortcuts"]        = "plugin/shortcuts.lua",
      ["luabot.plugin.trac"]             = "plugin/trac.lua",
      ["luabot.plugin.travis"]           = "plugin/travis.lua",
      ["luabot.plugin.urltitles"]        = "plugin/urltitles.lua",
      ["luabot.plugin.webhook"]          = "plugin/webhook.lua",

      ["luabot.util.basexx"]             = "util/basexx.lua",
      ["luabot.util.cache"]              = "util/cache.lua",
      ["luabot.util.encodings"]          = "util/encodings.lua",
      ["luabot.util.events"]             = "util/events.lua",
      ["luabot.util.html"]               = "util/html.lua",
      ["luabot.util.http"]               = "util/http.lua",
      ["luabot.util.indexedbheap"]       = "util/indexedbheap.lua",
      ["luabot.util.ip"]                 = "util/ip.lua",
      ["luabot.util.jid"]                = "util/jid.lua",
      ["luabot.util.json"]               = "util/json.lua",
      ["luabot.util.logger"]             = "util/logger.lua",
      ["luabot.util.sasl.anonymous"]     = "util/sasl/anonymous.lua",
      ["luabot.util.sasl.plain"]         = "util/sasl/plain.lua",
      ["luabot.util.sasl.scram"]         = "util/sasl/scram.lua",
      ["luabot.util.sha1"]               = "util/sha1.lua",
      ["luabot.util.sha2"]               = "util/sha2.lua",
      ["luabot.util.stanza"]             = "util/stanza.lua",
      ["luabot.util.strutil"]            = "util/strutil.lua",
      ["luabot.util.timer"]              = "util/timer.lua",
      ["luabot.util.urlfetch"]           = "util/urlfetch.lua",
      ["luabot.util.xmppstream"]         = "util/xmppstream.lua",

      ["luabot.verse.init"]              = "verse/init.lua",
      ["luabot.verse.client"]            = "verse/client.lua",
      ["luabot.verse.plugins.bind"]      = "verse/plugins/bind.lua",
      ["luabot.verse.plugins.groupchat"] = "verse/plugins/groupchat.lua",
      ["luabot.verse.plugins.keepalive"] = "verse/plugins/keepalive.lua",
      ["luabot.verse.plugins.presence"]  = "verse/plugins/presence.lua",
      ["luabot.verse.plugins.sasl"]      = "verse/plugins/sasl.lua",
      ["luabot.verse.plugins.session"]   = "verse/plugins/session.lua",
      ["luabot.verse.plugins.tls"]       = "verse/plugins/tls.lua",
      ["luabot.verse.plugins.version"]   = "verse/plugins/version.lua",
   },
   install = {
      bin = {
         luabot = "bot.lua"
      }
   }
}
