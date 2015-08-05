-- a port of https://github.com/LizardGamer/tumblr-argument-generator/blob/develop/app/assets/js/main.js
-- original by Lokaltog
-- github pls no delete

util = require'util'
html2unicode = require'html'
simplehttp = util.simplehttp

intro = {
  'burn in hell',
  'check your privilege',
  'fuck you',
  'fuck off',
  'please die',
  'rot in hell',
  'screw you',
  'shut the fuck up',
  'shut up',
  'kill yourself',
  'drop dead'
}
description = {
  'deluded',
  'fucking',
  'god damn',
  'judgemental',
  'worthless'
}
marginalized = {
  {
    'activist',
    'agender',
    'appearance',
    'asian',
    'attractive',
    'bi',
    'bigender',
    'black',
    'celestial',
    'chubby',
    'closet',
    'color',
    'curvy',
    'dandy',
    'deathfat',
    'demi',
    'differently abled',
    'disabled',
    'diversity',
    'dysphoria',
    'ethnic',
    'ethnicity',
    'fat love',
    'fat',
    'fatist',
    'fatty',
    'female',
    'feminist',
    'genderfuck',
    'genderless',
    'hair',
    'height',
    'indigenous',
    'intersectionality',
    'invisible',
    'kin',
    'lesbianism',
    'little person',
    'marginalized',
    'minority',
    'multigender',
    'non-gender',
    'non-white',
    'obesity',
    'otherkin',
    'pansexual',
    'polygender',
    'privilege',
    'prosthetic',
    'queer',
    'radfem',
    'skinny',
    'smallfat',
    'stretchmark',
    'thin',
    'third-gender',
    'trans*',
    'transfat',
    'transgender',
    'transman',
    'transwoman',
    'trigger',
    'two-spirit',
    'womyn',
    'poc',
    'woc'
  },
  {
    'chauvinistic',
    'misogynistic',
    'nphobic',
    'oppressive',
    'phobic',
    'shaming',
    'denying',
    'discriminating',
    'hypersexualizing',
    'intolerant',
    'racist',
    'sexualizing'
  }
}
privileged = {
  {
    'able-bodied',
    'appearance',
    'attractive',
    'binary',
    'bi',
    'cis',
    'cisgender',
    'cishet',
    'hetero',
    'male',
    'smallfat',
    'thin',
    'white'
  },
  {
    'ableist',
    'classist',
    'normative',
    'overprivileged',
    'patriarch',
    'sexist',
    'privileged'
  }
}
finisher = {
  'asshole',
  'bigot',
  'oppressor',
  'piece of shit',
  'rapist',
  'scum',
  'shitlord',
  'subhuman',
  'misogynist',
  'nazi'
}

getRandomItem = (array) ->
  array[math.random(1, #array)]

generateTerm = ->
  getRandomItem({
    'a',
    'bi',
    'dandy',
    'demi',
    'gender',
    'multi',
    'pan',
    'poly'
  }) .. getRandomItem({
    'amorous',
    'femme',
    'fluid',
    'queer',
    'romantic',
    'sexual',
  })

generateArgument = ->
  buf = {
    getRandomItem(intro),
    ', you ',
    getRandomItem(description),
    ' ',
    getRandomItem({
      generateTerm(),
      getRandomItem(marginalized[1])
    }),
    '-',
    getRandomItem(marginalized[2]),
    ', ',
    getRandomItem(privileged[1]),
    '-',
    getRandomItem(privileged[2]),
    ' ',
    getRandomItem(finisher),
    '.',
  }
  table.concat(buf)

martinLutherInsult = (source, destination, arg) =>
  simplehttp 'http://ergofabulous.org/luther/', (data) ->
    insult = data\match '<p class="larger">(.-)</p>'
    if insult
      say arg..": "..insult

shaker = (source, destination, arg) =>
  simplehttp 'http://www.pangloss.com/seidel/Shaker/', (data) ->
    insult = data\match '<font size="%+2">%s*(.-)</font>'
    if insult
      say arg..": "..insult


PRIVMSG:
  '^%pinsult$': (source, destination) =>
    say generateArgument()
  '^%pinsult (.+)$': (source, destination, arg) =>
    say arg..": "..generateArgument()
  '^%pminsult (.+)$': martinLutherInsult
  '^%psinsult (.+)$': shaker
