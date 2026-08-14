# Async and Promises

Polling-only helpers for testing callbacks, deferred results, and state that is
already able to change while the test body is running.

These are polling-only test helpers, not real asynchronous execution support.
q is single-threaded, and each helper stays inside the current q call. Its
blocking sleep does not yield to q's event loop, dispatch IPC callbacks, or let
ordinary timer callbacks run. `waitEx[...,1b]` explicitly calls `.z.ts[]`
between polls, but that heartbeat is only a direct timer-hook invocation; it
does not dispatch IPC or create a general event loop.

Use these helpers when the callback is invoked synchronously by code under
test, another call has already settled the deferred, observable state changes
without event-loop progress, or a `waitEx` timer heartbeat is deliberately
sufficient. Do not call `await` or `eventually` and expect a future timer or IPC
message in the same q process to resolve them—the polling call prevents that
work from being dispatched.

Everything lives in `.tst` and is loaded by default — no `require` needed.

---

## Quick reference

| Function | Purpose |
|----------|---------|
| `.tst.deferred[]` | Create a pending deferred; returns an opaque long handle |
| `.tst.resolve[id; value]` | Settle it successfully |
| `.tst.reject[id; reason]` | Settle it as failed |
| `.tst.await[id; timeoutMs]` | Block until settled; return the value or throw the reason |
| `.tst.isSettled[id]` | Has it settled yet? |
| `.tst.getState[id]` | Full state: `` `state`val`err `` |
| `.tst.until[cond]` | Poll until true — 1s timeout, 100ms interval |
| `.tst.wait[cond; timeoutMs; intervalMs]` | Poll with explicit timings |
| `.tst.waitEx[cond; timeoutMs; intervalMs; heartbeat]` | As above, optionally firing `.z.ts` |
| `.tst.eventually[cond; timeoutMs; intervalMs]` | Poll, treating a *throwing* condition as "not yet" |
| `.tst.sleep[ms]` | Busy-wait for `ms` milliseconds |
| `.tst.callbackSpy[name]` | A callback that records every invocation |
| `.tst.getCallbackCalls[name]` | Recorded invocations as `(timestamp; args)` pairs |
| `.tst.clearCallbackLogs[]` | Drop all recorded invocations |

---

## Deferreds

A deferred is a named slot that is `pending` until something settles it. The
opaque long handle can be captured in a closure or stashed in a global without
interning a new q symbol for every operation.

```q
should["complete the order once payment confirms"]{
    d: .tst.deferred[];

    / Code under test calls back when it finishes.
    `.gateway.onPaid mock {[txn] .tst.resolve[.tst.testState.d; txn]};
    .tst.testState.d: d;
    .order.submit 42;

    (.tst.await[d; 1000]) musteq "TXN-42";
};
```

### Settling

`resolve` and `reject` both settle. A deferred can only settle **once** —
settling an already-settled deferred throws `Promise already settled`, and
settling an unknown id throws `Unknown deferred`.

`await` consumes the settled registry entry before it returns or rethrows. Any
abandoned pending entries are cleared at the end of every run, including each
watch rerun, so a long-lived process retains bounded state. Legacy `` `def_N ``
handles remain accepted at API boundaries; use
`.tst.legacyDeferredHandle[id]` only when an integration explicitly requires
the old printable spelling.

```q
d: .tst.deferred[];
.tst.resolve[d; 42];
.tst.resolve[d; 43];      / throws: Promise already settled
```

### Awaiting

`await` polls until the deferred settles, then either returns the value or
throws the rejection reason:

```q
d: .tst.deferred[];
.tst.reject[d; "gateway unreachable"];
mustthrow["*gateway unreachable*"; (.tst.await; d; 1000)];
```

The reason may be a string or a symbol; both surface as the thrown message.
Pass `0N` as the timeout to use the default of **5000ms**. On timeout `await`
throws `Eventually timed out after <n>ms`.

### Inspecting without waiting

`isSettled` is the non-throwing check — it returns `0b` for an id that does not
exist, rather than signalling:

```q
.tst.isSettled d;          / 0b while pending
.tst.isSettled `nosuch;    / 0b — unknown ids are simply "not settled"
```

`getState` returns the whole record and **does** throw on an unknown id:

```q
.tst.resolve[d; 7];
s: .tst.getState d;        / columns: state, val, err
(first s`state) musteq `resolved;
```

