local function not_impl()
	error("Function not implemented");
end
local mime = require "mime";

return {
	stringprep = {};
	base64 = { encode = mime.b64, decode = not_impl }; --mime.unb64 is buggy with \0
};
