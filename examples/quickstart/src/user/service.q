/ User Management Service
/ Fixed version with correct table access syntax

system "d .user";

  / User database (in-memory)
  .user.users: ([id:`long$()] name:`symbol$(); email:`symbol$(); role:`symbol$(); active:`boolean$());

  / Create a new user
  create:{[name;email;role]
      / Validate inputs
      if[null name; '"Name cannot be null"];
      if[null email; '"Email cannot be null"];
      if[not role in `admin`user`guest; '"Invalid role"];
      
      / Generate ID
      newId: $[0<count .user.users; 1 + exec max id from .user.users; 1];
      
      / Insert user
      `.user.users upsert (newId; name; email; role; 1b);
      
      / Log creation
      .user.logEvent[`userCreated; newId];
      
      newId
   };

  / Find user by ID
  findById:{[userId]
      $[userId in exec id from .user.users; first select from .user.users where id=userId; ()]
   };

  / Update user role
  updateRole:{[userId;newRole]
      if[not userId in exec id from .user.users; '"User not found"];
      if[not newRole in `admin`user`guest; '"Invalid role"];
      
      update role:newRole from `.user.users where id=userId;
      .user.logEvent[`roleUpdated; userId];
      1b
   };

  / Deactivate user
  deactivate:{[idd]
      if[not idd in exec id from .user.users; '"User not found"];
      update active:0b from `.user.users where id=idd;
      .user.logEvent[`userDeactivated; idd];
      1b
   };

  / Get all active .user.users
  getActive:{[]
      select from .user.users where active
   };

  / External logging service
  logEvent:{[eventType;userId]
      -1 "EVENT: ", string[eventType], " for user ", string userId;
   };

  / Email notification service
  sendEmail:{[userId;subject;body]
      user: .user.findById[userId];
      if[null user; '"User not found"];
      -1 "EMAIL to ", string[user`email], ": ", subject;
      1b
   };

system "d .";
::
