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

local register = {}

return {
	Register = function(self, eventName, eventFunc)
		argcheck(eventName, 1, "string")
		argcheck(eventFunc, 2, "function")

		if(not register[eventName]) then register[eventName] = {} end

		local module = debug.getinfo(2).short_src:match('modules/([^./]+)')
		register[eventName][module] = eventFunc
	end,

	Fire = function(self, eventName, ...)
		argcheck(eventName, 1, "string")

		local funcs = register[eventName]
		if(funcs) then
			for module, func in next, funcs do
				func(...)
			end
		end
	end,

	ClearModule = function(self, module)
		argcheck(module, 1, "string")

		for event, tbl in next, register do
			tbl[module] = nil
			if(not next(tbl)) then
				register[event] = nil
			end
		end
	end,

	ClearAll = function(self)
		register = {}
	end,
}
