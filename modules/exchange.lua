local util = require'util'
local simplehttp = util.simplehttp
local json = util.json
local urlEncode = util.urlEncode
local key = ivar2.config.yfinanceApiKey

local cc = {
	["AED"] = "United Arab Emirates Dirham (AED)",
	["AFN"] = "Afghan Afghani (AFN)",
	["ALL"] = "Albanian Lek (ALL)",
	["AMD"] = "Armenian Dram (AMD)",
	["ANG"] = "Netherlands Antillean Guilder (ANG)",
	["AOA"] = "Angolan Kwanza (AOA)",
	["ARS"] = "Argentine Peso (ARS)",
	["AUD"] = "Australian Dollar (A$)",
	["AWG"] = "Aruban Florin (AWG)",
	["AZN"] = "Azerbaijani Manat (AZN)",
	["BAM"] = "Bosnia-Herzegovina Convertible Mark (BAM)",
	["BBD"] = "Barbadian Dollar (BBD)",
	["BDT"] = "Bangladeshi Taka (BDT)",
	["BGN"] = "Bulgarian Lev (BGN)",
	["BHD"] = "Bahraini Dinar (BHD)",
	["BIF"] = "Burundian Franc (BIF)",
	["BMD"] = "Bermudan Dollar (BMD)",
	["BND"] = "Brunei Dollar (BND)",
	["BOB"] = "Bolivian Boliviano (BOB)",
	["BRL"] = "Brazilian Real (R$)",
	["BSD"] = "Bahamian Dollar (BSD)",
	["BTC"] = "Bitcoin (฿)",
	["BTN"] = "Bhutanese Ngultrum (BTN)",
	["BWP"] = "Botswanan Pula (BWP)",
	["BYR"] = "Belarusian Ruble (BYR)",
	["BZD"] = "Belize Dollar (BZD)",
	["CAD"] = "Canadian Dollar (CA$)",
	["CDF"] = "Congolese Franc (CDF)",
	["CHF"] = "Swiss Franc (CHF)",
	["CLF"] = "Chilean Unit of Account (UF) (CLF)",
	["CLP"] = "Chilean Peso (CLP)",
	["CNH"] = "CNH (CNH)",
	["CNY"] = "Chinese Yuan (CN¥)",
	["COP"] = "Colombian Peso (COP)",
	["CRC"] = "Costa Rican Colón (CRC)",
	["CUP"] = "Cuban Peso (CUP)",
	["CVE"] = "Cape Verdean Escudo (CVE)",
	["CZK"] = "Czech Republic Koruna (CZK)",
	["DEM"] = "German Mark (DEM)",
	["DJF"] = "Djiboutian Franc (DJF)",
	["DKK"] = "Danish Krone (DKK)",
	["DOP"] = "Dominican Peso (DOP)",
	["DZD"] = "Algerian Dinar (DZD)",
	["EGP"] = "Egyptian Pound (EGP)",
	["ERN"] = "Eritrean Nakfa (ERN)",
	["ETB"] = "Ethiopian Birr (ETB)",
	["EUR"] = "Euro (€)",
	["FIM"] = "Finnish Markka (FIM)",
	["FJD"] = "Fijian Dollar (FJD)",
	["FKP"] = "Falkland Islands Pound (FKP)",
	["FRF"] = "French Franc (FRF)",
	["GBP"] = "British Pound Sterling (£)",
	["GEL"] = "Georgian Lari (GEL)",
	["GHS"] = "Ghanaian Cedi (GHS)",
	["GIP"] = "Gibraltar Pound (GIP)",
	["GMD"] = "Gambian Dalasi (GMD)",
	["GNF"] = "Guinean Franc (GNF)",
	["GTQ"] = "Guatemalan Quetzal (GTQ)",
	["GYD"] = "Guyanaese Dollar (GYD)",
	["HKD"] = "Hong Kong Dollar (HK$)",
	["HNL"] = "Honduran Lempira (HNL)",
	["HRK"] = "Croatian Kuna (HRK)",
	["HTG"] = "Haitian Gourde (HTG)",
	["HUF"] = "Hungarian Forint (HUF)",
	["IDR"] = "Indonesian Rupiah (IDR)",
	["IEP"] = "Irish Pound (IEP)",
	["ILS"] = "Israeli New Sheqel (₪)",
	["INR"] = "Indian Rupee (Rs.)",
	["IQD"] = "Iraqi Dinar (IQD)",
	["IRR"] = "Iranian Rial (IRR)",
	["ISK"] = "Icelandic Króna (ISK)",
	["ITL"] = "Italian Lira (ITL)",
	["JMD"] = "Jamaican Dollar (JMD)",
	["JOD"] = "Jordanian Dinar (JOD)",
	["JPY"] = "Japanese Yen (¥)",
	["KES"] = "Kenyan Shilling (KES)",
	["KGS"] = "Kyrgystani Som (KGS)",
	["KHR"] = "Cambodian Riel (KHR)",
	["KMF"] = "Comorian Franc (KMF)",
	["KPW"] = "North Korean Won (KPW)",
	["KRW"] = "South Korean Won (₩)",
	["KWD"] = "Kuwaiti Dinar (KWD)",
	["KYD"] = "Cayman Islands Dollar (KYD)",
	["KZT"] = "Kazakhstani Tenge (KZT)",
	["LAK"] = "Laotian Kip (LAK)",
	["LBP"] = "Lebanese Pound (LBP)",
	["LKR"] = "Sri Lankan Rupee (LKR)",
	["LRD"] = "Liberian Dollar (LRD)",
	["LSL"] = "Lesotho Loti (LSL)",
	["LTL"] = "Lithuanian Litas (LTL)",
	["LVL"] = "Latvian Lats (LVL)",
	["LYD"] = "Libyan Dinar (LYD)",
	["MAD"] = "Moroccan Dirham (MAD)",
	["MDL"] = "Moldovan Leu (MDL)",
	["MGA"] = "Malagasy Ariary (MGA)",
	["MKD"] = "Macedonian Denar (MKD)",
	["MMK"] = "Myanmar Kyat (MMK)",
	["MNT"] = "Mongolian Tugrik (MNT)",
	["MOP"] = "Macanese Pataca (MOP)",
	["MRO"] = "Mauritanian Ouguiya (MRO)",
	["MUR"] = "Mauritian Rupee (MUR)",
	["MVR"] = "Maldivian Rufiyaa (MVR)",
	["MWK"] = "Malawian Kwacha (MWK)",
	["MXN"] = "Mexican Peso (MX$)",
	["MYR"] = "Malaysian Ringgit (MYR)",
	["MZN"] = "Mozambican Metical (MZN)",
	["NAD"] = "Namibian Dollar (NAD)",
	["NGN"] = "Nigerian Naira (NGN)",
	["NIO"] = "Nicaraguan Córdoba (NIO)",
	["NOK"] = "Norwegian Krone (NOK)",
	["NPR"] = "Nepalese Rupee (NPR)",
	["NZD"] = "New Zealand Dollar (NZ$)",
	["OMR"] = "Omani Rial (OMR)",
	["PAB"] = "Panamanian Balboa (PAB)",
	["PEN"] = "Peruvian Nuevo Sol (PEN)",
	["PGK"] = "Papua New Guinean Kina (PGK)",
	["PHP"] = "Philippine Peso (Php)",
	["PKG"] = "PKG (PKG)",
	["PKR"] = "Pakistani Rupee (PKR)",
	["PLN"] = "Polish Zloty (PLN)",
	["PYG"] = "Paraguayan Guarani (PYG)",
	["QAR"] = "Qatari Rial (QAR)",
	["RON"] = "Romanian Leu (RON)",
	["RSD"] = "Serbian Dinar (RSD)",
	["RUB"] = "Russian Ruble (RUB)",
	["RWF"] = "Rwandan Franc (RWF)",
	["SAR"] = "Saudi Riyal (SAR)",
	["SBD"] = "Solomon Islands Dollar (SBD)",
	["SCR"] = "Seychellois Rupee (SCR)",
	["SDG"] = "Sudanese Pound (SDG)",
	["SEK"] = "Swedish Krona (SEK)",
	["SGD"] = "Singapore Dollar (SGD)",
	["SHP"] = "Saint Helena Pound (SHP)",
	["SLL"] = "Sierra Leonean Leone (SLL)",
	["SOS"] = "Somali Shilling (SOS)",
	["SRD"] = "Surinamese Dollar (SRD)",
	["STD"] = "São Tomé and Príncipe Dobra (STD)",
	["SVC"] = "Salvadoran Colón (SVC)",
	["SYP"] = "Syrian Pound (SYP)",
	["SZL"] = "Swazi Lilangeni (SZL)",
	["THB"] = "Thai Baht (฿)",
	["TJS"] = "Tajikistani Somoni (TJS)",
	["TMT"] = "Turkmenistani Manat (TMT)",
	["TND"] = "Tunisian Dinar (TND)",
	["TOP"] = "Tongan Paʻanga (TOP)",
	["TRY"] = "Turkish Lira (TRY)",
	["TTD"] = "Trinidad and Tobago Dollar (TTD)",
	["TWD"] = "New Taiwan Dollar (NT$)",
	["TZS"] = "Tanzanian Shilling (TZS)",
	["UAH"] = "Ukrainian Hryvnia (UAH)",
	["UGX"] = "Ugandan Shilling (UGX)",
	["USD"] = "US Dollar ($)",
	["UYU"] = "Uruguayan Peso (UYU)",
	["UZS"] = "Uzbekistan Som (UZS)",
	["VEF"] = "Venezuelan Bolívar (VEF)",
	["VND"] = "Vietnamese Dong (₫)",
	["VUV"] = "Vanuatu Vatu (VUV)",
	["WST"] = "Samoan Tala (WST)",
	["XAF"] = "CFA Franc BEAC (FCFA)",
	["XCD"] = "East Caribbean Dollar (EC$)",
	["XDR"] = "Special Drawing Rights (XDR)",
	["XOF"] = "CFA Franc BCEAO (CFA)",
	["XPF"] = "CFP Franc (CFPF)",
	["YER"] = "Yemeni Rial (YER)",
	["ZAR"] = "South African Rand (ZAR)",
	["ZMK"] = "Zambian Kwacha (1968–2012) (ZMK)",
	["ZMW"] = "Zambian Kwacha (ZMW)",
	["ZWL"] = "Zimbabwean Dollar (2009) (ZWL)",
}

