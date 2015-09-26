local verse = require "verse";

function verse.plugins.keepalive(stream)
	stream.keepalive_timeout = stream.keepalive_timeout or 300;
	verse.add_task(stream.keepalive_timeout, function ()
		stream.conn:write(" ");
		return stream.keepalive_timeout;
	end);
end
