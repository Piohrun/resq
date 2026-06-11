/ Golden fixture: should (pass) + skip + pending in ONE desc block.
.tst.desc["skip mix"]{
  should["runs"]{ musteq[1; 1] };
  skip["not ready"]{ musteq[1; 2] };
  pending["todo later"];
 };
