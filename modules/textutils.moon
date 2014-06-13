
PRIVMSG:
  '^%pupper (.+)$': (source, destination, arg) =>
    say arg\upper!
  '^%plower (.+)$': (source, destination, arg) =>
    say arg\lower!
  '^%preverse (.+)$': (source, destination, arg) =>
    say arg\reverse!
  '^%plen (.+)$': (source, destination, arg) =>
    say tostring(arg\len!)
  '^%pnicks$': (source, destination) =>
    say table.concat([n for n,k in pairs(ivar2.channels[destination].nicks)], ' ')
  '^%prandom (.+)$': (source, destination, arg) =>
    words = [word for word in arg\gmatch('%S+')]
    say words[math.random(1, #words)]
