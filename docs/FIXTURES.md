# Advanced Fixture Scopes and Hooks

Fixtures are the recommended way to manage test data and external resources
such as database connections and file handles. resQ provides scopes and
lifecycle hooks to control reuse and cleanup.

## Scopes: `test` vs `session`

By default, every time a test asks for a fixture, it is freshly instantiated. This is the `test` scope.

- **`test` scope**: The fixture is created (and destroyed) for every single `should` block. Ideal for mutable data.
- **`session` scope**: The fixture is created **once** for the entire test
  session. Use it for expensive resources that can be shared safely, such as a
  read-only lookup table or dedicated test connection.

### Registering Scopes
```q
/ A session-level connection (Only opened once!)
/ registerFixture takes exactly 2 args (name; value). To add lifecycle options,
/ use registerFixtureWithOpts (name; value; opts-dict).
.tst.registerFixtureWithOpts[`hdbConn; 0i;
    `scope`setup`teardown!(
        `session;
        {[h] hopen `:localhost:5000};
        {[h] hclose h}
    )
];
```

## Lifecycle Hooks: `setup` & `teardown`

Hooks allow you to execute logic before and after a fixture is used.

- **`setup`**: Receives the raw fixture value and returns the "instantiated" value.
- **`teardown`**: Receives the instantiated value after the test completes for cleanup.

A teardown that throws is recorded as a structured test error and fails the
run. resQ still attempts the remaining teardown and cleanup callbacks so one
failure does not hide later resource problems.

### Example: Temporary Files
```q
/ Use registerFixtureWithOpts for the 3-arg (name; value; opts) form.
.tst.registerFixtureWithOpts[`tempFile; "temp.txt";
    `setup`teardown!(
        {[f] hsym[`$f] 0: enlist "init"; f};
        {[f] @[hdel; hsym `$f; {}]}
    )
];

should["read from file"]{[tempFile]
  "init" mustmatch read0 hsym `$tempFile;
};
```

## Dependency Injection
You do not need to call `getFixture` manually. Add the fixture name as an
argument to the `should` block and resQ injects it.

```q
should["test with injected fixture"]{[myFixture]
   myFixture musteq expected;
};
```

## Best Practices
- **Isolation**: Use `test` scope whenever possible to ensure tests remain independent.
- **Performance**: Use `session` scope only when setup cost matters and the
  value is safe to share between tests.
- **Cleanup**: Always provide a `teardown` hook for any fixture that creates files or opens ports.

For expectation- or suite-specific cleanup callbacks, see
[`registerCleanup` / `registerSpecCleanup`](API_REFERENCE.md#registercleanup--registerspeccleanup).
