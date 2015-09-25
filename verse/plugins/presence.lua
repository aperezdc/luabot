local verse = require "verse";

function verse.plugins.presence(stream)
	stream.last_presence = nil;

	stream:hook("presence-out", function (presence)
		if not presence.attr.to then
			stream.last_presence = presence; -- Cache non-directed presence
		end
	end, 1);

	function stream:resend_presence()
		if last_presence then
			stream:send(last_presence);
		end
	end

	function stream:set_status(opts)
		local p = verse.presence();
		if type(opts) == "table" then
			if opts.show then
				p:tag("show"):text(opts.show):up();
			end
			if opts.prio then
				p:tag("priority"):text(tostring(opts.prio)):up();
			end
			if opts.msg then
				p:tag("status"):text(opts.msg):up();
			end
		end
		-- TODO maybe use opts as prio if it's a int,
		-- or as show or status if it's a string?

		stream:send(p);
	end
end
