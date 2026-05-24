/ Resolve the matching src file relative to this test, not CWD.
.example.projectRoot: "/" sv -3 _ "/" vs $[":" = first f: string .utl.FILELOADING; 1 _ f; f];
system "l ", .example.projectRoot, "/src/tick/feed.q";
/ Test: Ticker Feed

.tst.desc["Ticker Feed"; {

  before {[]
    .feed.listeners: ();
  };

  should["track subscribers correctly"; {[]
    .feed.subscribe[100i];
    .feed.listeners mustmatch enlist 100i;
  }];

  should["generate trade data with expected schema"; {[]
    d: .feed.genTrade[];
    (cols d) mustmatch `time`sym`price`size;
  }];

  / Async test using .tst.wait
  should["wait for condition using async utilities"; {[]
    .tst.testTarget: .z.p + 50000000; / 50ms in future
    .tst.wait[{ .z.p > .tst.testTarget }; 200; 10];
    (.z.p > .tst.testTarget) musteq 1b;
  }];
  
}];
