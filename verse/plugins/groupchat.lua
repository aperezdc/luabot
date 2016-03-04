local verse = require "verse";
local events = require "util.events";
local jid = require "util.jid";

local room_mt = {};
room_mt.__index = room_mt;

local xmlns_delay = "urn:xmpp:delay";
local xmlns_muc = "http://jabber.org/protocol/muc";

function verse.plugins.groupchat(stream)
	stream:add_plugin("presence")
	stream.rooms = {};

	stream:hook("stanza", function (stanza)
		local room_jid = jid.bare(stanza.attr.from);
		if not room_jid then return end
		local room = stream.rooms[room_jid]
		if not room and stanza.attr.to and room_jid then
			room = stream.rooms[stanza.attr.to.." "..room_jid]
		end
		if room and room.opts.source and stanza.attr.to ~= room.opts.source then return end
		if room then
			local nick = select(3, jid.split(stanza.attr.from));
			local body = stanza:get_child_text("body");
			local delay = stanza:get_child("delay", xmlns_delay);
			local event = {
				room_jid = room_jid;
				room = room;
				sender = room.occupants[nick];
				nick = nick;
				body = body;
				stanza = stanza;
				delay = (delay and delay.attr.stamp);
			};
			local ret = room:event(stanza.name, event);
			return ret or (stanza.name == "message") or nil;
		end
	end, 500);

	function stream:join_room(jid, nick, opts)
		if not nick then
			return false, "no nickname supplied"
		end
		opts = opts or {};
		local room = setmetatable(verse.eventable{
			stream = stream, jid = jid, nick = nick,
			subject = nil,
			occupants = {},
			opts = opts,
		}, room_mt);
		if opts.source then
			self.rooms[opts.source.." "..jid] = room;
		else
			self.rooms[jid] = room;
		end
		local occupants = room.occupants;
		room:hook("presence", function (presence)
			local nick = presence.nick or nick;
			if not occupants[nick] and presence.stanza.attr.type ~= "unavailable" then
				occupants[nick] = {
					nick = nick;
					jid = presence.stanza.attr.from;
					presence = presence.stanza;
				};
				local x = presence.stanza:get_child("x", xmlns_muc .. "#user");
				if x then
					local x_item = x:get_child("item");
					if x_item and x_item.attr then
						occupants[nick].real_jid    = x_item.attr.jid;
						occupants[nick].affiliation = x_item.attr.affiliation;
						occupants[nick].role        = x_item.attr.role;
					end
					--TODO Check for status 100?
				end
				if nick == room.nick then
					room.stream:event("groupchat/joined", room);
				else
					room:event("occupant-joined", occupants[nick]);
				end
			elseif occupants[nick] and presence.stanza.attr.type == "unavailable" then
				if nick == room.nick then
					room.stream:event("groupchat/left", room);
					if room.opts.source then
						self.rooms[room.opts.source.." "..jid] = nil;
					else
						self.rooms[jid] = nil;
					end
				else
					occupants[nick].presence = presence.stanza;
					room:event("occupant-left", occupants[nick]);
					occupants[nick] = nil;
				end
			end
		end);
		room:hook("message", function(event)
			local subject = event.stanza:get_child_text("subject");
			if not subject then return end
			subject = #subject > 0 and subject or nil;
			if subject ~= room.subject then
				local old_subject = room.subject;
				room.subject = subject;
				return room:event("subject-changed", { from = old_subject, to = subject, by = event.sender, event = event });
			end
		end, 2000);
		local join_st = verse.presence():tag("x",{xmlns = xmlns_muc}):reset();
		self:event("pre-groupchat/joining", join_st);
		room:send(join_st)
		self:event("groupchat/joining", room);
		return room;
	end

	stream:hook("presence-out", function(presence)
		if not presence.attr.to then
			for _, room in pairs(stream.rooms) do
				room:send(presence);
			end
			presence.attr.to = nil;
		end
	end);
end

function room_mt:send(stanza)
	if stanza.name == "message" and not stanza.attr.type then
		stanza.attr.type = "groupchat";
	end
	if stanza.name == "presence" then
		stanza.attr.to = self.jid .."/"..self.nick;
	end
	if stanza.attr.type == "groupchat" or not stanza.attr.to then
		stanza.attr.to = self.jid;
	end
	if self.opts.source then
		stanza.attr.from = self.opts.source
	end
	self.stream:send(stanza);
end

function room_mt:send_message(text)
	self:send(verse.message():tag("body"):text(text));
end

function room_mt:set_subject(text)
	self:send(verse.message():tag("subject"):text(text));
end

function room_mt:leave(message)
	self.stream:event("groupchat/leaving", self);
	local presence = verse.presence({type="unavailable"});
	if message then
		presence:tag("status"):text(message);
	end
	self:send(presence);
end

function room_mt:admin_set(nick, what, value, reason)
	self:send(verse.iq({type="set"})
		:query(xmlns_muc .. "#admin")
			:tag("item", {nick = nick, [what] = value})
				:tag("reason"):text(reason or ""));
end

function room_mt:set_role(nick, role, reason)
	self:admin_set(nick, "role", role, reason);
end

function room_mt:set_affiliation(nick, affiliation, reason)
	self:admin_set(nick, "affiliation", affiliation, reason);
end

function room_mt:kick(nick, reason)
	self:set_role(nick, "none", reason);
end

function room_mt:ban(nick, reason)
	self:set_affiliation(nick, "outcast", reason);
end
