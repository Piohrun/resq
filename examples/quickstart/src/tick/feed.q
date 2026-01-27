\d .feed

/ Ticker Feed
/ Simulates publishing updates to listeners

listeners: ();
subscribe:{[h] listeners,: h; };

/ Triggered by timer
onTimer:{
  data: genTrade[];
  / Push to listeners
  {[h;d] (neg h)(`.u.upd;`trade;d)}[;data] each listeners;
 };

/ Generate random trade
genTrade:{
  syms:`GOOG`IBM`MSFT;
  n:1;
  ([] time:n#.z.t; sym:n?syms; price:100+n?10.0; size:100*1+n?10)
 };

\d .
