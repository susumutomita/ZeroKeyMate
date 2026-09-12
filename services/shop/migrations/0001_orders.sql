-- No birth dates, card data, identity documents, PINs or raw proofs.
CREATE TABLE orders (
  id TEXT PRIMARY KEY,
  revision INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL CHECK (state IN ('awaiting_age','age_verified','payment_pending','complete')),
  value TEXT NOT NULL CHECK (json_valid(value)),
  created_at INTEGER NOT NULL
);
CREATE INDEX orders_created_at ON orders(created_at);
