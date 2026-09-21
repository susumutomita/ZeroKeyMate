-- Preserve all orders, revisions and replay state while permitting products
-- that need no age proof. D1 applies this migration atomically.
CREATE TABLE orders_with_catalogue (
  id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL CHECK (state IN ('awaiting_age','age_verified','payment_ready','payment_pending','payment_expired','complete')),
  value TEXT NOT NULL CHECK (json_valid(value)),
  created_at INTEGER NOT NULL
);
INSERT INTO orders_with_catalogue(id,revision,state,value,created_at)
  SELECT id,revision,state,value,created_at FROM orders;
DROP TABLE orders;
ALTER TABLE orders_with_catalogue RENAME TO orders;
CREATE INDEX orders_created_at ON orders(created_at);
