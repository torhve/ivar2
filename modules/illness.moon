-- thanks to byte[] for sicknesses :-)

illnesses = {
  [[nany vgpuvat]],
  [[nany cnva]],
  [[nfgvtzngvfz]],
  [[onq oerngu]],
  [[oryyl ohggba qvfpunetr]],
  [[oyheerq ivfvba pnhfrf]],
  [[oyheel ivfvba]],
  [[oyheel ivfvba]],
  [[objry vapbagvarapr]],
  [[pbyq fberf]],
  [[pbafgvcngvba]],
  [[peno yvpr]],
  [[qnaqehss]],
  [[qvfrnfrf bs gur rlr]],
  [[rwnphyngvba]],
  [[rerpgvba ceboyrzf]],
  [[rlr pbaqvgvbaf]],
  [[rlr qvfrnfrf]],
  [[rlr rkrepvfrf]],
  [[rlr synfurf]],
  [[rlr sybngref]],
  [[rlr urnygu]],
  [[rlr erqarff]],
  [[rlr fgenva flzcgbzf]],
  [[rlr ivfvba]],
  [[rlr ivgnzvaf]],
  [[srpny vapbagvarapr]],
  [[svffher]],
  [[synxl fxva]],
  [[sybngref va gur rlr]],
  [[travgny jnegf]],
  [[tynhpbzn flzcgbzf]],
  [[unve ybff]],
  [[urnq yvpr]],
  [[urzzbeubvqf]],
  [[uvpphcf]],
  [[ubj gb vzcebir rlrfvtug]],
  [[vagenbphyne cerffher]],
  [[veevgnoyr objry flaqebzr]],
  [[vgpuvat]],
  [[wbpx vgpu]],
  [[ynfre rlr fhetrel]],
  [[ynfre fhetrel sbe rlrf]],
  [[ynfvx]],
  [[ynfvx rlr fhetrel]],
  [[ynfvx fhetrel pbfg]],
  [[zna obbof]],
  [[zrzbel ceboyrzf]],
  [[zrabcnhfr]],
  [[zbhgu hypref]],
  [[anvy ovgvat]],
  [[beny frk]],
  [[birejrvtug]],
  [[cvyrf]],
  [[cbylcunfvp fyrrc]],
  [[cbea nqqvpgvba]],
  [[cerzrafgehny flaqebzr]],
  [[erq snpr]],
  [[erfgyrff yrtf]],
  [[ergvany qrgnpuzrag]],
  [[fpnyl fxva]],
  [[fpnef]],
  [[funxl unaqf]],
  [[fzryyl srrg]],
  [[fabevat]],
  [[fgnzzrevat]],
  [[fgergpu znexf]],
  [[fjrngvat]],
  [[gbranvy vasrpgvba]],
  [[gbathr ceboyrzf]],
  [[hevanel vapbagvarapr]],
  [[inevpbfr irvaf]],
  [[ireehpnf]],
  [[ivfvba gurencl]],
  [[jvaq]],
  [[travgny tnaterar]],
  [[ubezbany vzonynapr]]
  [[urecrf]]
}

illness = ->
  ivar2.util.rot13(illnesses[math.random(1, #illnesses)])

PRIVMSG:
  '^%pillness (.+)$': (s, d, nick) =>
    say "#{nick}, afflicted by #{illness!}"
  '^%pillness$': (s, d) =>
    say illness!
 
