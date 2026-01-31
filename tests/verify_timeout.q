.tst.desc["Timeout Test"]{
    should["fail if it takes too long"]{
        / Loop to consume ~4-5 seconds
        x:0; do[4000000000; x+:1]; x
    };
};
