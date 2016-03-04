local verse = require "verse";
local stream = verse.stream_mt;

local jid_split = require "util.jid".split;
local adns = require "net.adns";
local lxp = require "lxp";
local st = require "util.stanza";

-- Shortcuts to save having to load util.stanza
verse.message, verse.presence, verse.iq, verse.stanza, verse.reply, verse.error_reply =
	st.message, st.presence, st.iq, st.stanza, st.reply, st.error_reply;

local new_xmpp_stream = require "util.xmppstream".new;

local xmlns_stream = "http://etherx.jabber.org/streams";

local function compare_srv_priorities(a,b)
	return a.priority < b.priority or (a.priority == b.priority and a.weight > b.weight);
end

local stream_callbacks = {
	stream_ns = xmlns_stream,
	stream_tag = "stream",
	 default_ns = "jabber:client" };
	
function stream_callbacks.streamopened(stream, attr)
	stream.stream_id = attr.id;
	if not stream:event("opened", attr) then
		stream.notopen = nil;
	end
	return true;
end

function stream_callbacks.streamclosed(stream)
	stream.notopen = true;
	if not stream.closed then
		stream:send("</stream:stream>");
		stream.closed = true;
	end
	stream:event("closed");
	return stream:close("stream closed")
end

function stream_callbacks.handlestanza(stream, stanza)
	if stanza.attr.xmlns == xmlns_stream then
		return stream:event("stream-"..stanza.name, stanza);
	elseif stanza.attr.xmlns then
		return stream:event("stream/"..stanza.attr.xmlns, stanza);
	end

	return stream:event("stanza", stanza);
end

function stream_callbacks.error(stream, e, stanza)
	if stream:event(e, stanza) == nil then
		if stanza then
			local err = stanza:get_child(nil, "urn:ietf:params:xml:ns:xmpp-streams");
			local text = stanza:get_child_text("text", "urn:ietf:params:xml:ns:xmpp-streams");
			error(err.name..(text and ": "..text or ""));
		else
			error(stanza and stanza.name or e or "unknown-error");
		end
	end
end

function stream:reset()
	if self.stream then
		self.stream:reset();
	else
		self.stream = new_xmpp_stream(self, stream_callbacks);
	end
	self.notopen = true;
	return true;
end

function stream:connect_client(jid, pass)
	self.jid, self.password = jid, pass;
	self.username, self.host, self.resource = jid_split(jid);
	
	-- Required XMPP features
	self:add_plugin("tls");
	self:add_plugin("sasl");
	self:add_plugin("bind");
	self:add_plugin("session");
	
	function self.data(conn, data)
		local ok, err = self.stream:feed(data);
		if ok then return; end
		self:debug("Received invalid XML (%s) %d bytes: %s", tostring(err), #data, data:sub(1, 300):gsub("[\r\n]+", " "));
		self:close("xml-not-well-formed");
	end
	
	self:hook("connected", function () self:reopen(); end);
	self:hook("incoming-raw", function (data) return self.data(self.conn, data); end);
	
	self.curr_id = 0;
	
	self.tracked_iqs = {};
	self:hook("stanza", function (stanza)
		local id, type = stanza.attr.id, stanza.attr.type;
		if id and stanza.name == "iq" and (type == "result" or type == "error") and self.tracked_iqs[id] then
			self.tracked_iqs[id](stanza);
			self.tracked_iqs[id] = nil;
			return true;
		end
	end);
	
	self:hook("stanza", function (stanza)
		local ret;
		if stanza.attr.xmlns == nil or stanza.attr.xmlns == "jabber:client" then
			if stanza.name == "iq" and (stanza.attr.type == "get" or stanza.attr.type == "set") then
				local xmlns = stanza.tags[1] and stanza.tags[1].attr.xmlns;
				if xmlns then
					ret = self:event("iq/"..xmlns, stanza);
					if not ret then
						ret = self:event("iq", stanza);
					end
				end
				if ret == nil then
					self:send(verse.error_reply(stanza, "cancel", "service-unavailable"));
					return true;
				end
			else
				ret = self:event(stanza.name, stanza);
			end
		end
		return ret;
	end, -1);

	self:hook("outgoing", function (data)
		if data.name then
			self:event("stanza-out", data);
		end
	end);
	
	self:hook("stanza-out", function (stanza)
		if not stanza.attr.xmlns then
			self:event(stanza.name.."-out", stanza);
		end
	end);
	
	local function stream_ready()
		self:event("ready");
	end
	self:hook("session-success", stream_ready, -1)
	self:hook("bind-success", stream_ready, -1);

	local _base_close = self.close;
	function self:close(reason)
		self.close = _base_close;
		if not self.closed then
			self:send("</stream:stream>");
			self.closed = true;
		else
			return self:close(reason);
		end
	end
	
	local function start_connect()
		-- Initialise connection
		self:connect(self.connect_host or self.host, self.connect_port or 5222);
	end
	
	if not (self.connect_host or self.connect_port) then
		-- Look up SRV records
		adns.lookup(function (answer)
			if answer then
				local srv_hosts = {};
				self.srv_hosts = srv_hosts;
				for _, record in ipairs(answer) do
					table.insert(srv_hosts, record.srv);
				end
				table.sort(srv_hosts, compare_srv_priorities);
				
				local srv_choice = srv_hosts[1];
				self.srv_choice = 1;
				if srv_choice then
					self.connect_host, self.connect_port = srv_choice.target, srv_choice.port;
					self:debug("Best record found, will connect to %s:%d", self.connect_host or self.host, self.connect_port or 5222);
				end
				
				self:hook("disconnected", function ()
					if self.srv_hosts and self.srv_choice < #self.srv_hosts then
						self.srv_choice = self.srv_choice + 1;
						local srv_choice = srv_hosts[self.srv_choice];
						self.connect_host, self.connect_port = srv_choice.target, srv_choice.port;
						start_connect();
						return true;
					end
				end, 1000);
				
				self:hook("connected", function ()
					self.srv_hosts = nil;
				end, 1000);
			end
			start_connect();
		end, "_xmpp-client._tcp."..(self.host)..".", "SRV");
	else
		start_connect();
	end
end

function stream:reopen()
	self:reset();
	self:send(st.stanza("stream:stream", { to = self.host, ["xmlns:stream"]='http://etherx.jabber.org/streams',
		xmlns = "jabber:client", version = "1.0" }):top_tag());
end

function stream:send_iq(iq, callback)
	local id = self:new_id();
	self.tracked_iqs[id] = callback;
	iq.attr.id = id;
	self:send(iq);
end

function stream:new_id()
	self.curr_id = self.curr_id + 1;
	return tostring(self.curr_id);
end
