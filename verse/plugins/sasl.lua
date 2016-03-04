local verse = require"verse";
local base64, unbase64 = require "mime".b64, require"mime".unb64;
local xmlns_sasl = "urn:ietf:params:xml:ns:xmpp-sasl";

function verse.plugins.sasl(stream)
	local function handle_features(features_stanza)
		if stream.authenticated then return; end
		stream:debug("Authenticating with SASL...");
		local sasl_mechanisms = features_stanza:get_child("mechanisms", xmlns_sasl);
		if not sasl_mechanisms then return end

		local mechanisms = {};
		local preference = {};

		for mech in sasl_mechanisms:childtags("mechanism") do
			mech = mech:get_text();
			stream:debug("Server offers %s", mech);
			if not mechanisms[mech] then
				local name = mech:match("[^-]+");
				local ok, impl = pcall(require, "util.sasl."..name:lower());
				if ok then
					stream:debug("Loaded SASL %s module", name);
					mechanisms[mech], preference[mech] = impl(stream, mech);
				elseif not tostring(impl):match("not found") then
					stream:debug("Loading failed: %s", tostring(impl));
				end
			end
		end

		local supported = {}; -- by the server
		for mech in pairs(mechanisms) do
			table.insert(supported, mech);
		end
		if not supported[1] then
			stream:event("authentication-failure", { condition = "no-supported-sasl-mechanisms" });
			stream:close();
			return;
		end
		table.sort(supported, function (a, b) return preference[a] > preference[b]; end);
		local mechanism, initial_data = supported[1];
		stream:debug("Selecting %s mechanism...", mechanism);
		stream.sasl_mechanism = coroutine.wrap(mechanisms[mechanism]);
		initial_data = stream:sasl_mechanism(mechanism);
		local auth_stanza = verse.stanza("auth", { xmlns = xmlns_sasl, mechanism = mechanism });
		if initial_data then
			auth_stanza:text(base64(initial_data));
		end
		stream:send(auth_stanza);
		return true;
	end

	local function handle_sasl(sasl_stanza)
		if sasl_stanza.name == "failure" then
			local err = sasl_stanza.tags[1];
			local text = sasl_stanza:get_child_text("text");
			stream:event("authentication-failure", { condition = err.name, text = text });
			stream:close();
			return false;
		end
		local ok, err = stream.sasl_mechanism(sasl_stanza.name, unbase64(sasl_stanza:get_text()));
		if not ok then
			stream:event("authentication-failure", { condition = err });
			stream:close();
			return false;
		elseif ok == true then
			stream:event("authentication-success");
			stream.authenticated = true
			stream:reopen();
		else
			stream:send(verse.stanza("response", { xmlns = xmlns_sasl }):text(base64(ok)));
		end
		return true;
	end

	stream:hook("stream-features", handle_features, 300);
	stream:hook("stream/"..xmlns_sasl, handle_sasl);

	return true;
end

