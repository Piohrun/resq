.tst.desc["controlled flake fixture"]{
  should["uses the external pass marker"]{
    (first getenv `RESQ_FLAKE_PASS) musteq first "1";
  };
 };
::
