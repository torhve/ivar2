trim = (s) ->
  string.match s, '^%s*(.*%S)' or ''

-- the words we want to match
word = "[%wæøåÆØÅ]+"

-- These are the endings we don't approve
badends = { "'en", "'ene", "'et", "'ing", "'ar", "'ane" }

-- No [$|%s] in lua patterns so we just construct two patterns
patternends = { '$', '%s' }

-- Linestart exceptions
lineexceptions = { '^"', "^'", "^-", "^ %-" }

-- Construct all the patterns we need to check
patterns = {}
for wend in *badends
  for pend in *patternends
    table.insert patterns, word .. wend .. pend

-- Check every word against our bad patterns.
checkWord = (source, destination, line) =>
  -- First check for exceptions
  for pattern in *lineexceptions
    if line\match pattern
      -- Line is excepted. 
      return

  out = {}
  for pattern in *patterns
    for word in line\gmatch pattern
      table.insert out, trim(word)

  if #out > 0
    @Msg 'privmsg', destination, source, "Sylfest likar ikkje: %s", table.concat(out, ', ')

-- run our handler on any message that contains '
PRIVMSG:
  ".*'.*": checkWord
