/ User Management Service
/ Fixed version with correct table access syntax

\d .user

/ User database (in-memory)
users: ([id:`int$()] name:`symbol$(); email:`symbol$(); role:`symbol$(); active:`boolean$())

/ Create a new user
create:{[name;email;role]
    / Validate inputs
    if[null name; '"Name cannot be null"];
    if[null email; '"Email cannot be null"];
    if[not role in `admin`user`guest; '"Invalid role"];
    
    / Generate ID
    newId: $[0<count users; 1 + exec max id from users; 1];
    
    / Insert user
    `.user.users upsert (newId; name; email; role; 1b);
    
    / Log creation
    .user.logEvent[`userCreated; newId];
    
    newId
 };

/ Find user by ID
findById:{[id]
    $[id in exec id from users; first select from users where id=id; ()]
 };

/ Update user role
updateRole:{[id;newRole]
    if[not id in exec id from users; '"User not found"];
    if[not newRole in `admin`user`guest; '"Invalid role"];
    
    update role:newRole from `.user.users where id=id;
    .user.logEvent[`roleUpdated; id];
    1b
 };

/ Deactivate user
deactivate:{[idd]
    if[not idd in exec id from users; '"User not found"];
    update active:0b from `.user.users where id=idd;
    .user.logEvent[`userDeactivated; idd];
    1b
 };

/ Get all active users
getActive:{[]
    select from users where active
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

\d .
::
