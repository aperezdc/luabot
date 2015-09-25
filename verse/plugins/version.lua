local verse = require "verse";

local xmlns_version = "jabber:iq:version";

local function set_version(self, version_info)
	self.name = version_info.name;
	self.version = version_info.version;
	self.platform = version_info.platform;
end

function verse.plugins.version(stream)
	stream.version = { set = set_version };
	stream:hook("iq/"..xmlns_version, function (stanza)
		if stanza.attr.type ~= "get" then return; end
		local reply = verse.reply(stanza)
			:tag("query", { xmlns = xmlns_version });
		if stream.version.name then
			reply:tag("name"):text(tostring(stream.version.name)):up();
		end
		if stream.version.version then
			reply:tag("version"):text(tostring(stream.version.version)):up()
		end
		if stream.version.platform then
			reply:tag("os"):text(stream.version.platform);
		end
		stream:send(reply);
		return true;
	end);
	
	function stream:query_version(target_jid, callback)
		callback = callback or function (version) return stream:event("version/response", version); end
		stream:send_iq(verse.iq({ type = "get", to = target_jid })
			:tag("query", { xmlns = xmlns_version }), 
			function (reply)
				if reply.attr.type == "result" then
					local query = reply:get_child("query", xmlns_version);
					local name = query and query:get_child_text("name");
					local version = query and query:get_child_text("version");
					local os = query and query:get_child_text("os");
					callback({
						name = name;
						version = version;
						platform = os;
						});
				else
					local type, condition, text = reply:get_error();
					callback({
						error = true;
						condition = condition;
						text = text;
						type = type;
						});
				end
			end);
	end
	return true;
end
