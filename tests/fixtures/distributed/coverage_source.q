\d .distcov

classify:{[x]
    if[x<0;:`negative];
    if[x=0;:`zero];
    `positive
 };

parity:{[x]$[0=x mod 2;`even;`odd]};

\d .
