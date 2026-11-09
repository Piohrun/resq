/ Every property here holds for any value qspec's generator can produce.
.tst.desc["holds value domain"]{
  should["load alongside property tests"]{ 1 musteq 1 };
  holds["longs are neither null nor infinite";`runs`vars!(100;(enlist `x)!enlist `long)]{[x]
    must[not null x`x;"null long"];
    must[(abs x`x)<0W;"infinite long"];
  };
  holds["ints are neither null nor infinite";`runs`vars!(100;(enlist `x)!enlist `int)]{[x]
    must[not null x`x;"null int"];
    must[(abs x`x)<0W;"infinite int"];
  };
  / qspec draws shorts from every short value, null and infinities included
  / (about 1 in 65536 each), so only the type is an invariant.
  holds["shorts are shorts";`runs`vars!(100;(enlist `x)!enlist `short)]{[x]
    type[x`x] musteq -5h;
  };
  holds["floats are finite and within qspec's range";`runs`vars!(100;(enlist `x)!enlist `float)]{[x]
    must[not null x`x;"null float"];
    must[x[`x] within 0 1e6;"float outside [0,1e6]"];
  };
  holds["reals are finite and within qspec's range";`runs`vars!(100;(enlist `x)!enlist `real)]{[x]
    must[not null x`x;"null real"];
    must[x[`x] within 0 10000e;"real outside [0,10000]"];
  };
  holds["booleans are booleans";`runs`vars!(100;(enlist `x)!enlist `boolean)]{[x]
    type[x`x] musteq -1h;
  };
  holds["dictionary vars";`runs`vars!(20;`a`b!(`long;`long))]{[x]
    (x[`a]+x[`b]) musteq x[`b]+x[`a];
  };
  holds["list vars";`runs`vars!(20;1 2 3)]{[x] x mustin 1 2 3 };
  holds["generator function vars";`runs`vars!(20;{til 3})]{[x] x mustmatch til 3 };
  holds["an integer maxFailRate";`runs`maxFailRate!(20;0)]{[x] 1 musteq 1 };
  should["run after the property tests"]{ 1 musteq 1 };
 };
