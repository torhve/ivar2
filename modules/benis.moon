-- code from q66's module from luabot ported from rfs benis module
reduce = (fun, list, def) ->
  for k, v in ipairs(list)
    def = fun(def, v)
  return def

rand = math.random
tconc = table.concat

benisify = (s) ->
  reduce (acc, f) -> 
    f(acc),
    {
      (s) -> s\lower()
      (s) -> s\gsub('x', 'cks')
      (s) -> s\gsub('ing', 'in')
      (s) -> s\gsub('you', 'u')
      (s) -> s\gsub 'oo', ->
        ('u')\rep(rand(1, 5))
      (s) -> 
        s\gsub '[%w_]%z', (x) ->
          x\sub(1, 1)\rep(rand(1, 2))
      (s) -> 
        s\gsub 'ck', ->
          'g'\rep(rand(1, 5))
      (s) -> 
        s\gsub '(t+)%f[aeiouys ]', (x) ->
          ('d')\rep(#x)
      (s) -> 
        s\gsub '(t+)$', (x) ->
          ('d')\rep(#x)
      (s) -> s\gsub('p', 'b'),
      (s) -> s\gsub('%f[%w_]the%f[^%w_]', 'da'),
      (s) -> s\gsub('%f[%w_]c', 'g'),
      (s) -> s\gsub('%f[%w_]is%f[^%w_]', 'are'),
      (s) -> s\gsub '(c+)(.)', (x, y) ->
        (y == 'e' or y == 'i' or y == 'y') and (x .. y) or ('g')\rep(rand(1, 5)) ..  (y == 'c' and 'g' or y)
      (s) -> 
        s\gsub '([qk]+)%f[aeiouy ]', ->
          ('g')\rep(rand(1, 5))
      (s) -> 
        s\gsub '([qk]+)$', ->
          ('g')\rep(rand(1, 5))
      (s) ->
          endswith = s\find '[?!.]$'
          repf = (x) ->
              ret = x\rep(rand(2, 5)) .. ' '
              for i = 1, rand(2, 5)
                  ret = ret .. (':')\rep(rand(1, 2)) .. ('D')\rep(rand(1, 4))
              return ret
          unless endswith then return s\gsub('$', repf)
          s\gsub('[?!.]+', repf)
    }, s

PRIVMSG:
  '^%pbenis (.*)$':(source, destination, arg) =>
    say(benisify(arg))

