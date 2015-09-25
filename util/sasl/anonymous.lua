
return function (stream, name)
	if name == "ANONYMOUS" then
		return function ()
			return coroutine.yield() == "success";
		end, 0;
	end
end
