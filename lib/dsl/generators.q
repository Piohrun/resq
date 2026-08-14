/ generators.q - deterministic property generators and shrink protocol
.resq.gen.init_:1b

.resq.gen.PROTOCOL:`$"resq-generator-v1"

/ A generator is data plus two protocol entry points. Built-ins are dispatched
/ by kind; custom generators provide functions in options. Keeping seed,
/ counter and stream explicit makes sampling replayable and prevents any built-in
/ from touching q's process-global random stream.
.resq.gen.make:{[kind;options]
  if[not -11h=type kind;'"generator kind must be a symbol"];
  if[not 99h=type options;'"generator options must be a dictionary"];
  `protocol`kind`options!(.resq.gen.PROTOCOL;kind;options)
 };

.resq.gen.isGenerator:{[x]
  if[not 99h=type x;:0b];
  if[not all `protocol`kind`options in key x;:0b];
  .resq.gen.PROTOCOL~x`protocol
 };

.resq.gen.constant:{[item]
  .resq.gen.make[`constant;enlist[`value]!enlist item]
 };

.resq.gen.typed:{[typeName]
  if[not (typeName in key .tst.typeFuzzN);
    '"unknown generator type: ",.tst.toString typeName];
  .resq.gen.make[`type;enlist[`typeName]!enlist typeName]
 };

