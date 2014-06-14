local simplehttp = require'simplehttp'
local html2unicode = require'html'

local cc = {
	["AED"] = "United Arab Emirates Dirham (AED)",
	["ANG"] = "Netherlands Antillean Guilder (ANG)",
	["ARS"] = "Argentine Peso (ARS)",
	["AUD"] = "Australian Dollar (AUD)",
	["BDT"] = "Bangladeshi Taka (BDT)",
	["BGN"] = "Bulgarian Lev (BGN)",
	["BHD"] = "Bahraini Dinar (BHD)",
	["BND"] = "Brunei Dollar (BND)",
	["BOB"] = "Bolivian Boliviano (BOB)",
	["BRL"] = "Brazilian Real (BRL)",
	["BWP"] = "Botswanan Pula (BWP)",
	["CAD"] = "Canadian Dollar (CAD)",
	["CHF"] = "Swiss Franc (CHF)",
	["CLP"] = "Chilean Peso (CLP)",
	["CNY"] = "Chinese Yuan (CNY)",
	["COP"] = "Colombian Peso (COP)",
	["CRC"] = "Costa Rican Colón (CRC)",
	["CZK"] = "Czech Republic Koruna (CZK)",
	["DKK"] = "Danish Krone (DKK)",
	["DOP"] = "Dominican Peso (DOP)",
	["DZD"] = "Algerian Dinar (DZD)",
	["EEK"] = "Estonian Kroon (EEK)",
	["EGP"] = "Egyptian Pound (EGP)",
	["EUR"] = "Euro (EUR)",
	["FJD"] = "Fijian Dollar (FJD)",
	["GBP"] = "British Pound Sterling (GBP)",
	["HKD"] = "Hong Kong Dollar (HKD)",
	["HNL"] = "Honduran Lempira (HNL)",
	["HRK"] = "Croatian Kuna (HRK)",
	["HUF"] = "Hungarian Forint (HUF)",
	["IDR"] = "Indonesian Rupiah (IDR)",
	["ILS"] = "Israeli New Sheqel (ILS)",
	["INR"] = "Indian Rupee (INR)",
	["JMD"] = "Jamaican Dollar (JMD)",
	["JOD"] = "Jordanian Dinar (JOD)",
	["JPY"] = "Japanese Yen (JPY)",
	["KES"] = "Kenyan Shilling (KES)",
	["KRW"] = "South Korean Won (KRW)",
	["KWD"] = "Kuwaiti Dinar (KWD)",
	["KYD"] = "Cayman Islands Dollar (KYD)",
	["KZT"] = "Kazakhstani Tenge (KZT)",
	["LBP"] = "Lebanese Pound (LBP)",
	["LKR"] = "Sri Lankan Rupee (LKR)",
	["LTL"] = "Lithuanian Litas (LTL)",
	["LVL"] = "Latvian Lats (LVL)",
	["MAD"] = "Moroccan Dirham (MAD)",
	["MDL"] = "Moldovan Leu (MDL)",
	["MKD"] = "Macedonian Denar (MKD)",
	["MUR"] = "Mauritian Rupee (MUR)",
	["MVR"] = "Maldivian Rufiyaa (MVR)",
	["MXN"] = "Mexican Peso (MXN)",
	["MYR"] = "Malaysian Ringgit (MYR)",
	["NAD"] = "Namibian Dollar (NAD)",
	["NGN"] = "Nigerian Naira (NGN)",
	["NIO"] = "Nicaraguan Córdoba (NIO)",
	["NOK"] = "Norwegian Krone (NOK)",
	["NPR"] = "Nepalese Rupee (NPR)",
	["NZD"] = "New Zealand Dollar (NZD)",
	["OMR"] = "Omani Rial (OMR)",
	["PEN"] = "Peruvian Nuevo Sol (PEN)",
	["PGK"] = "Papua New Guinean Kina (PGK)",
	["PHP"] = "Philippine Peso (PHP)",
	["PKR"] = "Pakistani Rupee (PKR)",
	["PLN"] = "Polish Zloty (PLN)",
	["PYG"] = "Paraguayan Guarani (PYG)",
	["QAR"] = "Qatari Rial (QAR)",
	["RON"] = "Romanian Leu (RON)",
	["RSD"] = "Serbian Dinar (RSD)",
	["RUB"] = "Russian Ruble (RUB)",
	["SAR"] = "Saudi Riyal (SAR)",
	["SCR"] = "Seychellois Rupee (SCR)",
	["SEK"] = "Swedish Krona (SEK)",
	["SGD"] = "Singapore Dollar (SGD)",
	["SKK"] = "Slovak Koruna (SKK)",
	["SLL"] = "Sierra Leonean Leone (SLL)",
	["SVC"] = "Salvadoran Colón (SVC)",
	["THB"] = "Thai Baht (THB)",
	["TND"] = "Tunisian Dinar (TND)",
	["TRY"] = "Turkish Lira (TRY)",
	["TTD"] = "Trinidad and Tobago Dollar (TTD)",
	["TWD"] = "New Taiwan Dollar (TWD)",
	["TZS"] = "Tanzanian Shilling (TZS)",
	["UAH"] = "Ukrainian Hryvnia (UAH)",
	["UGX"] = "Ugandan Shilling (UGX)",
	["USD"] = "US Dollar (USD)",
	["UYU"] = "Uruguayan Peso (UYU)",
	["UZS"] = "Uzbekistan Som (UZS)",
	["VEF"] = "Venezuelan Bolívar (VEF)",
	["VND"] = "Vietnamese Dong (VND)",
	["XOF"] = "CFA Franc BCEAO (XOF)",
	["YER"] = "Yemeni Rial (YER)",
	["ZAR"] = "South African Rand (ZAR)",
	["ZMK"] = "Zambian Kwacha (ZMK)",
}

