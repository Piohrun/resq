\d .tst

/ detailed difference between two objects
/ returns a list of strings describing the difference, or empty list if identical
diff:{[expected;actual]
    if[expected~actual; :()];
    
    tExp: type expected;
    tAct: type actual;
    
    if[not tExp=tAct;
        :("Type mismatch";"  Expected type: ",string[tExp];"  Actual type:   ",string[tAct]);
    ];
    
    / Table diff
    if[98h=tExp;
        if[not (cExp:cols expected)~(cAct:cols actual);
            :(enlist "Column mismatch";"  Expected: ",.Q.s1 cExp;"  Actual:   ",.Q.s1 cAct);
        ];
        
        if[not (nExp:count expected)=(nAct:count actual);
            :(enlist "Count mismatch";"  Expected rows: ",string nExp;"  Actual rows:   ",string nAct);
        ];
        
        / Check rows (expensive for large tables, but necessary)
        / We find the first 5 rows that differ
        badRows: 5 sublist where not expected ~' actual;
        
        if[0<count badRows;
             msg: enlist "Table content mismatch (showing first ",string[count badRows]," mismatches):";
             msg,: raze {[r;ex;ac] 
                (enlist "  Row ",string[r],":";
                "    Exp: ", .Q.s1 ex r;
                "    Act: ", .Q.s1 ac r)
             }[;expected;actual] each badRows;
             :msg
        ];
    ];
    
    / List diff (generic)
    if[(tExp >= 0h) and (tExp < 20h);
        if[not (nExp:count expected)=(nAct:count actual);
            :(enlist "Count mismatch";"  Expected len: ",string nExp;"  Actual len:   ",string nAct);
        ];
        
        badIdx: 5 sublist where not expected ~' actual;
        if[0<count badIdx;
             msg: enlist "List content mismatch (showing first ",string[count badIdx]," mismatches):";
             msg,: raze {[i;ex;ac] 
                (enlist "  Idx ",string[i],":";
                "    Exp: ", .Q.s1 ex i;
                "    Act: ", .Q.s1 ac i)
             }[;expected;actual] each badIdx;
             :msg
        ];
    ];
    
    / Default fallback
    ("Value mismatch";"  Expected: ", .Q.s1 expected;"  Actual:   ", .Q.s1 actual)
 }

\d .