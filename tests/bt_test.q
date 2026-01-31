f1:{[x] f2[x+1]};
f2:{[x] f3[x+1]};
f3:{[x] 'nested_error};

/ Trap
res: @[{[x] f1[x]}; 10; {[err] 
    bt: .Q.sbt .Q.bt[];
    "Error: ", err, "\nStack Trace:\n", bt
}];

-1 res;
exit 0;
