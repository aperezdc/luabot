
local base64, unbase64 = require "mime".b64, require"mime".unb64;
local hashes = require"util.hashes";
local bit = require"bit";
local random = require"util.random";

local tonumber = tonumber;
local char, byte = string.char, string.byte;
local gsub = string.gsub;
local xor = bit.bxor;

local function XOR(a, b)
	return (gsub(a, "()(.)", function(i, c)
		return char(xor(byte(c), byte(b, i)))
	end));
end

local H, HMAC = hashes.sha1, hashes.hmac_sha1;

local function Hi(str, salt, i)
	local U = HMAC(str, salt .. "\0\0\0\1");
	local ret = U;
	for _ = 2, i do
		U = HMAC(str, U);
		ret = XOR(ret, U);
	end
	return ret;
end

local function Normalize(str)
	return str; -- TODO
end

local function value_safe(str)
	return (gsub(str, "[,=]", { [","] = "=2C", ["="] = "=3D" }));
end

local function scram(stream, name)
	local username = "n=" .. value_safe(stream.username);
	local c_nonce = base64(random.bytes(15));
	local our_nonce = "r=" .. c_nonce;
	local client_first_message_bare = username .. "," .. our_nonce;
	local cbind_data = "";
	local gs2_cbind_flag = stream.conn:ssl() and "y" or "n";
	if name == "SCRAM-SHA-1-PLUS" then
		cbind_data = stream.conn:socket():getfinished();
		gs2_cbind_flag = "p=tls-unique";
	end
	local gs2_header = gs2_cbind_flag .. ",,";
	local client_first_message = gs2_header .. client_first_message_bare;
	local cont, server_first_message = coroutine.yield(client_first_message);
	if cont ~= "challenge" then return false end

	local nonce, salt, iteration_count = server_first_message:match("(r=[^,]+),s=([^,]*),i=(%d+)");
	local i = tonumber(iteration_count);
	salt = unbase64(salt);
	if not nonce or not salt or not i then
		return false, "Could not parse server_first_message";
	elseif nonce:find(c_nonce, 3, true) ~= 3 then
		return false, "nonce sent by server does not match our nonce";
	elseif nonce == our_nonce then
		return false, "server did not append s-nonce to nonce";
	end

	local cbind_input = gs2_header .. cbind_data;
	local channel_binding = "c=" .. base64(cbind_input);
	local client_final_message_without_proof = channel_binding .. "," .. nonce;

	local SaltedPassword  = Hi(Normalize(stream.password), salt, i);
	local ClientKey       = HMAC(SaltedPassword, "Client Key");
	local StoredKey       = H(ClientKey);
	local AuthMessage     = client_first_message_bare .. "," ..  server_first_message .. "," ..  client_final_message_without_proof;
	local ClientSignature = HMAC(StoredKey, AuthMessage);
	local ClientProof     = XOR(ClientKey, ClientSignature);
	local ServerKey       = HMAC(SaltedPassword, "Server Key");
	local ServerSignature = HMAC(ServerKey, AuthMessage);

	local proof = "p=" .. base64(ClientProof);
	local client_final_message = client_final_message_without_proof .. "," .. proof;

	local ok, server_final_message = coroutine.yield(client_final_message);
	if ok ~= "success" then return false, "success-expected" end

	local verifier = server_final_message:match("v=([^,]+)");
	if unbase64(verifier) ~= ServerSignature then
		return false, "server signature did not match";
	end
	return true;
end

return function (stream, name)
	if stream.username and (stream.password or (stream.client_key or stream.server_key)) then
		if name == "SCRAM-SHA-1" then
			return scram, 99;
		elseif name == "SCRAM-SHA-1-PLUS" then
			local sock = stream.conn:ssl() and stream.conn:socket();
			if sock and sock.getfinished then
				return scram, 100;
			end
		end
	end
end

