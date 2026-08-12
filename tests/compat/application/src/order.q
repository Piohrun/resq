/ Production-style source fixture: documented functions under an indented
/ namespace directive, with locals that used to become reserved through .q.
system "d .order";

  / @param rows table with time and amount columns
  / @return elapsed span and total amount
  summarize:{[rows]
    before:first rows`time;
    after:last rows`time;
    mock:sum rows`amount;
    `elapsed`total!(after-before;mock)
  };

  / @param amount numeric order amount
  / @return fee-adjusted amount
  settle:{[amount]
    it:amount*0.01;
    holds:amount+it;
    perf:holds+0f;
    must:perf;
    must
  };

system "d .";
