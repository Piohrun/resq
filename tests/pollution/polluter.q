
.tst.desc["Pollution Source"]{
    should["pollute the global namespace"]{
        / Explicitly set a variable in the root namespace
        curr: system "d";
        system "d .";
        
        POLLUTION_VAR:: 123;
        
        system "d ", string curr;
        
        / Verify it exists (we might need to access via . if we are back in ns, but root vars are visible)
        POLLUTION_VAR musteq 123;
    };
};
