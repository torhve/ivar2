local argcheck = function(value, num, ...)
	assert(type(num) == 'number', "Bad argument #2 to 'argcheck' (number expected, got ".. type(num) ..")")

	for i=1,select("#", ...) do
		if type(value) == select(i, ...) then return end
	end

	local types = {}
	for i=1, select("#", ...) do types[#types] = select(i, ...) end

	local name = string.match(debug.traceback(2, 2, 0), ": in function ['<](.-)['>]")
	error(("Bad argument #%d to '%s' (%s expected, got %s"):format(num, name, table.concat(types, ', '), type(value)), 3)
end

return {
	__register = {},

	Register = function(self, eventName, eventFunc)
		argcheck(eventName, 1, "string")
		argcheck(eventFunc, 2, "function")

		if(not self.__register[eventName]) then self.__register[eventName] = {} end

		local funcs = self.__register[eventName]
		for i=1, #funcs do
			if(funcs[i] == func) then
				return nil, "Event handler already registered."
			end
		end

		funcs[#funcs + 1] = eventFunc
	end,

	Fire = function(self, eventName, ...)
		argcheck(eventName, 1, "string")

		local funcs = self.__register[eventName]
		if(funcs) then
			for i=1, #funcs do
				funcs[i](...)
			end
		end
	end,

	ClearAll = function(self)
		self.__register = {}
	end,
}
