/ Comprehensive Test Suite for User Service";
/ Showcases: Mocking, Spies, Parameterization, Coverage Tracking

system "l examples/quickstart/src/user/service.q";

.tst.desc["User Management Service"]{
  before{
    / Reset user database
    `.user.users set ([id:`int$()] name:`symbol$(); email:`symbol$(); role:`symbol$(); active:`boolean$());
    / Clear spy logs
    .tst.clearSpyLogs[];
  };

  / === PHASE 1: Advanced Mocking & Spies ===
  should["create user and verify logging spy"]{
    / Spy on logEvent to verify it's called
    .tst.spy[`.user.logEvent; (::)];
    
    userId: .user.create[`alice; `$"alice@example.com"; `user];
    userId musteq 1;
    
    / Verify logEvent was called with correct params
    `.user.logEvent mustHaveBeenCalledWith (`userCreated; 1);
  };

  should["mock external logging to prevent side effects"]{
    / Mock logEvent to do nothing
    .tst.mock[`.user.logEvent; {[x;y] (`mocked; x; y)}];
    
    userId: .user.create[`bob; `$"bob@test.com"; `admin];
    / Should succeed without actual logging
    userId mustgt 0;
  };

  / === PHASE 2: Combinatorial Parameterization ===
  should["validate user creation with various roles"]{
    / Test all combinations of valid inputs
    .tst.parametrize[`name`role!(`alice`bob`charlie; `admin`user`guest); {[name;role]
      userId: .user.create[name; `$string[name],"@test.com"; role];
      userId mustgt 0;
      user: .user.findById[userId];
      user[`role] musteq role;
    }];
  };

  should["reject invalid roles"]{
    code: { .user.create[`test; `$"test@test.com"; `invalidRole] };
    mustthrow["*Invalid role*"; code];
  };

  / === Basic Functionality Tests ===
  should["find user by ID"]{
    id: .user.create[`dave; `$"dave@test.com"; `user];
    user: .user.findById[id];
    user[`name] musteq `dave;
    user[`email] musteq `$"dave@test.com";
  };

  should["update user role"]{
    id: .user.create[`eve; `$"eve@test.com"; `user];
    .user.updateRole[id; `admin];
    user: .user.findById[id];
    user[`role] musteq `admin;
  };

  should["deactivate user"]{
    id: .user.create[`frank; `$"frank@test.com"; `guest];
    .user.deactivate[id];
    user: .user.findById[id];
    user[`active] musteq 0b;
  };

  should["get active users only"]{
    `.user.users set ([id:`int$()] name:`symbol$(); email:`symbol$(); role:`symbol$(); active:`boolean$());
    id1: .user.create[`user1; `$"u1@test.com"; `user];
    id2: .user.create[`user2; `$"u2@test.com"; `user];
    .user.deactivate[id1];
    
    active: .user.getActive[];
    count[active] musteq 1;
    first[(key active)`id] musteq id2;
  };
}
