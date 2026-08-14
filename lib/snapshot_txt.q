/ snapshot_txt.q - text (.snap.txt) snapshot storage + mustmatchst assertion
\d .tst

/ Snapshot configuration
/ NOTE: text snapshots live under tests/__snapshots__ as <name>.snap.txt, a
/ DIFFERENT directory + extension convention than binary snapshots (snapshot.q
/ stores tests/snapshots/<name>.snap). Both conventions are kept as-is for
/ backward compatibility.
snapTxtRoot: @[get;`.resq.startCwd;{system "cd"}]
snapTxtDir: snapTxtRoot,"/tests/__snapshots__"

setSnapTxtDir:{[d] .tst.snapTxtDir: .utl.pathToString d}

/ Same leaf containment as snapshot.q's snapPath: a snapshot name must be a
/ bare file name, so it can never resolve outside snapTxtDir.
snapTxtPath:{[name]
    n: $[10h = type name; name;
         -11h = type name; string name;
         '"Invalid snapshot name: expected a string or symbol"];
    if[not .tst.validSnapLeaf n;
        '"Invalid snapshot name '", n, "': must be a bare file name (no path separators, no leading dot)"];
    target:.tst.snapTxtDir,"/",n,".snap.txt";
    .utl.pathToHsym .tst.validateSnapshotTarget[.tst.snapTxtDir;target]
 }

/ Existence by FILE PRESENCE (mirrors snapshot.q's snapExists). A stored empty
/ value otherwise round-trips as "" and could be confused with "missing".
snapTxtExists:{[name] not () ~ key .tst.snapTxtPath name }

loadSnapTxt:{[name]
    p: .tst.snapTxtPath name;
    if[not type key p; :()];
    "\n" sv read0 p
 }

saveSnapTxt:{[name;data]
    .tst.ensureDir[.tst.snapTxtDir];
    p: .tst.snapTxtPath name;
    txt:.j.j .tst.textSnapshotDocument data;
    hsym[p] 0: enlist txt;
 }

.tst.textSnapshotDocument:{[raw]
    canonical:.tst.canonicalValueBytes raw;
    rendering:.tst.renderValueFull raw;
    `schemaVersion`kind`codec`digestAlgorithm`digest`canonicalPayload`ipcPayloadHex`rendering`renderingDigest!(
        2j;"resq-text-snapshot";.tst.valueCodecMetadata[];"md5";
        .tst.canonicalValueDigest canonical;canonical;
        .tst.valueHexBytes -8!raw;rendering;.tst.canonicalValueDigest rendering)
 };

.tst.textSnapshotCodecMatches:{[codec]
    if[not 99h=type codec;:0b];
    expected:.tst.valueCodecMetadata[];
    required:key expected;
    if[not all required in key codec;:0b];
    all {[left;right;setting]
        $[setting~`version;("j"$left setting)=("j"$right setting);
          .tst.toString[left setting]~.tst.toString[right setting]]
      }[codec;expected;] each required
 };

.tst.parseTextSnapshot:{[text]
    fail:{[state;reason]`state`reason`document!(state;reason;()!())};
    parsed:@[{[raw](0b;.j.k raw)};text;{[err](1b;err)}];
    if[first parsed;:fail[`legacy;"unversioned or malformed text snapshot"]];
    doc:last parsed;
    if[not 99h=type doc;:fail[`legacy;"unversioned text snapshot"]];
    required:`schemaVersion`kind`codec`digestAlgorithm`digest`canonicalPayload`ipcPayloadHex`rendering`renderingDigest;
    if[not all required in key doc;
        :fail[`legacy;"text snapshot v1 has no trusted full-value payload"]];
    if[not 2="j"$doc`schemaVersion;
        :fail[`unsupported;"unsupported text snapshot schema version"]];
    if[not "resq-text-snapshot"~.tst.toString doc`kind;
        :fail[`unsupported;"unexpected text snapshot kind"]];
    if[not "md5"~.tst.toString doc`digestAlgorithm;
        :fail[`unsupported;"unsupported text snapshot digest"]];
    if[not .tst.textSnapshotCodecMatches doc`codec;
        :fail[`unsupported;"snapshot codec/q build differs; explicit migration is required"]];
    canonical:.tst.toString doc`canonicalPayload;
    rendering:.tst.toString doc`rendering;
    if[not .tst.toString[doc`digest]~.tst.canonicalValueDigest canonical;
        :fail[`invalid;"canonical payload digest mismatch"]];
    if[not .tst.toString[doc`renderingDigest]~.tst.canonicalValueDigest rendering;
        :fail[`invalid;"rendering digest mismatch"]];
    `state`reason`document!(`ok;"";doc)
 };

.tst.textSnapshotMigrationRequired:{[name;reason]
    ' "Text snapshot migration required for '",name,"': ",reason,
      ". Re-run with explicit snapshot update mode to write trusted v2 evidence."
 };

mustmatchTxtSnap:{[actual;name]
    / Validate before any filesystem access or snapshot creation.
    validatedPath: .tst.snapTxtPath name;
    n: $[10h=type name; name; string name];
    actualDocument:.tst.textSnapshotDocument actual;
    / Decide existence by FILE PRESENCE, not by ()~stored.
    missing: not .tst.snapTxtExists n;

    / Explicit update intent always (re)writes and passes, with a NOTE.
    if[@[get;`.tst.updateSnaps;{0b}];
        .tst.saveSnapTxt[n;actual];
        .tst.recordSnapshotEvent[`text;n;`updated;validatedPath];
        -1 "NOTE: text snapshot created: ", n, " (", .tst.snapTxtDir, ") - review and commit it";
        :1b;
    ];

    / First-run (no stored snapshot). Under -strict, refuse to auto-create-and-
    / pass so a fresh CI workspace fails loudly instead of green-washing. Guard
    / the strict lookup since .tst.app.strict may be undefined in bare sessions.
    if[missing;
        if[1b ~ @[get; `.tst.app.strict; 0b];
            .tst.recordSnapshotEvent[`text;n;`missing;validatedPath];
            ' "Snapshot missing under -strict: ", n, " (run without -strict once to create it)";
        ];
        .tst.saveSnapTxt[n;actual];
        .tst.recordSnapshotEvent[`text;n;`created;validatedPath];
        -1 "NOTE: text snapshot created: ", n, " (", .tst.snapTxtDir, ") - review and commit it";
        :1b;
    ];

    storedText:.tst.loadSnapTxt[n];
    parsed:.tst.parseTextSnapshot storedText;
    if[not (parsed`state)~`ok;
        .tst.recordSnapshotEvent[`text;n;`unsupported;validatedPath];
        .tst.textSnapshotMigrationRequired[n;parsed`reason]];
    stored:parsed`document;
    if[not (actualDocument`canonicalPayload)~stored`canonicalPayload;
        .tst.recordSnapshotEvent[`text;n;`mismatch;validatedPath];
        -1 "SNAPSHOT MISMATCH for '",n,"'";
        -1 "----------------------------------------------------------------";
        -1 "Expected (Stored):";
        -1 stored`rendering;
        -1 "Actual (Current):";
        -1 actualDocument`rendering;
        -1 "----------------------------------------------------------------";
        'snapshotTxtMismatch
    ];

    .tst.recordSnapshotEvent[`text;n;`matched;validatedPath];
    1b
 }

\d .
