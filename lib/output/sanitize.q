.tst.sanitizeToList:{[x]
    $[0h = type x; x;
      98h = type x; {[tbl; idx] tbl idx}[x] each til count x;
      99h = type x; enlist x;
      enlist x]
 };

.tst.sanitizeExpectations:{[x]
    rows: .tst.sanitizeToList x;
    rows: rows where not (::)~/: rows;
    $[0 = count rows; (); rows]
 };

.tst.sanitizeExpectation:{[suite; file; ns; tags; ex]
    if[not 99h = type ex;
        :`suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
            suite;
            "Unavailable expectation";
            `pass;
            "";
            0Nn;
            ();
            0;
            file;
            ns;
            tags)];

    exDesc:     $[`desc in key ex; .tst.toString ex`desc; "Unnamed expectation"];
    exResult:   .tst.normalizeResultStatus $[`result in key ex; ex`result; `pass];
    exFailures: $[`failures in key ex; ex`failures; ()];
    exErr:      $[`errorText in key ex; ex`errorText; ()];
    rawTime: $[`time in key ex; ex`time; 0Nn];
    exTime: $[(98h = type rawTime) and (0 < count rawTime); first rawTime;
              -16h = type rawTime; rawTime;
              0Nn];
    exAsserts:  $[`assertsRun in key ex;
                    $[(type ex`assertsRun) in (1h,4h,7h,-6h,-7h,6h); ex`assertsRun; 0i];
                    0i];
    exMsg: $[0 < count exFailures; .tst.toString exFailures;
                  0 < count exErr; .tst.toString exErr;
                  ""];

    `suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
        suite;
        exDesc;
        exResult;
        exMsg;
        exTime;
        exFailures;
        exAsserts;
        file;
        ns;
        tags)
 };

.tst.sanitizeSpec:{[spec]
    suite: $[`title in key spec; .tst.toString spec`title; "Unnamed suite"];
    file:  $[`tstPath in key spec; .tst.toString spec`tstPath; ""];
    ns:    $[`namespace in key spec; .tst.toString spec`namespace; ""];
    tags:  $[`tags in key spec; spec`tags; ()];
    exs:   $[`expectations in key spec; .tst.sanitizeExpectations spec`expectations; ()];

    if[0 = count exs;
        :enlist `suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
            suite;
            "No expectations";
            .tst.normalizeResultStatus $[`result in key spec; spec`result; `pass];
            "";
            0Nn;
            ();
            0i;
            file;
            ns;
            tags)
    ];
    .tst.sanitizeExpectation[suite;file;ns;tags;] each exs
 };

.tst.isResultRow:{[x]
    if[not 99h = type x; :0b];
    all `suite`description`status in key x
 };

.tst.sanitize:{[specs]
    if[0h = type specs;
        specs: specs where not (::)~/: specs;
        if[0 = count specs; :()];
    ];
    specs: .tst.sanitizeToList specs;
    if[not count specs; :()];
    specs: specs where not (::)~/: specs;
    if[not count specs; :()];
    if[all .tst.isResultRow each specs;
        :specs
    ];
    raze .tst.sanitizeSpec each specs
 };

.tst.emptyResultTable:{[]
    flip `suite`description`status`message`time`failures`assertsRun`file`namespace`tags!(
        ();
        ();
        `symbol$();
        ();
        `timespan$();
        ();
        `int$();
        ();
        ();
        ())
 };

/ Canonical reporter boundary.
/ accepts: spec objects, expectation rows, flat result tables, or row dictionaries
/ returns: list of result-row dictionaries
.tst.resultRows:{[results]
    rows: $[`sanitize in key `.tst; .tst.sanitize results; results];
    $[0h = type rows; rows;
      98h = type rows; {[tbl; idx] tbl idx}[rows] each til count rows;
      99h = type rows; enlist rows;
      enlist rows]
 };

/ Canonical table form for reporters that need qSQL grouping/filtering.
.tst.resultTable:{[results]
    rows: .tst.resultRows results;
    if[0 = count rows; :.tst.emptyResultTable[]];
    flip flip rows
 };
