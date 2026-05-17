.tst.desc["Configuration File Support"]{
 after{system "rm -f test_config.json"};

 should["load default config when file does not exist"]{
  cfg: .tst.loadConfig["nonexistent.json"];
  cfg[`fmt] musteq `text;
  cfg[`exit] musteq 0b;
  cfg[`fuzzLimit] musteq 100;
  };
 should["load and parse JSON config file"]{
  / Create test config file
  testCfg: "{ \"fmt\": \"junit\", \"exit\": true, \"failFast\": true }";
  hsym[`$":test_config.json"] 0: enlist testCfg;
  
  cfg: .tst.loadConfig["test_config.json"];
  cfg[`fmt] musteq `junit;
  cfg[`exit] musteq 1b;
  cfg[`failFast] musteq 1b;
  };
 should["normalize supported format aliases in config"]{
  testCfg: "{ \"fmt\": \"XML\", \"fuzzLimit\": 5 }";
  hsym[`$":test_config.json"] 0: enlist testCfg;
  
  cfg: .tst.loadConfig["test_config.json"];
  cfg[`fmt] musteq `junit;
  };
 should["warn for unsupported format"]{
  warnings: .tst.validateConfig `fmt`maxTestTime!(`unknown; 10);
  0 < count warnings;
  0 < count warnings where warnings like "Unsupported format*";
  };
 should["warn for non-text format type"]{
  warnings: .tst.validateConfig `fmt!5;
  0 < count warnings;
  0 < count warnings where warnings like "Unsupported format*";
  };
 should["merge config with defaults"]{
  testCfg: "{ \"fmt\": \"xunit\" }";
  hsym[`$":test_config.json"] 0: enlist testCfg;
  
  cfg: .tst.loadConfig["test_config.json"];
  cfg[`fmt] musteq `xunit;
  cfg[`fuzzLimit] musteq 100;
  };
 should["apply config to global settings"]{
  testCfg: `fmt`exit`failFast!(`console; 1b; 1b);
  .tst.applyConfig[testCfg];
  
  .resq.config.fmt musteq `console;
  .tst.app.exit musteq 1b;
  .tst.app.failFast musteq 1b;
  };
 };

::
