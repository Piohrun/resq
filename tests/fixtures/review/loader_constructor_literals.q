/ Regression source for the constructor-string polarity bug. This file is not
/ part of default discovery; the focused loader/release gate consumes it after
/ the scanner fix is active.
.tst.desc["constructor literals should stay data"]{
  should["should[ it[ shouldEach[ holds[ perf["]{
    observed:("should[";"it[";"shouldEach[";"holds[";"perf[");
    observed musteq ("should[";"it[";"shouldEach[";"holds[";"perf[");
  };
  should["skip[ pending[ skipIf[ retry[ testOnly["]{
    observed:("skip[";"pending[";"skipIf[";"retry[";"testOnly[");
    observed musteq ("skip[";"pending[";"skipIf[";"retry[";"testOnly[");
  };
  should["escaped quote \" and slash \\ preserve retry[ as text"]{
    "escaped quote \" and slash \\ preserve retry[ as text"
      musteq "escaped quote \" and slash \\ preserve retry[ as text";
  };
  should["first same-line constructor"]{1 musteq 1}; should["second same-line constructor"]{2 musteq 2};
};

::
