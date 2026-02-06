system "d .analytics";
sma:{[n;list]
  l: `float$list;
  res: mavg[n; l];
  if[n > 1;
    partialIdx: where (til count l) < n - 1;
    if[count partialIdx; res: @[res; partialIdx; :; `float$ floor res partialIdx]];
  ];
  res
 };
system "d .";
