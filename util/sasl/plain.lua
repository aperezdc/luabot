
return function (stream, name)
	if name == "PLAIN" and stream.username and stream.password then
		return function (stream)
			return "success" == coroutine.yield("\0"..stream.username.."\0"..stream.password);
		end, 5;
	end
end

