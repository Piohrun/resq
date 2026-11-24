.tst.desc["Mocking"]{
 should["assign the given value to the named variable"]{
  `foo mock 0;
  foo musteq 0;
  };
 should["assign to a non-fully qualifeid name with respect to the current context"]{
  `.tst.context mock `.foo;
  `foo mock 3;
  .foo.foo musteq 3;
  };
 should["backup a variable if it already exists"]{
  `..foo set 0;
  `..foo mock 1;
  .tst.restore[];
  (get `..foo) musteq 0;
  delete foo from `.;
  };
 should["restore a legitimate dne-valued target instead of deleting it"]{
  .tst.testState.mockDneOriginal: `dne;
  `.tst.testState.mockDneOriginal mock 42;
  .tst.restore[];
  (get `.tst.testState.mockDneOriginal) musteq `dne;
  @[{![`.tst.testState;();0b;enlist x]}; `mockDneOriginal; {}];
  };
 should["restore values shaped like the old restore-error sentinel"]{
  original: (`restoreErr; "ordinary value");
  .tst.testState.mockRestoreTuple: original;
  `.tst.testState.mockRestoreTuple mock 42;
  .tst.restore[];
  (get `.tst.testState.mockRestoreTuple) musteq original;
  @[{![`.tst.testState;();0b;enlist x]}; `mockRestoreTuple; {}];
  };
 should["remove any variables that did not originally exist when all variables are restored"]{
  `foo mock 1;
  .tst.restore[];
  mustthrow["foo"] {get `foo};
  };
 should["refuse to mock a top level namespace"]{
  mustthrow[()] { `.tst mock ` };
  };
 should["support namespaces at top level that are just local variables"]{
  mustnotthrow[()] {`var.name mock 1};
  };
 };

/ A .z callback mocked while unset must be unset again afterwards. `key `.z`
/ does not list callbacks, so "unset" is observed as `get` signalling.
.tst.testState.zCallbackSet:{[name] @[{get x; 1b}; name; {[e] 0b}]};
.tst.desc["mocking an unset .z callback"]{
  should["install the handler for the test"]{
    must[not .tst.testState.zCallbackSet `.z.ps; "this test needs .z.ps unset beforehand"];
    `.z.ps mock {[x] x};
    must[.tst.testState.zCallbackSet `.z.ps; "the mock must be installed"];
  };
  should["leave it unset for the next test"]{
    must[not .tst.testState.zCallbackSet `.z.ps; "a mocked .z.ps must not outlive its test"];
  };
  should["restore a handler that was set"]{
    .z.ps: {[x] `original};
    .tst.registerCleanup[{system "x .z.ps"}; enlist (::)];
    `.z.ps mock {[x] `mocked};
    .tst.restore[];
    (.z.ps 1) musteq `original;
  };
 };

/ A view is `name::expression`. Mocked like a variable it came back as a
/ plain value and no longer followed what it was defined on. q keeps views in
/ the root namespace.
.tst.desc["mocking a view"]{
  before{
    here: system "d";
    system "d .";
    value "resqViewBase:10";
    value "resqViewDoubled::resqViewBase*2";
    system "d ", string here;
    .tst.registerCleanup[{[u] @[{![`.;();0b;x]}; `resqViewDoubled`resqViewBase; {[e] ::}]}; enlist (::)];
  };
  should["be refused with a message, and leave the view a view"]{
    .tst.isView[`resqViewDoubled] musteq 1b;
    .tst.isView[`resqViewBase] musteq 0b;
    / as a test loaded into the root namespace would call it
    saved: .tst.context;
    .tst.context: `.;
    outcome: @[{.tst.mock[`resqViewDoubled; 999]; "mocked"}; ::; {x}];
    .tst.context: saved;
    (outcome like "cannot mock the view resqViewDoubled*") musteq 1b;
    / the view is untouched and still follows its base
    @[`.; `resqViewBase; :; 50];
    here: system "d";
    system "d .";
    doubled: get `resqViewDoubled;
    system "d ", string here;
    doubled musteq 100;
  };
  should["mock an ordinary name in a namespace that does not exist yet"]{
    `.resqNoSuchNamespace.item mock 1;
    .resqNoSuchNamespace.item musteq 1;
  };
 };
