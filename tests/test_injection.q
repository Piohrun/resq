
.tst.desc["Fixture Injection"; {

  before {
    / Register a fixture
    .tst.registerFixture[`userMock; `name`id!(`Alice; 1001)];
  };

  should["inject fixture by name"; {[userMock]
    userMock[`name] musteq `Alice;
    userMock[`id] musteq 1001;
  }];

  should["inject multiple fixtures"; {[]
    .tst.registerFixture[`a; 10];
    .tst.registerFixture[`b; 20];
  }];
  
  should["work with multiple args"; {[a;b]
    (a+b) musteq 30;
  }];
  
}];
