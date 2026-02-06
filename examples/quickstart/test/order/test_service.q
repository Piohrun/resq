oldFL: @[get; `.utl.FILELOADING; {::}];
if[`FILELOADING in key `.utl; .utl.FILELOADING: ::];
system "l examples/quickstart/src/order/service.q";
if[not oldFL ~ (::); .utl.FILELOADING: oldFL];
/ Comprehensive Test Suite for Order Service
/ Showcases: Async Testing, Mock Sequences, Partial Mocks

.tst.desc["Order Processing Service"]{
  before{
    / Reset order database
    `.order.orders set ([id:`long$()] userId:`long$(); items:(); totalAmount:`float$(); status:`symbol$(); createdAt:`timestamp$());
  };

  / === PHASE 1: Mock Sequences ===
  should["handle sequential price tier lookups"]{
    / Mock getUserTier to return different values on consecutive calls
    .tst.mockSequence[`.order.getUserTier; (`standard; `premium; `vip)];
    
    / Mock payment processing to avoid async complexity
    .tst.mock[`.order.processPaymentAsync; {[x;y] ()}];
    
    / Create three orders - each should get different pricing
    items: ((`item1; 2; 10.0); (`item2; 1; 20.0));
    
    id1: .order.create[1; items];  / standard: 40.0 * 1.0 = 40.0
    id2: .order.create[2; items];  / premium: 40.0 * 0.9 = 36.0
    id3: .order.create[3; items];  / vip: 40.0 * 0.8 = 32.0
    
    .order.orders[id1;`totalAmount] musteq 40.0;
    .order.orders[id2;`totalAmount] musteq 36.0;
    .order.orders[id3;`totalAmount] musteq 32.0;
  };

  / === PHASE 1: Partial Mocks ===
  should["use partial mock for pricing overrides"]{
    / Override only VIP pricing, keep others unchanged
    .tst.partialMock[`.order.pricing; enlist[`vip]!enlist 0.7];
    
    / Mock external calls
    .tst.mock[`.order.getUserTier; {[x] `vip}];
    .tst.mock[`.order.processPaymentAsync; {[x;y] ()}];
    
    items: enlist (`item; 1; 100.0);
    id: .order.create[1; items];
    
    / Should use new VIP discount of 0.7
    .order.orders[id;`totalAmount] musteq 70.0;
  };

  / === PHASE 3: Async Testing with Deferred ===
  should["handle async payment callback"]{
    / Create deferred for async payment
    .tst.paymentDeferred:: .tst.deferred[];
    
    / Mock async payment to resolve deferred
    .tst.mock[`.order.processPaymentAsync; {[oid;amt]
      / Simulate async operation completing
      .tst.resolve[.tst.paymentDeferred; (`success; oid)];
    }];
    
    / Create order
    .tst.mock[`.order.getUserTier; {[x] `standard}];
    items: enlist (`item; 1; 50.0);
    id: .order.create[1; items];
    
    / Wait for payment to process
    result: .tst.await[.tst.paymentDeferred; 1000];
    result[0] musteq `success;
    result[1] musteq id;
  };

  / === PHASE 2: Parameterized Pricing Tests ===
  should["calculate correct totals for all tier combinations"]{
    .tst.mock[`.order.processPaymentAsync; {[x;y] ()}];
    
    / Test all pricing tiers (zipped scenarios)
    cases: ([] tier:`standard`premium`vip; basePrice: 100 100 100; expected: 100.0 90.0 80.0);
    .tst.forall[cases; {[tier;basePrice;expected]
      .tst.currentTier:: tier;
      .tst.mock[`.order.getUserTier; {[x] .tst.currentTier}];
      items: enlist (`item; 1; basePrice);
      id: .order.create[1; items];
      .order.orders[id;`totalAmount] musteq expected;
    }];
  };

  / === Basic Tests ===
  should["find order by ID"]{
    .tst.mock[`.order.getUserTier; {[x] `standard}];
    .tst.mock[`.order.processPaymentAsync; {[x;y] ()}];
    
    items: enlist (`item; 2; 25.0);
    id: .order.create[1; items];
    
    order: .order.findById[id];
    order[`userId] musteq 1;
    order[`totalAmount] musteq 50.0;
  };

  should["update order status via payment callback"]{
    .tst.mock[`.order.getUserTier; {[x] `standard}];
    .tst.mock[`.order.processPaymentAsync; {[x;y] ()}];
    .tst.mock[`.order.notifyUser; {[x;y] ()}];
    
    items: enlist (`item; 1; 10.0);
    id: .order.create[1; items];
    
    / Simulate payment success
    .order.paymentCallback[id; `success; "TXN123"];
    
    order: .order.findById[id];
    order[`status] musteq `completed;
  };
}
