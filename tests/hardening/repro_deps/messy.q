
/ A file with confusing strings
confusingFunc:{[]
 s: "This string has a { brace in it";
 s2: "And this one has a } closing brace";
 s3: "Nested { { } } braces in string";
 query: "select from t where col1 = 1, col2 = { x > 10 }";
 s
 };

/ Function that wraps load
customLoad:{[f]
 system "l ",f;
 };
