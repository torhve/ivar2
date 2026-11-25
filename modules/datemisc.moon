date = require 'date' -- sudo luarocks install https://github.com/Tieske/date/raw/master/date-2.1.1-1.rockspec
idate = require 'idate'
os = require 'os'

fridayHandler = (s, d, a) =>
  d = date()\tolocal()
  wd = d\getisoweekday!
  wn = d\getisoweeknumber!
  if wd == 5
    say 'Ja!!! Fredag er her!'
  else
    time = d\setisoweekday(5)
    duration = date.diff(date(false), d)
    plural = ''
    dager = math.abs duration\spandays!
    if tonumber(dager) > 1
      plural = 'er'
    say "#{dager} dag#{plural} til fredag"

helgHandler = (s, d, a) =>
  d = date()\tolocal()
  wd = d\getisoweekday!
  wn = d\getisoweeknumber!
  if wd == 5 and d\gethours! >= 16
    say 'Ja!!! Helga er her!'
  else
    d\setisoweekday(5)
    d\sethours(16)
    duration = date.diff(d, date(false))
    dager = math.abs duration\spandays!
    minutt = math.abs duration\spanminutes!
    if tonumber(dager) > 1
      dager = "#{dager} dager "
    elseif dager == 1
      dager = "#{dager} dag "
    else
      dager = ""
    say "#{dager}#{minutt}m til helg."

PRIVMSG:
  '^%ppizza%?$': (source, destination, arg) =>
    d = date()\tolocal()
    wd = d\getisoweekday!
    wn = d\getisoweeknumber!
    if wd == 5 and wn%2 == 0
      reply 'Definitivt!'
    else
      reply 'Neppe. :('
  '^%pfriday%?$': fridayHandler
  '^%pfredag%?$': fridayHandler
  '^%phelg%?$': helgHandler
  '^%pweek$': =>
    d = date()\tolocal()
    say tostring d\getisoweeknumber!
  '^%pnonisoweek$': =>
    d = date()\tolocal()
    say tostring d\getweeknumber!
