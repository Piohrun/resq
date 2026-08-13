.dist.beforeCount:0;
.dist.afterCount:0;
.dist.retryCount:0;

.tst.registerFixture[`distributedFixture;40];

.tst.desc["Distributed execution contract"]{
    before{.dist.beforeCount+:1};
    after{.dist.afterCount+:1};

    shouldEach["declarative fixture cases";
        ([] input:1 2 3 4;expected:41 42 43 44)]{
        [input;expected;distributedFixture]
        .dist.beforeCount musteq 1+.dist.afterCount;
        (input+distributedFixture) musteq expected;
    };

    retry[1;"retry history survives sharding"]{
        .dist.retryCount+:1;
        if[1=.dist.retryCount;'"distributed transient"];
        .dist.retryCount musteq 2;
    };

    should["ordinary tests remain atomic"]{
        .dist.beforeCount musteq 1+.dist.afterCount;
        1 musteq 1;
    };

    should["dynamic forall cases remain atomic"]{
        .tst.forall[([] input:1 2 3)]{[input] input musteq input};
    };

    should["dynamic parametrize cases remain atomic"]{
        .tst.parametrize[`left`right!(1 2;10 20);{[left;right]
            (left+right) mustgt 0;
        }];
    };
};
