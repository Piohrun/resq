# Property-Based Testing (PBT)

Property-Based Testing (PBT) allows you to define **invariants** (properties
that should always be true) and let the framework generate hundreds of
deterministic cases to find edge cases you might have missed.

## Thinking in Properties
Instead of writing a test for a single example:
> "If I reverse `1 2 3`, I get `3 2 1`."

Write a test for a **property**:
> "If I reverse a list twice, I should always get the original list back,
> regardless of the list's content or length."

## Using `holds`
In resQ, use the `holds` keyword to define a property test.

```q
.tst.desc["List Utilities"]{
  / `vars` receives `int$()` (a typed empty list) — resQ generates random-length
  / int lists. `runs` controls how many random inputs to try.
  holds["reverse-reverse is identity"; `runs`vars!(100; `int$())]{[l]
    reverse[reverse l] mustmatch l
  };
};
```

Generation is deterministic and does not consume q's global random stream.
Pass a `seed` property to replay or share a run exactly:

```q
holds["reverse-reverse is identity"; `runs`seed`vars!(100;4242;`int$())]{[l]
  reverse[reverse l] mustmatch l
};
```

Without an explicit seed, resQ derives a stable seed from the test's portable
identity. JSON schema v2 records the effective seed, run/pass/failure counts,
failing inputs, failure rate, replay tokens, original/minimal input, shrink work,
failure signature, duration, and termination reason under the test row's
`property` object.

## Public `.resq.gen` protocol

Every built-in generator is a data value tagged `resq-generator-v1`. Sampling
is a pure function of `(generator; seed; counter; stream)`:

```q
g:.resq.gen.scalar[`int;-100;100];
.resq.gen.sample[g;4242;0;"root"]
.resq.gen.sampleList[g;100;4242;"root"]
```

Built-ins use resQ's private MD5 counter hash. They do not read, reset, or
advance q's `\S` random state. Built-in symbol generation chooses from the
fixed `` `a`b`c`d`e`f`g `` pool and therefore cannot intern an unbounded set of
symbols. A user function supplied through legacy `vars` or `custom` may use q's
global random functions; determinism of that user code remains the author's
responsibility.

The constructors are:

| Constructor | Meaning |
|-------------|---------|
| `.resq.gen.typed typeName` | One value of a supported q type |
| `.resq.gen.scalar[typeName; lower; upper]` | Bounded byte/short/int/long/real/float/char |
| `.resq.gen.boundary values` | Uniform choice from explicit boundary values |
| `.resq.gen.weightedChoice[values; weights]` | Weighted explicit choice |
| `.resq.gen.nullable[generator; rate]` | Null with the declared probability |
| `.resq.gen.list[generator; min; max]` | Bounded collection |
| `.resq.gen.dictionary generators` | Named dictionary fields |
| `.resq.gen.tuple generators` | Positional heterogeneous values |
| `.resq.gen.table[schema; minRows; maxRows]` | Bounded table with generated columns |
| `.resq.gen.map[generator; function]` | Transform a generated value |
| `.resq.gen.filter[generator; predicate; maxAttempts]` | Bounded rejection sampling |
| `.resq.gen.custom[label; sample; shrink]` | User protocol implementation |

`sample` for a custom generator receives `[seed; counter; stream]`. `shrink`
receives the current value and returns ordered candidates. Filters throw after
`maxAttempts`; they never loop forever. `map` cannot generally invert a
transformation, so its shrink candidates use the mapped value's q type. Use a
custom generator where a domain-specific mapped shrink tree matters.

All legacy `vars` forms remain accepted. Type symbols, typed empty lists,
explicit choices, dictionaries, atoms, and generator functions are adapted by
`.resq.gen.adapt` before sampling.

### Composite example

```q
rowGen:.resq.gen.dictionary[
  `sym`qty`price!(
    .resq.gen.weightedChoice[`AAPL`MSFT`NVDA;3 2 1];
    .resq.gen.scalar[`long;1;100000];
    .resq.gen.filter[
      .resq.gen.scalar[`float;0.01;10000f];
      {not null x};
      20])];

holds["notional is non-negative";`runs`seed`vars!(500;42;rowGen)]{[row]
  0f mustlt (row`qty)*(row`price)
};
```

**Important**: each `holds` call in the same `.tst.desc` block must use a
compatible `vars` type (e.g., all symbol generators or all dict generators). If
you mix a simple type spec (`` `int ``) with a dict spec (`` `a`b!(`int;`int) ``)
in one desc block, resQ cannot build a uniform expectation table and throws a
`'type` load error. Put holds with different var shapes in separate desc blocks.

## Multiple Named Variables
When `vars` is a dictionary, the generated value is a dict — access fields by
key:

```q
.tst.desc["commutative addition"]{
  holds["a+b == b+a"; `runs`vars!(100; `a`b!(`int;`int))]{[x]
    (x[`a]+x[`b]) musteq (x[`b]+x[`a])
  };
};
```

## The shrinking engine
When a property test fails, the randomly generated input is often large and
noisy. resQ includes an automated **Shrinker**.

1. **Failure Found**: A list of 1,000 integers causes a crash.
2. **Shrinking**: The engine walks a deterministic type-aware candidate tree:
   collection removal, scalar simplification, and field/element/row shrinking.
3. **Minimal Case**: The engine presents you with the simplest possible failing
   input (e.g., a list with just `0` and `-1`).

This turns "It failed with this giant mess of data" into "It fails when a list
contains a negative number."

Only a candidate with the same failure signature as the original is accepted,
so minimization does not silently switch to a different bug. Shrinking has three
independent ceilings:

| `holds` property | Default | Meaning |
|------------------|---------|---------|
| `shrinkSteps` | `100` | Maximum accepted simplifications |
| `shrinkCandidates` | `1000` | Maximum executed candidates |
| `shrinkTimeMs` | `1000` | Wall-time ceiling in milliseconds |

The termination value is one of `minimal`, `stepLimit`, `candidateLimit`, or
`timeLimit`; a passing property records `notRun`.

Every failing generated case has a token such as
`resq-pbt-v1/4242/17`. Replay the exact input without advancing global random
state:

```q
input:.resq.gen.replay[rowGen;"resq-pbt-v1/4242/17"];
```

The token is portable when the generator definition and protocol version are
unchanged. Commit or log the generator definition alongside a token; editing
its bounds, fields, weights, mapping, or filtering intentionally changes the
sample.

## Default Pass Behaviour
A `holds` block with no failing inputs passes. The default `maxFailRate` is
`0.0`, meaning zero tolerance for failures. The check is strict: the actual
failure rate must **exceed** `maxFailRate` to fail the test.

To allow a small proportion of inputs to fail (e.g. for generators that produce
out-of-domain values you filter with early return):
```q
.tst.desc["occasionally OOD"]{
  holds["positive sqrt"; `maxFailRate`vars!(0.1; `float)]{[x]
    if[x < 0; :()];   / skip; does not count as a failure
    (sqrt x * x) mustwithin (x-0.001; x+0.001)
  };
};
```

## Best Practices
- **Invariants**: Good properties include:
  - **Round-tripping**: `decode[encode[x]] ~ x`
  - **Inversions**: `a + b - b = a`
  - **Idempotency**: `sort[sort[x]] ~ sort[x]`
- **Mixed Testing**: PBT doesn't replace example tests; it complements them.
- **Separate desc blocks** when `vars` shapes differ between `holds` calls.
- **Bound filters** and prefer constructive generators over rejection when the
  valid domain is sparse.
- **Keep failure messages structural**. A message containing the full generated
  value can make two instances look like different failure classes and prevent
  useful shrinking.
