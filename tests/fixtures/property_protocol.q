.tst.desc["property protocol fixture"]{
  holds["shrinks a guaranteed failure";
    `runs`seed`vars`shrinkSteps`shrinkCandidates`shrinkTimeMs!(
      1;424242j;.resq.gen.list[.resq.gen.scalar[`int;0;100];2;6];50j;200j;1000f)]{[xs]
    count[xs] musteq 0;
  };
};
