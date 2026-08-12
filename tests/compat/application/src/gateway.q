\d .gateway

/ A second ordinary application namespace exercises names that also happen to
/ be suite and fixture verbs. Plain q loads this file without resQ involvement.
route:{[payload]
  should:first payload;
  fixture:last payload;
  beforeAll:should+fixture;
  afterAll:beforeAll*2;
  afterAll
 };

\d .