.resq.gen.scalar:{[typeName;lo;hi]
  if[not (typeName in `byte`short`int`long`real`float`char);
    '"bounded scalar supports byte, short, int, long, real, float, or char"];
  if[lo>hi;'"bounded scalar lower bound exceeds upper bound"];
  .resq.gen.make[`scalar;`typeName`lower`upper!(typeName;lo;hi)]
 };

.resq.gen.boundary:{[values]
  if[0=count values;'"boundary generator requires at least one value"];
  .resq.gen.make[`boundary;enlist[`values]!enlist values]
 };

.resq.gen.weightedChoice:{[values;weights]
  if[0=count values;'"weighted choice requires at least one value"];
  if[count[values]<>count weights;'"weighted choice values and weights must have equal counts"];
  if[not all 0<=weights;'"weighted choice weights must be non-negative"];
  if[0>=sum weights;'"weighted choice requires a positive total weight"];
  .resq.gen.make[`weightedChoice;`values`weights!(values;"f"$weights)]
 };

.resq.gen.nullable:{[generator;nullRate]
  if[not .resq.gen.isGenerator generator;generator:.resq.gen.adapt generator];
  if[(nullRate<0) or nullRate>1;'"nullable rate must be between 0 and 1"];
  .resq.gen.make[`nullable;`generator`nullRate!(generator;"f"$nullRate)]
 };

.resq.gen.list:{[generator;minLength;maxLength]
  if[not .resq.gen.isGenerator generator;generator:.resq.gen.adapt generator];
  if[(minLength<0) or maxLength<minLength;'"list generator requires 0 <= minLength <= maxLength"];
  .resq.gen.make[`list;`generator`minLength`maxLength!(generator;"j"$minLength;"j"$maxLength)]
 };

.resq.gen.dictionary:{[generators]
  if[not 99h=type generators;'"dictionary generator requires a dictionary"];
  adapted:.resq.gen.adapt each generators;
  .resq.gen.make[`dictionary;enlist[`generators]!enlist adapted]
 };
.resq.gen.dict:.resq.gen.dictionary;

.resq.gen.tuple:{[generators]
  if[98h=type generators;
    if[not all .resq.gen.isGenerator each {[table;index]table index}[generators;] each til count generators;
      '"tuple generator table rows must be generators"];
    :.resq.gen.make[`tuple;enlist[`generators]!enlist generators]];
  if[not 0h=type generators;'"tuple generator requires a general list"];
  .resq.gen.make[`tuple;enlist[`generators]!enlist .resq.gen.adapt each generators]
 };

.resq.gen.table:{[schema;minRows;maxRows]
  if[not 99h=type schema;'"table generator schema must be a dictionary"];
  if[(minRows<0) or maxRows<minRows;'"table generator requires 0 <= minRows <= maxRows"];
  .resq.gen.make[`table;`schema`minRows`maxRows!(
    .resq.gen.adapt each schema;"j"$minRows;"j"$maxRows)]
 };

.resq.gen.map:{[generator;fn]
  if[not .resq.gen.isGenerator generator;generator:.resq.gen.adapt generator];
  if[not (abs type fn) within 100 104h;'"map generator requires a function"];
  .resq.gen.make[`map;`generator`function!(generator;fn)]
 };

.resq.gen.filter:{[generator;predicate;maxAttempts]
  if[not .resq.gen.isGenerator generator;generator:.resq.gen.adapt generator];
  if[not (abs type predicate) within 100 104h;'"filter generator requires a predicate function"];
  if[maxAttempts<=0;'"filter generator maxAttempts must be positive"];
  .resq.gen.make[`filter;`generator`predicate`maxAttempts!(generator;predicate;"j"$maxAttempts)]
 };

.resq.gen.custom:{[label;sampleFn;shrinkFn]
  if[not (abs type sampleFn) within 100 104h;'"custom generator sample must be a function"];
  if[not (abs type shrinkFn) within 100 104h;'"custom generator shrink must be a function"];
  .resq.gen.make[`custom;`label`sample`shrink!(.tst.toString label;sampleFn;shrinkFn)]
 };

/ Adapt every pre-1.5 `vars` spelling without changing its sampling meaning.
/ Generator dictionaries are detected before ordinary dictionaries.
.resq.gen.adapt:{[spec]
  if[.resq.gen.isGenerator spec;:spec];
  tc:type spec;
  if[-11h=tc;
    :$[spec in key .tst.typeFuzzN;.resq.gen.typed spec;.resq.gen.constant spec]];
  if[11h=tc;:.resq.gen.boundary spec];
  if[(abs tc) within 100 104h;
    :.resq.gen.make[`legacyFunction;enlist[`function]!enlist spec]];
  if[99h=tc;:.resq.gen.dictionary spec];
  if[tc>=0h;
    if[0=count spec;
      elementType:$[tc in .tst.typeCodes;.tst.typeNames .tst.typeCodes?tc;`long];
      :.resq.gen.list[.resq.gen.typed elementType;0;.tst.fuzzListMaxLength-1]];
    if[(1=count distinct spec) and null first spec;
      elementType:$[tc in .tst.typeCodes;.tst.typeNames .tst.typeCodes?tc;`long];
      :.resq.gen.list[.resq.gen.typed elementType;0;(count spec)-1]];
    if[1=count distinct spec;
      :.resq.gen.list[.resq.gen.constant first spec;0;(count spec)-1]];
    :.resq.gen.boundary spec];
  .resq.gen.constant spec
 };

.resq.gen.sampleType:{[typeName;seed;counter;stream]
  .tst.privateScalar[.tst.typeFuzzN typeName;seed;counter;stream]
 };

.resq.gen.sampleScalar:{[options;seed;counter;stream]
  name:options`typeName;
  lo:options`lower;
  hi:options`upper;
  word:.tst.privateWord[seed;counter;stream];
  if[name in `real`float;
    sampled:("f"$lo)+(("f"$hi)-"f"$lo)*("f"$word)%4294967295f;
    :$[`real~name;"e"$sampled;sampled]];
  span:("j"$hi)-"j"$lo;
  sampled:("j"$lo)+$[span=0;0j;word mod 1+span];
  $[`byte~name;"x"$sampled;
    `short~name;"h"$sampled;
    `int~name;"i"$sampled;
    `char~name;"c"$sampled;
    sampled]
 };

.resq.gen.sampleWeighted:{[options;seed;counter;stream]
  total:sum options`weights;
  draw:total*("f"$.tst.privateWord[seed;counter;stream])%4294967296f;
  idx:first where draw < sums options`weights;
  options[`values] idx
 };

.resq.gen.sampleListOptions:{[options;seed;counter;stream]
  lo:options`minLength;
  span:1+options[`maxLength]-lo;
  n:lo+.tst.privateIndex[seed;counter;stream,"/length";span];
  {[g;s;c;st;i].resq.gen.sample[g;s;c*104729+i;st,"/item/",string i]}[
    options`generator;seed;counter;stream;] each til n
 };

.resq.gen.sampleDictionary:{[options;seed;counter;stream]
  generators:options`generators;
  names:key generators;
  names!{[g;s;c;st;n].resq.gen.sample[g;s;c;st,"/",.tst.toString n]}'[
    value generators;(count names)#enlist seed;(count names)#enlist counter;
    (count names)#enlist stream;names]
 };

.resq.gen.sampleTuple:{[options;seed;counter;stream]
  generators:options`generators;
  {[generators;s;c;st;i]
    .resq.gen.sample[generators i;s;c;st,"/",string i]
  }[generators;seed;counter;stream;] each til count generators
 };

.resq.gen.sampleTable:{[options;seed;counter;stream]
  lo:options`minRows;
  n:lo+.tst.privateIndex[seed;counter;stream,"/rows";1+options[`maxRows]-lo];
  schema:options`schema;
  names:key schema;
  columns:{[g;s;c;st;name;n]
    .resq.gen.sampleList[g;n;s;st,"/column/",string[c],"/",.tst.toString name]
  }'[value schema;(count names)#enlist seed;(count names)#enlist counter;
     (count names)#enlist stream;names;(count names)#enlist n];
  flip names!columns
 };

.resq.gen.sampleFilter:{[options;seed;counter;stream]
  i:0j;
  while[i<options`maxAttempts;
    sampled:.resq.gen.sample[options`generator;seed;counter*65537+i;stream,"/filter"];
    accepted:@[{[pair]1b~(pair 0) pair 1};(options`predicate;sampled);{[e]0b}];
    if[accepted;:sampled];
    i+:1];
  '"filter generator exhausted maxAttempts without an accepted value"
 };

.resq.gen.nullValue:{[generator]
  kind:generator`kind;
  if[not (kind in `type`scalar);:(::)];
  typeName:generator[`options;`typeName];
  if[`boolean~typeName;:(::)];
  if[`guid~typeName;:0Ng];
  if[`char~typeName;:" "];
  if[`symbol~typeName;:`];
  code:.tst.typeCodes .tst.typeNames?typeName;
  code$0N
 };

.resq.gen.sample:{[generator;seed;counter;stream]
  if[not .resq.gen.isGenerator generator;'"invalid resq generator"];
  kind:generator`kind;
  options:generator`options;
  $[`constant~kind;options`value;
    `type~kind;.resq.gen.sampleType[options`typeName;seed;counter;stream];
    `scalar~kind;.resq.gen.sampleScalar[options;seed;counter;stream];
    `boundary~kind;options[`values] .tst.privateIndex[seed;counter;stream;count options`values];
    `weightedChoice~kind;.resq.gen.sampleWeighted[options;seed;counter;stream];
    `nullable~kind;$[(("f"$.tst.privateWord[seed;counter;stream,"/null"])%4294967296f)<options`nullRate;
      .resq.gen.nullValue options`generator;
      .resq.gen.sample[options`generator;seed;counter;stream,"/value"]];
    `list~kind;.resq.gen.sampleListOptions[options;seed;counter;stream];
    `dictionary~kind;.resq.gen.sampleDictionary[options;seed;counter;stream];
    `tuple~kind;.resq.gen.sampleTuple[options;seed;counter;stream];
    `table~kind;.resq.gen.sampleTable[options;seed;counter;stream];
    `map~kind;options[`function] .resq.gen.sample[options`generator;seed;counter;stream,"/map"];
    `filter~kind;.resq.gen.sampleFilter[options;seed;counter;stream];
    `custom~kind;options[`sample][seed;counter;stream];
    `legacyFunction~kind;options[`function][];
    '"unknown resq generator kind: ",.tst.toString kind]
 };

.resq.gen.sampleList:{[generator;runs;seed;stream]
  .resq.gen.sample[generator;seed;;stream] each til runs
 };

.resq.gen.replayToken:{[seed;counter]
  "resq-pbt-v1/",string["j"$seed],"/",string["j"$counter]
 };

.resq.gen.parseReplayToken:{[token]
  parts:"/" vs .tst.toString token;
  if[(3<>count parts) or not "resq-pbt-v1"~first parts;
    '"invalid resQ property replay token"];
  `seed`counter!("J"$parts 1;"J"$parts 2)
 };

.resq.gen.replay:{[generator;token]
  parsed:.resq.gen.parseReplayToken token;
  .resq.gen.sample[.resq.gen.adapt generator;parsed`seed;parsed`counter;"root"]
 };

/ Keep candidates stable and bounded. Serialization is used only as a local
/ identity key; it does not intern symbols or escape into a report.
.resq.gen.distinctCandidates:{[candidates;original]
  out:();seen:();
  ( {[original;state;candidate]
      if[original~candidate;:state];
      keyText:.tst.canonicalValueBytes candidate;
      if[any keyText~/:state 1;:state];
      (state[0],enlist candidate;state[1],enlist keyText)
    }[original]/[(out;seen);candidates]) 0
 };

.resq.gen.atomCandidates:{[generator;item]
  kind:generator`kind;
  options:generator`options;
  target:$[`scalar~kind;options`lower;
    `type~kind;.tst.typeFuzzN options`typeName;
    0];
  tc:type item;
  candidates:();
  if[tc in -1 -4 -5 -6 -7 -8 -9 -10 -12 -13 -14 -15 -16 -17 -18 -19h;
    candidates,:enlist target];
  if[tc in -4 -5 -6 -7 -8 -9h;
    candidates,:enlist item div 2];
  if[-11h=tc;candidates,:enlist `symbol];
  if[-2h=tc;candidates,:enlist 0Ng];
  .resq.gen.distinctCandidates[candidates;item]
 };

.resq.gen.listCandidates:{[generator;item]
  if[0=count item;:()];
  minimum:generator[`options;`minLength];
  half:minimum|"j"$floor (count item)%2;
  candidates:enlist minimum#item;
  if[half<count item;
    candidates,:enlist half#item;
    candidates,:enlist (count[item]-half)_item];
  child:generator[`options;`generator];
  i:0;
  while[i<count item;
    shrinks:.resq.gen.shrinkCandidates[child;item i];
    if[count shrinks;
      changed:item;
      changed[i]:first shrinks;
      candidates,:enlist changed];
    i+:1];
  .resq.gen.distinctCandidates[candidates;item]
 };

.resq.gen.dictCandidates:{[generator;item]
  generators:generator[`options;`generators];
  out:();
  {[generators;original;name]
    shrinks:.resq.gen.shrinkCandidates[generators name;original name];
    if[not count shrinks;:()];
    changed:original;
    changed[name]:first shrinks;
    enlist changed
  }[generators;item;] each key generators
 };

.resq.gen.tupleCandidates:{[generator;item]
  generators:generator[`options;`generators];
  out:();i:0;
  while[i<count generators;
    shrinks:.resq.gen.shrinkCandidates[generators i;item i];
    if[count shrinks;
      changed:item;
      changed[i]:first shrinks;
      out,:enlist changed];
    i+:1];
  out
 };

.resq.gen.tableCandidates:{[generator;item]
  if[0=count item;:()];
  minimum:generator[`options;`minRows];
  half:minimum|"j"$floor (count item)%2;
  candidates:enlist minimum#item;
  if[half<count item;candidates,:enlist half#item];
  if[(count[item]-half)>=minimum;candidates,:enlist half _ item];
  schema:generator[`options;`schema];
  names:key schema;
  columnIndex:0j;
  while[columnIndex<count names;
    field:names columnIndex;
    rowIndex:0j;
    while[rowIndex<count item;
      shrinks:.resq.gen.shrinkCandidates[schema field;item[field] rowIndex];
      if[count shrinks;
        changed:0!item;
        column:changed field;
        column[rowIndex]:first shrinks;
        changed[field]:column;
        candidates,:enlist changed];
      rowIndex+:1];
    columnIndex+:1];
  .resq.gen.distinctCandidates[candidates;item]
 };

.resq.gen.filteredCandidates:{[options;item]
  candidates:.resq.gen.shrinkCandidates[options`generator;item];
  if[not count candidates;:()];
  accepted:{[fn;candidate]
    @[{[pair]1b~(pair 0) pair 1};(fn;candidate);{[e]0b}]
  }[options`predicate;] each candidates;
  candidates where accepted
 };

.resq.gen.nullableCandidates:{[options;item]
  if[((::)~item) or (((type item)<0h) and 1b~null item);:()];
  (enlist .resq.gen.nullValue options`generator),
    .resq.gen.shrinkCandidates[options`generator;item]
 };

.resq.gen.legacyCandidates:{[item]
  tc:type item;
  if[98h=tc;:.resq.gen.tableCandidates[()!();item]];
  if[99h=tc;:()];
  if[tc>=0h;
    element:$[(abs tc) in .tst.typeCodes;
      .resq.gen.typed .tst.typeNames .tst.typeCodes?abs tc;
      .resq.gen.constant (::)];
    :.resq.gen.listCandidates[.resq.gen.list[element;0;count item];item]];
  if[(abs tc) in .tst.typeCodes;
    :.resq.gen.atomCandidates[.resq.gen.typed .tst.typeNames .tst.typeCodes?abs tc;item]];
  ()
 };

.resq.gen.shrinkCandidates:{[generator;item]
  if[not .resq.gen.isGenerator generator;generator:.resq.gen.adapt generator];
  kind:generator`kind;
  options:generator`options;
  candidates:$[`constant~kind;();
    kind in `type`scalar;.resq.gen.atomCandidates[generator;item];
    kind in `boundary`weightedChoice;options`values;
    `nullable~kind;.resq.gen.nullableCandidates[options;item];
    `list~kind;.resq.gen.listCandidates[generator;item];
    `dictionary~kind;raze .resq.gen.dictCandidates[generator;item];
    `tuple~kind;.resq.gen.tupleCandidates[generator;item];
    `table~kind;.resq.gen.tableCandidates[generator;item];
    `map~kind;.resq.gen.legacyCandidates item;
    `filter~kind;.resq.gen.filteredCandidates[options;item];
    `custom~kind;options[`shrink] item;
    `legacyFunction~kind;.resq.gen.legacyCandidates item;
    ()];
  .resq.gen.distinctCandidates[candidates;item]
 };
