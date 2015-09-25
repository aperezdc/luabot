local verse = require "verse";

local xmlns_tls = "urn:ietf:params:xml:ns:xmpp-tls";

function verse.plugins.tls(stream)
	local function handle_features(features_stanza)
		if stream.authenticated then return; end
		if features_stanza:get_child("starttls", xmlns_tls) and stream.conn.starttls then
			stream:debug("Negotiating TLS...");
			stream:send(verse.stanza("starttls", { xmlns = xmlns_tls }));
			return true;
		elseif not stream.conn.starttls and not stream.secure then
			stream:warn("SSL libary (LuaSec) not loaded, so TLS not available");
		elseif not stream.secure then
			stream:debug("Server doesn't offer TLS :(");
		end
	end
	local function handle_tls(tls_status)
		if tls_status.name == "proceed" then
			stream:debug("Server says proceed, handshake starting...");
			stream.conn:starttls({mode="client", protocol="sslv23", options="no_sslv2"}, true);
		end
	end
	local function handle_status(new_status)
		if new_status == "ssl-handshake-complete" then
			stream.secure = true;
			stream:debug("Re-opening stream...");
			stream:reopen();
		end
	end
	stream:hook("stream-features", handle_features, 400);
	stream:hook("stream/"..xmlns_tls, handle_tls);
	stream:hook("status", handle_status, 400);
	
	return true;
end
