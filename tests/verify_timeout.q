.tst.desc["Timeout Test"]{
    should["fail if it takes too long"]{
        / Simulate a timeout error without long runtime
        mustthrow["*stop*"]{ 'stop };
    };
};
