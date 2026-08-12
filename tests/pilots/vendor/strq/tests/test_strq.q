system "l libs/str.q";

.tst.desc["strQ external adoption"]{
  should["preserve word-boundary transformations"]{
    .str.sc["An example of Snake case"] musteq "An_example_of_Snake_case";
    .str.stc["an example string"] musteq "An Example String";
    .str.tc["An example of Train case"] musteq "An-example-of-Train-case";
    .str.cc["camel-case_function_TEST"] musteq "camelCaseFunctionTest";
    .str.cc["Another Test"] musteq "anotherTest";
    .str.ucc["addSpaceInCamelCase"] musteq "add Space In Camel Case";
    .str.us["underscoreSeparatedText"] musteq "underscore_separated_text";
    .str.us["space separated text"] musteq "space_separated_text";
  };
  should["preserve case and padding helpers"]{
    .str.fc["FlipCase"] musteq "fLIPcASE";
    .str.sfl[3;12] musteq " 12";
    .str.sfr[3;12] musteq "12 ";
    .str.sflb[`a`bbb`cc] musteq ("  a";"bbb";" cc");
    .str.sfrb[`a`bbb`cc] musteq ("a  ";"bbb";"cc ");
    .str.zfl[4;72] musteq "0072";
    .str.zfr[4;72] musteq "7200";
  };
  should["preserve q value stringification"]{
    .str.strif[`$"String"] musteq "String";
    .str.strif[`$"c"] musteq enlist "c";
    .str.strif[`s] musteq enlist "s";
    .str.strif[10] musteq "10";
    .str.strif[(0b;1i;2j;3f;`4;"5")] musteq "(0b;1i;2;3f;`4;\"5\")";
    .str.strif[([] i:1 2 3 4)] musteq "+(,`i)!,1 2 3 4";
  };
};

::
