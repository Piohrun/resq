
.tst.desc["Fixture Injection"; {

  before {
    / Register a fixture
    .tst.registerFixture[`userMock; `name`id!(`Alice; 1001)];
    / Every test gets them: the one that takes `a` and `b` used to rely on
    / the test before it having registered them, which holds only in
    / declaration order (not under -random-order).
    .tst.registerFixture[`a; 10];
    .tst.registerFixture[`b; 20];
  };

  should["inject fixture by name"; {[userMock]
    userMock[`name] musteq `Alice;
    userMock[`id] musteq 1001;
  }];

  should["inject multiple fixtures"; {[]
    must[all `a`b in key .tst.fixtures; "both fixtures must be registered"];
  }];
  
  should["work with multiple args"; {[a;b]
    (a+b) musteq 30;
  }];
  
}];