local conv = {
	['euro'] = 'eur',
	['bux'] = 'usd',
	['buck'] = 'usd',
	['bucks'] = 'usd',
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

-- fetch the current price for a symbol (works for =X currency pairs and
-- hyphenated tickers like BTC-USD) via the same endpoint stonks uses
local function fetchPrice(symbol)
	local url = "https://yfapi.net/v11/finance/quoteSummary/" .. urlEncode(symbol) .. "?modules=price"
	local data = simplehttp({ url = url, method = 'GET', headers = { ['x-api-key'] = key } })
	if(not data) then return nil end
	local ok, res = pcall(json.decode, data)
	if(not ok) then return nil end
	local results = res.quoteSummary and res.quoteSummary.result
	if(not results or results == json.null) then return nil end
	if(type(results) ~= 'table') then return nil end
	local summary = results[1]
	local price = summary and summary.price
	if(not price) then return nil end
	local raw = price.regularMarketPrice and tonumber(price.regularMarketPrice.raw)
	if(not raw) then return nil end
	return raw
end

-- rate for FROM → TO, in TO per FROM (nil if not available)
local function exchangeRate(from, to)
	local raw = fetchPrice(from .. to .. '=X')
	if(raw) then return raw end
	-- inverse pair, e.g. PLNNOK=X is not covered but NOKPLN=X is
	raw = fetchPrice(to .. from .. '=X')
	if(raw and raw ~= 0) then return 1 / raw end
	-- BTC has no =X pair; quote it as a ticker
	if(from == 'BTC') then
		raw = fetchPrice('BTC-' .. to)
		if(raw) then return raw end
	end
	return nil
end

local function normalize(code)
	local lower = code:lower()
	lower = conv[lower] or lower
	return lower:upper()
end

local function checkInput(value, from, to)
	if(not (cc[from] and cc[to])) then
		return nil, string.format('Invalid currency: %s.', (not cc[from] and from) or (not cc[to] and to))
	end

	-- Control the input.
	value = value:gsub(',', '.')
	-- luacheck: ignore success
	local success, result = run('return ' .. value)
	if(not success) then
		return nil, string.format('Parsing of input failed: %s', tostring(result))
	end
	value = result

	-- Number validation, serious business!
	if(type(value) ~= 'number' or value <= 0 or value == math.huge or value ~= value) then
		return nil, string.format('Invalid number provided: %s', tostring(value))
	end

	return true, value
end

local function handleExchange(self, say, source, destination, value, from, to)
	from = normalize(from)
	to = normalize(to)

	if(from == to) then
		return say( 'wat ar u dewn... %s! STAHP!', source.nick)
	end

	local success, result = checkInput(value, from, to)
	if(not success) then
		return say( '%s: %s', source.nick, result)
	end
	value = result

	local rate = exchangeRate(from, to)
	if(not rate) then
		return say( '%s: no exchange rate for %s to %s.', source.nick, from, to)
	end

	local converted = value * rate
	say( '%s: %s %s = %s %s', source.nick, value, from, string.format('%.2f', converted), to)
end

-- !xe/!cur take a single capture and split it: "<value> <from> [to]"
local function handleXe(self, say, source, destination, arg)
	local value, from, to = arg:match('^(%S+)%s+(%S+)%s*(.*)$')
	if(not value) then
		return say( '%s: usage: !xe <value> <from> [to]', source.nick)
	end
	to = (to ~= '' and to) or 'NOK'
	return handleExchange(self, say, source, destination, value, from, to)
end

return {
	PRIVMSG = {
		['^%pxe (.+)$'] = function(self, source, destination, arg)
			return handleXe(self, say, source, destination, arg)
		end,
		['^%pcur (.+)$'] = function(self, source, destination, arg)
			return handleXe(self, say, source, destination, arg)
		end,
		['^%pusd$'] = function(self, source, destination)
			return handleExchange(self, say, source, destination, '1', 'USD', 'NOK')
		end,
		['^%peur$'] = function(self, source, destination)
			return handleExchange(self, say, source, destination, '1', 'EUR', 'NOK')
		end,
		['^%pjpy$'] = function(self, source, destination)
			return handleExchange(self, say, source, destination, '100', 'JPY', 'NOK')
		end,
		['^%pzloty$'] = function(self, source, destination)
			return handleExchange(self, say, source, destination, '1', 'PLN', 'NOK')
		end,
		['^%p฿$'] = function(self, source, destination)
			return handleExchange(self, say, source, destination, '1', 'BTC', 'USD')
		end,
	},
}
