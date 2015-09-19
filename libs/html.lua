local mod = math.mod
local entities = setmetatable(
	{
		quot = '"', apos = "'", amp = "&", lt = "<", gt = ">", nbsp = " ",
		iexcl = "¡", cent = "¢", pound = "£", curren = "¤", yen = "¥", brvbar = "¦",
		sect = "§", uml = "¨", copy = "©", ordf = "ª", laquo = "«", ['not'] = "¬",
		shy = "­", reg = "®", macr = "¯", deg = "°", plusmn = "±", sup2 = "²",
		sup3 = "³", acute = "´", micro = "µ", para = "¶", middot = "·", cedil = "¸",
		sup1 = "¹", ordm = "º", raquo = "»", frac14 = "¼", frac12 = "½", frac34 = "¾",
		iquest = "¿", times = "×", divide = "÷", Agrave = "À", Aacute = "Á", Acirc = "Â",
		Atilde = "Ã", Auml = "Ä", Aring = "Å", AElig = "Æ", Ccedil = "Ç", Egrave = "È",
		Eacute = "É", Ecirc = "Ê", Euml = "Ë", Igrave = "Ì", Iacute = "Í", Icirc = "Î",
		Iuml = "Ï", ETH = "Ð", Ntilde = "Ñ", Ograve = "Ò", Oacute = "Ó", Ocirc = "Ô",
		Otilde = "Õ", Ouml = "Ö", Oslash = "Ø", Ugrave = "Ù", Uacute = "Ú", Ucirc = "Û",
		Uuml = "Ü", Yacute = "Ý", THORN = "Þ", szlig = "ß", agrave = "à", aacute = "á",
		acirc = "â", atilde = "ã", auml = "ä", aring = "å", aelig = "æ", ccedil = "ç",
		egrave = "è", eacute = "é", ecirc = "ê", euml = "ë", igrave = "ì", iacute = "í",
		icirc = "î", iuml = "ï", eth = "ð", ntilde = "ñ", ograve = "ò", oacute = "ó",
		ocirc = "ô", otilde = "õ", ouml = "ö", oslash = "ø", ugrave = "ù", uacute = "ú",
		ucirc = "û", uuml = "ü", yacute = "ý", thorn = "þ", yuml = "ÿ", forall = "∀",
		part = "∂", exists = "∃", empty = "∅", nabla = "∇", isin = "∈", notin = "∉",
		ni = "∋", prod = "∏", sum = "∑", minus = "−", lowast = "∗", radic = "√",
		prop = "∝", infin = "∞", ang = "∠", ['and'] = "∧", ['or'] = "∨", cap = "∩",
		cup = "∪", int = "∫", there4 = "∴", sim = "∼", cong = "≅", asymp = "≈",
		ne = "≠", equiv = "≡", le = "≤", ge = "≥", sub = "⊂", sup = "⊃",
		nsub = "⊄", sube = "⊆", supe = "⊇", oplus = "⊕", otimes = "⊗", perp = "⊥",
		sdot = "⋅", Aplha = "Α", Beta = "Β", Gamma = "Γ", Delta = "Δ", Epsilon = "Ε",
		Zeta = "Ζ", Eta = "Η", Theta = "Θ", Iota = "Ι", Kappa = "Κ", Lambda = "Λ",
		Mu = "Μ", Nu = "Ν", Xi = "Ξ", Omicron = "Ο", Pi = "Π", Rho = "Ρ",
		Sigma = "Σ", Tau = "Τ", Upsilon = "Υ", Phi = "Φ", Chi = "Χ", Psi = "Ψ",
		Omega = "Ω", aplha = "α", beta = "β", gamma = "γ", delta = "δ", epsilon = "ε",
		zeta = "ζ", eta = "η", theta = "θ", iota = "ι", kappa = "κ", lambda = "λ",
		mu = "μ", nu = "ν", xi = "ξ", omicron = "ο", pi = "π", rho = "ρ",
		tau = "τ", upsilon = "υ", phi = "φ", chi = "χ", psi = "ψ", omega = "ω",
		thetasym = "ϑ", upsih = "ϒ", piv = "ϖ", OElig = "Œ", oelig = "œ", Scaron = "Š",
		scaron = "š", Yuml = "Ÿ", fnof = "ƒ", circ = "ˆ", tilde = "˜", ensp = " ",
		emsp = " ", thinsp = " ", zwnj = "‌", zwj = "‍", lrm = "‎", rlm = "‏",
		ndash = "–", mdash = "—", lsquo = "‘", rsquo = "’", sbquo = "‚", ldquo = "“",
		rdquo = "”", bdquo = "„", dagger = "†", Dagger = "‡", bull = "•", hellip = "…",
		permil = "‰", prime = "′", Prime = "″", lsaquo = "‹", rsaquo = "›", oline = "‾",
		euro = "€", trade = "™", larr = "←", uarr = "↑", rarr = "→", darr = "↓",
		harr = "↔", crarr = "↵", lceil = "⌈", rceil = "⌉", lfloor = "⌊", rfloor = "⌋",
		loz = "◊", spades = "♠", clubs = "♣", hearts = "♥", diams = "♦",
	},
	{
		__call = function(s, k)
			return self[k] or '&' .. k .. ';'
		end,
	}
)

return function(str)
	if not str then return '' end
	str = str:gsub("&#([x]?%x+);", function(n)
		n = tonumber(n) or tonumber(n:sub(2), 16)

		if(n < 128) then
			return string.char(n)
		elseif(n < 2048) then
			return string.char(192 + ((n - (n % 64)) / 64), 128 + (n % 64))
		elseif(n <= 65535) then
			return string.char(224 + ((n - (n % 4096)) / 4096), 128 + (((n % 4096) - (n % 64)) / 64), 128 + (n % 64))
		else
			return string.char(n / 262144 + 240,
			mod(n / 4096, 64) + 128,
			mod(n / 64, 64) + 128,
			mod(n, 64) + 128)
		end
	end)

	return (str:gsub("&(%w+);", entities))
end
