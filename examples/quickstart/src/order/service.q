/ Order Processing Service
/ Demonstrates: Sequential mocking, partial dictionary mocks, async operations

\d .order

/ Order database
orders: ([id:`int$()] userId:`int$(); items:(); totalAmount:`float$(); status:`symbol$(); createdAt:`timestamp$())

/ Pricing service (external - can be mocked)
pricing: `standard`premium`vip!1.0 0.9 0.8  / Discount multipliers

/ Create new order
/ @param userId (int) User ID
/ @param items (list) List of (item; quantity; price) tuples
/ @return (int) Order ID
create:{[userId;items]
    / Calculate total
    total: sum {x[1] * x 2} each items;
    
    / Get user discount (external call - can be mocked)
    userTier: .order.getUserTier[userId];
    discount: .order.pricing[userTier];
    finalTotal: total * discount;
    
    / Generate order ID
    newId: $[0<count orders; 1 + max (key orders)`id; 1];
    
    / Create order
    `.order.orders upsert (newId; userId; items; finalTotal; `pending; .z.p);
    
    / Initiate async payment processing
    .order.processPaymentAsync[newId; finalTotal];
    
    newId
 };

/ Get user tier (external service)
getUserTier:{[userId]
    / Default implementation - can be mocked in tests
    `standard
 };

/ Process payment asynchronously
/ @param orderId (int) Order ID
/ @param amount (float) Payment amount
processPaymentAsync:{[orderId;amount]
    / Simulate async operation
    / In real system, this would be a callback
    -1 "Processing payment for order ", string[orderId], ": $", string amount;
    
    / Simulate payment gateway response (can use deferred in tests)
    .order.paymentCallback[orderId; `success; "TXN-", string orderId];
 };

/ Payment callback handler
/ @param orderId (int) Order ID
/ @param status (symbol) Payment status
/ @param txnId (string) Transaction ID
paymentCallback:{[orderId;status;txnId]
    if[not orderId in (key orders)`id; :()];
    
    newStatus: $[status ~ `success; `completed; `failed];
    update status:newStatus from `.order.orders where id=orderId;
    
    / Notify user
    order: orders[orderId];
    .order.notifyUser[order`userId; status];
 };

/ Notify user (can be mocked)
notifyUser:{[userId;status]
    -1 "Notifying user ", string[userId], " of ", string status;
 };

/ Get order by ID
findById:{[id]
    $[id in (key orders)`id; orders[id]; ()]
 };

/ Get user orders
getByUser:{[userId]
    select from orders where userId=userId
 };

\d .
::
