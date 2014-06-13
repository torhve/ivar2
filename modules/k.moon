-- k, reimplemented from dbot's k by byte[]
history = {}

PRIVMSG: {
  '^%pk$': (source, destination) =>
    t = {}
    max = 5
    for i = 1, max
      h = history[destination][math.random(#history[destination])]
      msg = h
      want = math.random(2, 4)
      getting = false
      msg = msg\gsub("\003%d?%d?,?%d?%d?", "")
      for w in msg\gmatch("[%w%[%]%{%}%|`%^_%-%|'\194-\244\128-\191]+") do
        if w == "http" or w == "https"
          break
        if not getting
          -- Skip k itself
          if w == 'k'
            continue
          -- Less odds if not starting with letter.
          if w\find("^[%a']") or math.random(2) == 1
            if math.random(1, max + i + 1) <= i
              getting = true
        if getting
          if want > 0
            t[#t + 1] = w\lower()
          else
            break
          want = want - 1
    outline = table.concat(t, " ")
    say outline
  (source, destination, argument) =>
    unless history[destination]
      history[destination] = {}
    table.insert history[destination], #history[destination]+1, argument
    if #history[destination] > 20
      table.remove history[destination], 1
}