---

## Polling for a condition

When there is no deferred to hang onto — the code under test just mutates
something — poll for the state you expect.

```q
should["flush the buffer within a second"]{
    .feed.start[];
    must[.tst.until {0 = count .feed.buffer}; "buffer should drain"];
};
```

`until` is the common case: **1000ms timeout, 100ms interval**, both fixed. Use
`wait` when you need to choose them:

```q
must[.tst.wait[{0 = count .feed.buffer}; 5000; 50]; "buffer should drain"];
```

The condition may be written either way — `{...}` with an implicit argument, or
an explicit niladic `{[] ...}`. Both work.

**On timeout these throw, they do not return `0b`.** So a bare call already
fails the test with a clear message; wrapping it in `must` only adds your own
wording:

```q
.tst.wait[{0b}; 60; 20];   / throws: wait timeout: condition not met in 60ms
```

### `waitEx` and heartbeats

If the code under test relies only on direct `.z.ts` work, the polling loop can
invoke that hook explicitly:

```q
.tst.waitEx[{.feed.ticks > 3}; 2000; 100; 1b];   / 1b => call .z.ts each interval
```

`wait[cond; t; i]` is exactly `waitEx[cond; t; i; 0b]`.

### `eventually` — when the condition itself throws

`eventually` differs from `wait` in one important way: **a condition that throws
is treated as "not true yet"**, and polling continues.

```q
/ Keeps polling while the table does not exist yet, succeeds once it does.
.tst.eventually[{0 < count .db.trades}; 2000; 50];
```

That is what you want when the thing you are checking is not merely false but
not yet *reachable*. The cost is that a genuine bug in the condition looks
identical to "not ready" — it polls to the timeout and reports
`Eventually timed out after <n>ms` with no mention of the underlying error.
When the condition can be evaluated safely, prefer `wait`, whose failure is
immediate and specific.

Pass `0N` for either timing to take the defaults: **5000ms timeout, 100ms
interval**.

---

## Callback spies

`callbackSpy` returns a one-argument function that records each call and returns
its argument unchanged, so it can stand in for a real callback:

```q
should["notify the user once per filled order"]{
    .tst.clearCallbackLogs[];
    `.order.notifyUser mock .tst.callbackSpy `notify;

    .order.fill 1;
    .order.fill 2;

    (count .tst.getCallbackCalls `notify) musteq 2;
};
```

Each recorded entry is a `(timestamp; args)` pair, so you can assert on ordering
or on what was passed:

```q
calls: .tst.getCallbackCalls `notify;
(last first calls) musteq 1;        / args of the first call
```

`getCallbackCalls` returns `()` for a name that was never spied on.

Logs are **global and not reset between tests** — call `.tst.clearCallbackLogs[]`
in the test or a `before` block, as above.

---

## `sleep` is a busy-wait

```q
.tst.sleep 250;    / spins for 250ms
```

`.tst.sleep` does not yield the process — it spins on `.z.p` until the deadline,
burning a core. It cannot service q timers or IPC. That is deliberate: it keeps
the timing predictable and avoids forking, which matters inside a test runner.
But it means the polling helpers above also burn CPU while they wait, so prefer
short intervals with a realistic timeout over long sleeps, and do not use
`sleep` as a substitute for an external event loop.

---

## Choosing between them

| Situation | Use |
|-----------|-----|
| The code under test hands you a completion callback | `deferred` + `resolve` + `await` |
| You need to assert a callback fired, and with what | `callbackSpy` |
| Some observable state becomes true shortly | `until` / `wait` |
| The check itself may throw until the system is ready | `eventually` |
| You genuinely need to pause | `sleep` — sparingly |
