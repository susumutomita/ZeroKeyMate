-- D1 applies this migration atomically. Keep existing orders and their revisions.
CREATE TABLE orders_with_expiry (
  id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL CHECK (state IN ('awaiting_age','age_verified','payment_pending','payment_expired','complete')),
  value TEXT NOT NULL CHECK (json_valid(value)),
  created_at INTEGER NOT NULL
);
INSERT INTO orders_with_expiry(id,revision,state,value,created_at)
  SELECT id,revision,state,value,created_at FROM orders;
DROP TABLE orders;
ALTER TABLE orders_with_expiry RENAME TO orders;
CREATE INDEX orders_created_at ON orders(created_at);
