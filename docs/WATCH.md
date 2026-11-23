# Watch Mode

resQ includes a **Watch Mode** that re-runs the tests affected by a change to a source or test file.

## Quick Start

```bash
resq watch src/ tests/
```

Pass one or more directories to watch. On each detected change, resQ re-runs the relevant tests in-process and prints the result.

---

## How It Works

### Change detection

The watcher polls the watched directories on a fixed interval. Each `.q` file
is fingerprinted by its size and high-resolution modification token; platforms
that expose only whole seconds add a fixed-width, 64 KiB-chunked content digest. Same-size edits
within one second therefore still trigger a run. Metadata remains batch-statted
in bounded chunks rather than launching one subprocess per file. New and
deleted files are detected too. Hidden files (names starting with `.`) are
ignored.

### What gets re-run

Watch reads the watched `.q` files to learn which file loads which, and re-runs the tests that load what changed.

1. **Test file changed**: runs that file, and any test file that loads it.
2. **Any other file changed**: runs every test file that loads it, directly or through other files. A test file matching it by name (`src/foo.q` → `tests/test_foo.q` or `tests/foo_test.q` by default) runs as well.
3. **Nothing is known to load the changed file**: runs the full suite, and says which file caused it.
4. **File deleted**: runs the full suite, because what loaded the file can no longer be read.

The full suite is every test file under the watched directories.

### How loads are found

q has no hook that reports a load, so watch reads them from source text.

- **Any literal naming a `.q` file counts.** `\l src/a.q`, `system "l src/a.q"`, `.lib.load "src/a.q"`, `` .lib.load `:src/a.q `` and `.lib.load each ("src/a.q";"src/b.q")` all make the file depend on `src/a.q`, whatever the function is called. Comments and text after the script terminator are ignored.
- **A path matches by its trailing components.** `\l src/a.q` matches any watched file whose path ends in `/src/a.q`. A relative path is resolved against a working directory the text does not show, so `\l util.q` matches every watched `util.q`. This can run more tests than needed, never fewer.
- **A path joined onto a prefix matches by its literal tail.** `system "l ", root, "/src/a.q"` depends on the files ending in `/src/a.q`.

### Loads that cannot be read

Some loads have no fixed target in the text:

```q
system "l src/", name, ".q";   / the name is computed
.lib.load each modules;        / the list is a variable
.lib.load "pricing";           / a module name, which only the loader can map to a file
```

Loading a directory runs the scripts in it, so a load that names a watched directory counts too, as does `\l .`:

```q
\l src                         / a watched directory
system "l ", root, "/src";     / a path that ends in one
\l .                           / the current directory, wherever that is at run time
```

A test file that reaches such a load re-runs on **every** source change, because what it loads cannot be known. Watch lists these at startup with the file and line, each line once:

```text
>> 1 test file(s) rerun on every source change: a load they reach has no fixed target.
>>   tests/test_dyn.q line 3: .lib.load "src/",name,".q";
```

### Your own loader function

A function that loads a computed path is treated as a loader, and its calls are judged instead of its body:

```q
.lib.load:{[path] system "l ",path};      / a loader; this file stays ordinary
.lib.all:{[paths] .lib.load each paths};  / a wrapper is a loader too

.lib.load "src/a.q";                      / fixed target: a dependency on src/a.q
.lib.load "src/", name, ".q";             / computed target: unreadable, see above
```

Only a function that is simply assigned to a name is a loader. A lambda that runs where it is written is a load of that file, and is treated as one that cannot be read:

```q
loaded: {system "l ", x} each paths;      / runs now: this file loads computed paths
ld: {[root;p] system "l ", root, p}[base]; / a projection: what it was given cannot be read
```

A loader defined in a watched file is found without configuration. A loader defined **outside** the watched directories has to be named, or its calls with computed targets look like ordinary calls and go unnoticed:

```json
{
  "watchLoaders": [".lib.load", ".app.require"]
}
```

`.tst.watch.loaders` accepts the same names from a plugin file (`-plugin`).

### Limits

Watch selection is a convenience for the edit loop, not a guarantee. Run the full suite before you rely on a result. It cannot see:

- a loader defined outside the watched directories and not named in `watchLoaders`, when it is called with a computed target;
- loads chosen by data, such as a module list read from a file;
- a loader function called with a `.q` literal that is not what it loads.

### Reloading changed files

Watch re-runs tests in the same q process, and `-isolate` does not apply to it. Whether a re-run sees your edit depends on how the file is loaded:

| Loaded with | Re-run reads the edited file |
|---|---|
| `\l`, `system "l ..."`, `.tst.loadSource` | Yes, every time |
| `.utl.require`, `.resq.require` | Yes: watch forgets the watched files these have loaded before each re-run |
| Your own loader that skips files it has already loaded | No: the right tests re-run, against the old definitions |

resQ cannot reset a cache it does not own. If your loader keeps one, clear it in the test file before loading, or load the file under test with `\l`.

### Poll interval

Default is 1 second. Override by setting `.tst.watch.interval` (in seconds) in a plugin file (`-plugin`), which loads before the watcher starts.

---

## Configuration

Watch mode runs without a TTY — it works under redirected stdin and in CI environments. It uses a foreground poll loop (not `.z.ts`), so it does not interfere with any timer handler your code may define.

| Setting | Where | Purpose |
|---|---|---|
| `watchLoaders` | `resq.json` | Names of loader functions defined outside the watched directories |
| `.tst.watch.loaders` | plugin file | The same, set from q |
| `.tst.watch.interval` | plugin file | Poll interval in seconds |
| `testFilePatterns` | `resq.json` | Which basenames are test files |

---

## Troubleshooting

**Q: A new file isn't being picked up.**
A: The watcher re-scans directory listings on each poll cycle, so new files are detected within one poll interval (default 1 second).

**Q: It keeps running the full suite instead of a few files.**
A: Watch prints `No test file is known to load <file>` when it does this. No watched file names the changed file in a literal. If your tests load it through a function that takes a module name or a computed path, that load cannot be read; see *Loads that cannot be read*.

**Q: The same tests run on every change.**
A: They reach a load with no fixed target. The startup lines name the file and line. Give the load a literal `.q` path, or accept the extra runs.

**Q: A test that uses the changed file did not run.**
A: Check that its loader is defined in a watched directory or named in `watchLoaders`, and that the path it passes is a literal. Then run the full suite: selection is advisory.

**Q: I need to watch more directories.**
A: Pass all of them as arguments: `resq watch src/ lib/ tests/`.
