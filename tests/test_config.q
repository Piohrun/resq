.tst.desc["Configuration File Support"]{
 after{@[hdel; hsym `$":test_config.json"; {}]};

 should["load default config when file does not exist"]{
  cfg: .tst.loadConfig["nonexistent.json"];
  cfg[`fmt] musteq `text;
  cfg[`exit] musteq 0b;
  cfg[`pollutionGuard] musteq 1b;
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
 should["warn for non-boolean pollution guard"]{
  warnings: .tst.validateConfig `pollutionGuard!5;
  0 < count warnings;
  0 < count warnings where warnings like "pollutionGuard must be a boolean";
  };
 should["merge config with defaults"]{
  testCfg: "{ \"fmt\": \"xunit\" }";
  hsym[`$":test_config.json"] 0: enlist testCfg;
  
  cfg: .tst.loadConfig["test_config.json"];
  cfg[`fmt] musteq `xunit;
  cfg[`fuzzLimit] musteq 100;
  };
 should["apply config to global settings"]{
  prevFmt: .resq.config.fmt;
  prevExit: .tst.app.exit;
  prevFailFast: .tst.app.failFast;
  prevGuard: .tst.app.pollutionGuard;
  testCfg: `fmt`exit`failFast`pollutionGuard!(`console; 1b; 1b; 0b);
  .tst.applyConfig[testCfg];
  
  appliedFmt: .resq.config.fmt;
  appliedExit: .tst.app.exit;
  appliedFailFast: .tst.app.failFast;
  appliedGuard: .tst.app.pollutionGuard;
  .resq.config.fmt: prevFmt;
  .tst.app.exit: prevExit;
  .tst.app.failFast: prevFailFast;
  .tst.app.pollutionGuard: prevGuard;
  appliedFmt musteq `console;
  appliedExit musteq 1b;
  appliedFailFast musteq 1b;
  appliedGuard musteq 0b;
  };
 };

::
