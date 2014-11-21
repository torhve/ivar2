-- Ported from hubot which sites this source:
-- http://www.macmillandictionary.com/thesaurus-category/british/Ways-of-accepting-someone-s-thanks

response = {
  "you're welcome",
  "no problem",
  "not at all",
  "don’t mention it",
  "it’s no bother",
  "it’s my pleasure",
  "my pleasure",
  "it’s all right",
  "it’s nothing",
  "think nothing of it",
  "sure",
  "sure thing"
}

answer = (s, d, a) =>
  reply response[math.random(#response)]

PRIVMSG:
  "#{ivar2.config.nick}.-takk": answer
  "#{ivar2.config.nick}.-thank": answer
  "takk.-#{ivar2.config.nick}": answer
  "thanks.-#{ivar2.config.nick}": answer
