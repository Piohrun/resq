\d .utl

/ Minimal qutil mock
pkg: {[x]};

/ Require: Load file if exists in QPATH or relative
require: {[x]
  -1 "Requiring: ", x;
  if["qspec"~x; :(::)]; / Skip qspec (assume loaded or unneeded)
  tryLoad: {[f] @[system; "l ",f; {0b}]};
  
  / Try relative
  if[tryLoad x; :x];
  
  / Try QPATH
  paths: ":" vs getenv `QPATH;
  { if[not 1b ~ x 1; x[0] each x[1]] }[tryLoad;] each paths,\:x;
 };

addOpt: {[name;type;target] };
addArg: {[name;type;target;prop] };
parseArgs: {[]};
