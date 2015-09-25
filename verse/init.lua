
-- Use LuaRocks if available
pcall(require, "luarocks.require");

local socket = require"socket";

-- Load LuaSec if available
pcall(require, "ssl");

local server = require "net.server";
local events = require "util.events";
local logger = require "util.logger";

module("verse", package.seeall);
local verse = _M;
_M.server = server;

local stream = {};
stream.__index = stream;
stream_mt = stream;

verse.plugins = {};

function verse.init(...)
	for i=1,select("#", ...) do
		local ok = pcall(require, "verse."..select(i,...));
		if not ok then
			error("Verse connection module not found: verse."..select(i,...));
		end
	end
	return verse;
end


local max_id = 0;

function verse.new(logger, base)
	local t = setmetatable(base or {}, stream);
	max_id = max_id + 1;
	t.id = tostring(max_id);
	t.logger = logger or verse.new_logger("stream"..t.id);
	t.events = events.new();
	t.plugins = {};
	t.verse = verse;
	return t;
end

verse.add_task = require "util.timer".add_task;

verse.logger = logger.init; -- COMPAT: Deprecated
verse.new_logger = logger.init;
verse.log = verse.logger("verse");

local function format(format, ...)
	local n, arg, maxn = 0, { ... }, select('#', ...);
	return (format:gsub("%%(.)", function (c) if n <= maxn then n = n + 1; return tostring(arg[n]); end end));
end

function verse.set_log_handler(log_handler, levels)
	levels = levels or { "debug", "info", "warn", "error" };
	logger.reset();
	if io.type(log_handler) == "file" then
		local f = log_handler;
		function log_handler(name, level, message)
			f:write(name, "\t", level, "\t", message, "\n");
		end
	end
	if log_handler then
		local function _log_handler(name, level, message, ...)
			return log_handler(name, level, format(message, ...));
		end
		for i, level in ipairs(levels) do
			logger.add_level_sink(level, _log_handler);
		end
	end
end

function _default_log_handler(name, level, message)
	return io.stderr:write(name, "\t", level, "\t", message, "\n");
end
verse.set_log_handler(_default_log_handler, { "error" });

local function error_handler(err)
	verse.log("error", "Error: %s", err);
	verse.log("error", "Traceback: %s", debug.traceback());
end

function verse.set_error_handler(new_error_handler)
	error_handler = new_error_handler;
end

function verse.loop()
	return xpcall(server.loop, error_handler);
end

function verse.step()
	return xpcall(server.step, error_handler);
end

function verse.quit()
	return server.setquitting(true);
end

function stream:listen(host, port)
	host = host or "localhost";
	port = port or 0;
	local conn, err = server.addserver(host, port, new_listener(self, "server"), "*a");
	if conn then
		self:debug("Bound to %s:%s", host, port);
		self.server = conn;
	end
	return conn, err;
end

function stream:connect(connect_host, connect_port)
	connect_host = connect_host or "localhost";
	connect_port = tonumber(connect_port) or 5222;
	
	-- Create and initiate connection
	local conn = socket.tcp()
	conn:settimeout(0);
	local success, err = conn:connect(connect_host, connect_port);
	
	if not success and err ~= "timeout" then
		self:warn("connect() to %s:%d failed: %s", connect_host, connect_port, err);
		return self:event("disconnected", { reason = err }) or false, err;
	end

	local conn = server.wrapclient(conn, connect_host, connect_port, new_listener(self), "*a");
	if not conn then
		self:warn("connection initialisation failed: %s", err);
		return self:event("disconnected", { reason = err }) or false, err;
	end
	self:set_conn(conn);
	return true;
end

function stream:set_conn(conn)
	self.conn = conn;
	self.send = function (stream, data)
		self:event("outgoing", data);
		data = tostring(data);
		self:event("outgoing-raw", data);
		return conn:write(data);
	end;
end

function stream:close(reason)
	if not self.conn then 
		verse.log("error", "Attempt to close disconnected connection - possibly a bug");
		return;
	end
	local on_disconnect = self.conn.disconnect();
	self.conn:close();
	on_disconnect(self.conn, reason);
end

-- Logging functions
function stream:debug(...)
	return self.logger("debug", ...);
end

function stream:info(...)
	return self.logger("info", ...);
end

function stream:warn(...)
	return self.logger("warn", ...);
end

function stream:error(...)
	return self.logger("error", ...);
end

-- Event handling
function stream:event(name, ...)
	self:debug("Firing event: "..tostring(name));
	return self.events.fire_event(name, ...);
end

function stream:hook(name, ...)
	return self.events.add_handler(name, ...);
end

function stream:unhook(name, handler)
	return self.events.remove_handler(name, handler);
end

function verse.eventable(object)
        object.events = events.new();
        object.hook, object.unhook = stream.hook, stream.unhook;
        local fire_event = object.events.fire_event;
        function object:event(name, ...)
                return fire_event(name, ...);
        end
        return object;
end

function stream:add_plugin(name)
	if self.plugins[name] then return true; end
	if require("verse.plugins."..name) then
		local ok, err = verse.plugins[name](self);
		if ok ~= false then
			self:debug("Loaded %s plugin", name);
			self.plugins[name] = true;
		else
			self:warn("Failed to load %s plugin: %s", name, err);
		end
	end
	return self;
end

-- Listener factory
function new_listener(stream)
	local conn_listener = {};
	
	function conn_listener.onconnect(conn)
		if stream.server then
			local client = verse.new();
			conn:setlistener(new_listener(client));
			client:set_conn(conn);
			stream:event("connected", { client = client });
		else
			stream.connected = true;
			stream:event("connected");
		end
	end
	
	function conn_listener.onincoming(conn, data)
		stream:event("incoming-raw", data);
	end
	
	function conn_listener.ondisconnect(conn, err)
		if conn ~= stream.conn then return end
		stream.connected = false;
		stream:event("disconnected", { reason = err });
	end

	function conn_listener.ondrain(conn)
		stream:event("drained");
	end
	
	function conn_listener.onstatus(conn, new_status)
		stream:event("status", new_status);
	end
	
	return conn_listener;
end

return verse;
