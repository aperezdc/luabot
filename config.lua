
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

plugin "httpevent" {
   -- Exports functionality over HTTP using a built-in web server. This
   -- is used by a few plugins to provide additional functionality. If
   -- a port is not configured the web server won't be available.
   port = 8888;
   -- host = "localhost";
}

plugin "webhook" {
   -- Allows incoming messages by exposing a /webhook endpoint. The hook
   -- accepts JSON formatted messages like the following:
   --
   --   { "mucs": [...],  "jids": [...], "text": "Message" }
   --
   -- See the plugin/webhook.lua file header for details. The client needs to
   -- send a X-WebHook-Signature header containing the HMAC-SHA1 of the JSON
   -- body POSTted to the endpoint via HTTP:
   --
   --   X-WebHook-Signature: sha1=<hexstring>
   --
   secret = "random-token";
}

plugin "urltitles" {
	-- A lists of Lua patterns can be given to filter which URLs are
	-- expanded and which ones are not. This is mostly used in a
	-- per-room basis (see below):
	--
	-- include = {};
	-- exclude = {};
}
plugin "keystore" {
	backend = "filesystem";
	path = "./keystore";

	-- This uses the LMDB backend (requires building lightningmdb)
	--backend = "lmdb";
	--path = "./keystore.db";
}
plugin "meeting" {
	--
	-- Template for log file names. The template may contain slashes, and
	-- directories will be created as needed. The following values are
	-- available for expansion:
	--
	--    %{name}   Name of the MUC room.
	--    %{jid}    Full JID of the MUC room.
	--    %{HH}     Hour, range 00 to 23
	--    %{MM}     Minutes, range 00 to 59
	--    %{SS}     Seconds, range 00 to 59
	--    %{YYYY}   Year, as four digits
	--    %{mm}     Month, range 01 to 12
	--    %{DD}     Day, range 01 to 31
	--    %{time}   ISO-8601 timestamp
	--
	logname = "%{name}/%{YYYY}/%{time}";
	logdir  = "./meeting-logs/";
	logurl  = "https://domain.com/meetings/";
}

plugin "redmine" {
	-- Uses the Redmine REST API to obtain information about issues.
	url = "https://redmine.mycompany.com";

	-- Optionally, the plugin supports HTTP authentication to access the API.
	--http_username = "botuser";
	--http_password = "botpass";

	-- Alternatively, you may prefer to generate and use an API token.
	--api_token = "token";
}

plugin "trac" {
   -- Uses the Trac JSON-RPC API to obtain information about issues.
   url = "http://trac.mycompany.com/myproject";

   -- Optionally, the plugin supports HTTP authentication to access the API.
   --http_username = "botuser";
   --http_password = "botpass";

   -- Defines which JIDs are allowed to perform actions which modify data in
   -- Trac. Of course, the credentials used by the bot to access Trac also
   -- need to have permission to perform the actions.
   permissions = {
      create_ticket = {
         "*@domain.com/*";
      };
      edit_ticket = {
         "admin@domain.com/*";
         "john@doe.org/*";
      };
   };
}

-- Receives notifications from GitHub repositories using a webhook.
-- This needs the "httpevent" plugin above to be configured. See below
-- for an example on how to specify the repository and secret key.
plugin "github" {}

-- Receives notifications from Travis-CI builds using a webhook. This needs
-- the "httpevent" plugin above configured. See below for an example on how to
-- specify the user token. More info:
-- https://docs.travis-ci.com/user/notifications#Webhook-notification
plugin "travis" {}

-- These two make use of the "shortcuts" plugin, which is disabled by
-- default, and is usually enabled in a per-room basis (see below).
plugin "dsa" {}
plugin "cve" {}

-- Tell the bot to join a room, and specify per-room settings
room "devel@conference.domain.com" {
	-- Configure "urltitles" plugin in a per-room basis
	urltitles = {
		include = {
			"^https?://bugs%.myproject%.org/",
			"^https?://bugs%.myotherproject%.org/",
		};
	};
}
room "coffee@conference.domain.com" {
	nick = "beans";

	-- Expand CVE and DSA shortcuts.
	shortcuts = {
		cve = true;
		dsa = true;
	};
	quip = {
		per_room = true;
	};
}
room "luabot-dev@conference.domain.com" {
   github = {
      -- Enables the webhook receiver. The bot will listen over HTTP in the
      -- port specified for the "httpevent" plugin. The URL for the webhook
      -- contains the name of the repository, prefixed with "github/". For
      -- this example, the URL to configure in GitHub would be:
      --
      --   http://luabothost:8888/github/aperezdc/luabot
      --
      webhook = {
         repo = "aperezdc/luabot";
         secret = "this is super secret";
      };
   };

   travis = {
      -- Enables the webhook receiver. The URL for the webook is the JID of the
      -- room, prefixed with "travis/". For this rxample, the URL to configure
      -- in Travis would be:
      --
      --   http://luabothost:8888/travis/luabot-dev@conference.domain.com
      --
      token = "super secret token";
   };
}
