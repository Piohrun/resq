.tst.desc["Loading Text Fixtures"]{
 before{
  fix: ` sv (-1 _ ` vs .tst.tstPath),`fixtures`all_types.csv;
  `typeLine mock ssr[(read0 fix) 0;",";""];
  };
 should["load text based fixtures with different path separators"]{
  fixture[`fixtureCommas];
  fixture[`fixturePipes];
  fixture[`fixtureCarets];
  fixtureCommas mustmatch fixturePipes;
  fixtureCommas mustmatch fixtureCarets;
  };
 should["determine the types of the fixture's columns from the type-line"]{
  fixtureAs[`all_types;`allTypes];
  nullTypes: typeLine$" ";
  nullTypes mustmatch value first allTypes;
  };
 };
