if[not `FILELOADING in key `.utl;
system "l resq.q";

describe["Stack Trace Verification"]{
    it["should report a deep stack trace on failure"]{
        deep1:{[x] deep2[x+1] };
        deep2:{[x] deep3[x+1] };
        deep3:{[x] 'nested_error };
        deep1[10];
    };
};
];
