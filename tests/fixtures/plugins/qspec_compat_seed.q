/ The pinned qspec public fuzz corpus uses q's process-global RNG. The corpus is
/ immutable upstream source, so its compatibility harness loads this fixture
/ first to make the external legacy generator replayable without editing it.
system "S 424242";
