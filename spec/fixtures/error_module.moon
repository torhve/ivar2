boom_var = nil

boom = ->
  boom_var()

more_code = ->
  another_error_func = ->
    error("runtime boom")
  another_error_func()

nested = ->
  inner = ->
    deep_inner = ->
      error("deep error")
    deep_inner()
  inner()

PRIVMSG:
  '!boom': (s, d, a) =>
    boom()
  '!nested': (s, d, a) =>
    nested()
  '!more': (s, d, a) =>
    more_code()
