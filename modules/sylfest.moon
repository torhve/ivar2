lpeg = require 'lpeg'
import match, locale, P, R, V, S, Ct, C, Cg, Cf, Cc, Cp from lpeg
import concat from table

-- Helper for searching anywhere in string for patterns
anywhere = (p) ->
  P{ p + 1 * V(1) }
-- Helper for maybe pattern
maybe = (p) -> p^-1
-- Match norwegian words
word = R('az') + R('AZ') + S('æøåÆØÅ')
-- With an '
apo = P "'"
-- With bad endings
bend = P("ene") + P("en") + P("et") + P("ing") + P("ar") + P("ane") + P("er")
-- Separated by or line end
wend = S(',.? ') + P(-1)
-- Linestart exceptions
bstart = maybe(P(' ')) * S[["'-]]

-- Capture word with bad endings followed by good word end
sylfestpatt = C(word^1 * apo * bend) * P(wend)
-- Search anywhere in string, capture all sylfestwords, do not match if line starts with excepted linestarts
fullpatt = Ct(anywhere(sylfestpatt)^1 - bstart)

-- run our handler on any message that contains '
PRIVMSG:
  ".*'.*": (source, destination, line) =>
    matches = fullpatt\match(line)
    if matches
      say "Sylfest likar ikkje: %s", concat(matches, ', ')


