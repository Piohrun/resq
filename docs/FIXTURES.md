# 🧩 Advanced Fixture Scopes & Hooks

Fixtures are the recommended way to manage test data and external resources (database connections, file handles). `resQ` introduces **Scopes** and **Lifecycle Hooks** to optimize test performance and resource cleanup.

## Scopes: `test` vs `session`

By default, every time a test asks for a fixture, it is freshly instantiated. This is the `test` scope.

- **`test` scope**: The fixture is created (and destroyed) for every single `should` block. Ideal for mutable data.
- **`session` scope**: The fixture is created **once** for the entire test session. Ideal for expensive resources like an HDB connection or a large read-only lookup table.

### Registering Scopes
```q
/ A session-level connection (Only opened once!)
.tst.registerFixture[`hdbConn; 0i; `scope`setup`teardown!(
    `session; 
    {hopen `:localhost:5000}; 
    {[h] hclose h}
 )];
```

## Lifecycle Hooks: `setup` & `teardown`

Hooks allow you to execute logic before and after a fixture is used.

- **`setup`**: Receives the raw fixture value and returns the "instantiated" value.
- **`teardown`**: Receives the instantiated value after the test completes for cleanup.

### Example: Temporary Files
```q
.tst.registerFixture[`tempFile; "temp.txt"; `setup`teardown!(
    {[f] hsym[`$f] 0: enlist "init"; f};
    {[f] system "rm ",f}
 )];

should["read from file"]{[tempFile]
  "init" mustmatch read0 hsym `$tempFile;
};
```

## Dependency Injection
You don't need to manually call `getFixture`. Just add the fixture name as an argument to your `should` block, and the framework will automatically inject it.

```q
should["test with injected fixture"]{[myFixture]
   myFixture musteq expected;
};
```

## Best Practices
- **Isolation**: Use `test` scope whenever possible to ensure tests remain independent.
- **Performance**: Use `session` scope for large data structures (>1GB) or slow external services to avoid redundant overhead.
- **Cleanup**: Always provide a `teardown` hook for any fixture that creates files or opens ports.
