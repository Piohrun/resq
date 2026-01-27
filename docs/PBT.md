# 🛡️ Property-Based Testing (PBT)

Property-Based Testing (PBT) allows you to define **invariants** (properties that should always be true) and let the framework generate hundreds of random test cases to find edge cases you might have missed.

## Thinking in Properties
Instead of writing a test for a single example:
> "If I reverse `1 2 3`, I get `3 2 1`."

Write a test for a **property**:
> "If I reverse a list twice, I should always get the original list back, regardless of the list's content or length."

## Using `holds`
In `resQ`, use the `holds` keyword to define a property test.

```q
.tst.desc["List Utilities"]{
  / Define a property test
  / `runs` - number of random iterations (default 100)
  / `vars` - list of types for random input generation
  holds["reverse-reverse is identity"; `runs`vars!(100; (enlist `int$()))]{[l]
    reverse[reverse l] mustmatch l;
  };
};
```

## The "Shrinking" Engine
When a property test fails, the randomly generated input is often large and noisy. `resQ` includes an automated **Shrinker**.

1. **Failure Found**: A list of 1,000 integers causes a crash.
2. **Shrinking**: The engine recursively tries smaller versions of that list (bisecting, simplifying).
3. **Minimal Case**: The engine presents you with the simplest possible failing input (e.g., a list with just `0` and `-1`).

This turns "It failed with this giant mess of data" into "It fails when a list contains a negative number."

## Best Practices
- **Invariants**: Good properties include:
  - **Round-tripping**: `decode[encode[x]] == x`
  - **Inversions**: `a + b - b == a`
  - **Idempotency**: `sort[sort[x]] == sort[x]`
- **Mixed Testing**: PBT doesn't replace example tests; it complements them. Use example tests for known edge cases and PBT for "unknown unknowns."
