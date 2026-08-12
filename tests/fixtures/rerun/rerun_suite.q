.tst.desc["rerun suite"]{
  should["first passes"]{1 musteq 1};
  should["previously failing"]{
    marker:getenv `RESQ_RERUN_MARKER;
    must[.utl.pathExists marker;"marker deliberately absent"];
  };
  should["third passes"]{3 musteq 3};
 };
