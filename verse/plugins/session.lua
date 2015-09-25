local verse = require "verse";

local xmlns_session = "urn:ietf:params:xml:ns:xmpp-session";

function verse.plugins.session(stream)
	
	local function handle_features(features)
		local session_feature = features:get_child("session", xmlns_session);
		if session_feature and not session_feature:get_child("optional") then
			local function handle_binding(jid)
				stream:debug("Establishing Session...");
				stream:send_iq(verse.iq({ type = "set" }):tag("session", {xmlns=xmlns_session}),
					function (reply)
						if reply.attr.type == "result" then
							stream:event("session-success");
						elseif reply.attr.type == "error" then
							local err = reply:child_with_name("error");
							local type, condition, text = reply:get_error();
							stream:event("session-failure", { error = condition, text = text, type = type });
						end
					end);
				return true;
			end
			stream:hook("bind-success", handle_binding);
		end
	end
	stream:hook("stream-features", handle_features);
	
	return true;
end
