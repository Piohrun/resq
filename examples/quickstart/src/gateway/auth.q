\d .perm

/ Permission Registry (In-memory for simplicity)
privileges: `user`admin!(`read`write`exec; `read`write`exec`admin);

/ Check permission
/ @param user (sym)
/ @param action (sym)
check:{[user;action]
  if[not user in key privileges; :0b];
  action in privileges[user]
 };

/ Admin only action
shutdown:{[user]
  if[not check[user;`admin]; '"access denied"];
  / In real app, this would shut down system
  -1 "System shutdown triggered by ",string user;
  1b
 };

\d .
