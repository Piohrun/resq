system "l examples/quickstart/src/gateway/auth.q";
/ Test: Auth Gateway

.tst.desc["Auth Gateway"; {

  / Fixtures for dependency injection showcase
  before {[]
    .tst.registerFixture[`adminUser; `admin];
    .tst.registerFixture[`guestUser; `user];
  };

  / Dependency Injection: adminUser is injected from fixture
  should["allow admin actions for admin users"; {[adminUser]
    .perm.check[adminUser; `admin] musteq 1b;
  }];

  / Dependency Injection: guestUser is injected
  should["deny admin actions for guest users"; {[guestUser]
    .perm.check[guestUser; `admin] musteq 0b;
    .perm.check[guestUser; `read] musteq 1b;
  }];
  
  / Standard test without injection
  should["verify shutdown requires admin"; {[]
    / admin can shutdown
    .perm.shutdown[`admin] musteq 1b;
  }];

}];
