/ Golden fixture: desc/should titles with XML specials and a quote, plus a
/ failing musteq comparing strings so the message lands in the report.
.tst.desc["nasty <&> title with \" quote"]{
  should["should <&> with \" quote"]{ musteq["abc"; "xyz"] };
 };
