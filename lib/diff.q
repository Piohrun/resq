\d .tst

/ Color formatting utility
if[not `fmt in key `.tst; .tst.fmt.init: 1b];

fmt.color:{[c;txt]
    codes: `red`green`yellow`blue`magenta`cyan`bold!(31;32;33;34;35;36;1);
    if[not c in key codes; :txt];
    "\033[",string[codes c],"m",txt,"\033[0m"
 };

/ format Value for diff (colorized)
fmtVal:{[v;color]
    s: .Q.s1 v;
    if[count s; :.tst.fmt.color[color; s]];
    s
 };

/ Internal recursive diff
diffDeep:{[path;exp;act]
    if[exp ~ act; :()];
    
    tExp: type exp;
    tAct: type act;
    pStr: $[count path; path, ": "; ""];
    
    if[not tExp = tAct;
        :(enlist pStr, "Type mismatch";"  Expected type: ",.tst.fmtVal[tExp;`green];"  Actual type:   ",.tst.fmtVal[tAct;`red]);
    ];
    
    / Dictionary Diff (Recursive)
    if[99h = tExp;
        kExp: key exp;
        kAct: key act;
        
        / Key mismatches
        msg: ();
        missing: kExp except kAct;
        extra: kAct except kExp;
        
        if[count missing; msg,: enlist pStr, "Missing keys: ", .tst.fmt.color[`red; .Q.s1 missing]];
        if[count extra;   msg,: enlist pStr, "Extra keys:   ", .tst.fmt.color[`cyan; .Q.s1 extra]];
        
        / Value mismatches for common keys
        common: kExp inter kAct;
        pNext: $[count path; path, "."; ""];
        resList: { [p;e;a;k] .tst.diffDeep[p, .tst.toString[k]; e k; a k] }[pNext;exp;act] each common;
        msg,: raze resList;
        
        if[count msg; :msg];
    ];
    
    / Table diff
    if[98h=tExp;
        if[not (cExp:cols exp)~(cAct:cols act);
            :(enlist pStr, "Column mismatch";"  Expected: ",.tst.fmtVal[cExp;`green];"  Actual:   ",.tst.fmtVal[cAct;`red]);
        ];
        
        msg: ();
        if[not (nExp:count exp)=(nAct:count act);
            msg,: enlist pStr, "Count mismatch (Alignment might be off)";
            msg,: ("  Expected rows: ",.tst.fmtVal[nExp;`green]; "  Actual rows:   ",.tst.fmtVal[nAct;`red]);
        ];
        
        / Check rows
        limit: 5;
        badRows: ();
        
        / ADAPTIVE DIFF: For large tables, avoid row-by-row full scan
        isLarge: (count exp) > 1000;
        
        if[isLarge;
            / Quick column check using functional select/exec for speed
            / Find first mismatches efficiently
            / Note: This assumes simple columns. For complex columns, fallback to 1000 sample.
            
            / Compare columns individually to find bad rows indices
            / We use a sampled approach or chunked approach to avoid huge memory
            chunkSize: 1000;
            n: count exp;
            
            / Check first, middle, last chunk
            indices: distinct (til 5), (n - 1 - til 5), (1000 + til 5);
            indices: indices where indices < n;
            indices: asc indices;
            
            / Also check random sample if really huge
            if[n > 10000; indices: distinct indices, 5?n];
            
            / Check these rows specifically
            badRows: indices where not (exp indices) ~' (act indices);
            
            / If we found bad rows, great. If not, and we suspect mismatch (count matches), 
            / we might want to do a full scan but it is expensive.
            / For now, report "Diff in large table (partial scan)" if found.
            if[0 < count badRows;
                 msg,: enlist pStr, "Table content mismatch (Adaptive scan on large table):";
            ];
            
            / If no bad rows found in sample, but we know they differ (how? we don't know unless we scan)
            / For strict correctness we should scan all, but that's what crashes/is slow?
            / Let's try full scan on columns if they are atomic?
            
            if[0 = count badRows;
                / Try to find ANY index where they differ
                badRows: limit sublist where not exp ~' act;
            ];
        ];

        if[not isLarge;
            badRows: limit sublist where not exp ~' act;
        ];
        
        if[0<count badRows;
             msg,: enlist pStr, "Table content mismatch (showing first ",string[count badRows]," mismatches):";
             msg,: raze {[r;ex;ac] 
                rowExp: ex r;
                rowAct: ac r;
                diffCols: where not (value rowExp) ~' (value rowAct);
                rMsg: enlist "  Row ",string[r],":";
                colMsgs: { [re;ra;c]
                    (enlist "    Col ",string[c],":";
                     "      Exp: ", .tst.fmtVal[re c;`green];
                     "      Act: ", .tst.fmtVal[ra ra[c];`red])
                }[rowExp;rowAct] each diffCols;
                rMsg, raze colMsgs
             }[;exp;act] each badRows;
             :msg
        ];
        
        if[count msg; :msg];
    ];
    
    / List diff (generic)
    if[(tExp >= 0h) and (tExp < 20h);
        if[not (nExp:count exp)=(nAct:count act);
            :(enlist pStr, "Count mismatch";"  Expected len: ",.tst.fmtVal[nExp;`green];"  Actual len:   ",.tst.fmtVal[nAct;`red]);
        ];
        
        badIdx: 5 sublist where not exp ~' act;
        if[0<count badIdx;
             msg: enlist pStr, "List content mismatch (showing first ",string[count badIdx]," mismatches):";
             msg,: raze {[i;ex;ac] 
                (enlist "  Idx ",string[i],":";
                "    Exp: ", .tst.fmtVal[ex i;`green];
                "    Act: ", .tst.fmtVal[ac i;`red])
             }[;exp;act] each badIdx;
             :msg
        ];
    ];
    
    / Default fallback
    (enlist pStr, "Value mismatch";"  Expected: ", .tst.fmtVal[exp;`green];"  Actual:   ", .tst.fmtVal[act;`red])
 }

/ detailed difference between two objects
diff: {[expected;actual] .tst.diffDeep["";expected;actual]}

\d .