local conv = {
	['euro'] = 'eur',
	['bux'] = 'usd',
}

-- make environment
local _X = setmetatable({
	math = math,
	print = function(val) if(val and tonumber(val)) then return tonumber(val) end end
}, {__index = math})

-- run code under environment
local function run(untrusted_code)
	local untrusted_function, message = loadstring(untrusted_code)
	if not untrusted_function then return nil, message end
	setfenv(untrusted_function, _X)
	return pcall(untrusted_function)
end

local parseData = function(data)
	local data = data:match'<div id=currency_converter_result>(.-)</span>'
	if(not data) then
		return 'Some currency died? No exchange rates returned.'
	end

	return html2unicode(data:gsub('<.->', '')):gsub('  ', ' '):gsub('%w+', cc)
end

local checkInput = function(value, from, to)
	if(not (cc[from] and cc[to])) then
		return nil, string.format('Invalid currency: %s.', (not cc[from] and from) or (not cc[to] and to))
	end

	-- Control the input.
	value = value:gsub(',', '.')
	local success, value, err = run('return ' .. value)
	if(err) then
		return nil, string.format('Parsing of input failed: %s', err)
	end

	-- Number validation, serious business!
	if(type(value) ~= 'number' or value <= 0 or value == math.huge or value ~= value) then
		return nil, string.format('Invalid number provided: %s', tonumber(value))
	end

	return true, value
end

local handleExchange = function(self, source, destination, value, from, to)
	-- Strip away to/in and spaces.
	to = to:lower():gsub('[toin ]+ ', '')
	from = from:lower()

	-- Default to NOK.
	if(to == '') then to = 'NOK' end

	from = (conv[from] or from):upper()
	to = (conv[to] or to):upper()

	if(from == to) then
		return self:Msg('privmsg', destination, source, 'wat ar u dewn... %s! STAHP!', source.nick)
	end

	local success, value = checkInput(value, from, to)
	if(not success) then
		self:Msg('privmsg', destination, source, '%s: %s', source.nick, value)
	else
		simplehttp(
			('http://www.google.com/finance/converter?a=%s&from=%s&to=%s'):format(value, from, to),
			function(data)
				local message = parseData(data)
				if(message) then
					self:Msg('privmsg', destination, source, '%s: %s', source.nick, message)
				end
			end
		)
	end
end

return {
	PRIVMSG = {
		['^%pxe (%S+) (%S+) ?(.*)$'] = handleExchange,
		['^%pcur (%S+) (%S+) ?(.*)$'] = handleExchange,
		['^%pjpy'] = function(self, source, destination)
			handleExchange(self, source, destination, '100', 'JPY', 'NOK')
		end
	},
}
