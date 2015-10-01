
-- Connection settings. In most cases "server" and "port" can be omitted,
-- and in that case a DNS query for SRV records is used.
jid      = "user@domain.com"
password = "some-password"
host     = "jabber.domain.com"
port     = 5223

-- Logging: warnings and errors are always displayed by default.
debug_log = true   -- Display of debug and informational messages.
color_log = true   -- Use ANSI escapes to color logging output.
raw_log   = false  -- Display raw XML input/output traffic.

-- Default nick name used by the bot when connecting to MUC rooms. This
-- can be overriden using per-room settings (see below for an example)
nick = "luabot"

-- Load plugins, and specify their configurations. Note that the "muc"
-- plugin is always loaded and dos not need to be specified here.
plugin "invite" {}
plugin "urltitles" {}

-- Tell the bot to join a room, and specify per-room settings
room "devel@conference.domain.com" {}
room "coffee@conference.domain.com" {
	nick = "beans";
}
