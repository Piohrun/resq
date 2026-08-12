/ This suite deliberately remains qspec-shaped and unqualified. Its application
/ sources use the same spellings as the DSL and must still load unchanged.
system "l ",.resq.HOME,"/tests/compat/application/src/order.q";
\l tests/compat/application/src/gateway.q

describe["production application compatibility"]{
  should["load documented namespaced source with common local names"]{
    rows:([]time:10:00 10:05;amount:20 30f);
    summary:.order.summarize rows;
    summary[`elapsed] musteq 00:05;
    summary[`total] musteq 50f;
    .order.settle[100f] musteq 101f;
  };

  should["load a second source through native load syntax"]{
    .gateway.route[4 5] musteq 18;
  };

  should["allow a test local to share an expectation alias"]{
    it:10 20 30;
    it[1] musteq 20;
  };
};

::
