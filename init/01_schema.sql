-- =====================================================
-- ERP Schema (PostgreSQL 16) — master data + transactions
-- + tables maintained by pg_cron jobs
-- =====================================================

-- ---------- Master data ----------

CREATE TABLE departments (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(100) NOT NULL UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE employees (
  id            SERIAL PRIMARY KEY,
  department_id INT NOT NULL REFERENCES departments(id),
  first_name    VARCHAR(100) NOT NULL,
  last_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(255) NOT NULL UNIQUE,
  position      VARCHAR(100),
  salary        NUMERIC(12,2) NOT NULL DEFAULT 0,
  hired_at      DATE,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE customers (
  id           SERIAL PRIMARY KEY,
  code         VARCHAR(20) NOT NULL UNIQUE,
  name         VARCHAR(200) NOT NULL,
  email        VARCHAR(255),
  phone        VARCHAR(50),
  credit_limit NUMERIC(14,2) NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE suppliers (
  id         SERIAL PRIMARY KEY,
  code       VARCHAR(20) NOT NULL UNIQUE,
  name       VARCHAR(200) NOT NULL,
  email      VARCHAR(255),
  phone      VARCHAR(50),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE product_categories (
  id   SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE products (
  id            SERIAL PRIMARY KEY,
  category_id   INT NOT NULL REFERENCES product_categories(id),
  sku           VARCHAR(50) NOT NULL UNIQUE,
  name          VARCHAR(200) NOT NULL,
  unit_price    NUMERIC(12,2) NOT NULL,
  cost_price    NUMERIC(12,2) NOT NULL,
  reorder_level INT NOT NULL DEFAULT 10,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE inventory (
  id         SERIAL PRIMARY KEY,
  product_id INT NOT NULL REFERENCES products(id),
  warehouse  VARCHAR(50) NOT NULL DEFAULT 'MAIN',
  quantity   INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (product_id, warehouse)
);

-- ---------- Transactions ----------

CREATE TYPE order_status   AS ENUM ('draft','confirmed','shipped','completed','cancelled');
CREATE TYPE po_status      AS ENUM ('draft','sent','received','cancelled');
CREATE TYPE invoice_status AS ENUM ('pending','paid','overdue','cancelled');
CREATE TYPE payment_method AS ENUM ('transfer','credit_card','cash','cheque');

CREATE TABLE sales_orders (
  id           SERIAL PRIMARY KEY,
  order_no     VARCHAR(30) NOT NULL UNIQUE,
  customer_id  INT NOT NULL REFERENCES customers(id),
  status       order_status NOT NULL DEFAULT 'confirmed',
  order_date   TIMESTAMPTZ NOT NULL DEFAULT now(),
  currency     CHAR(3) NOT NULL DEFAULT 'THB',
  total_amount NUMERIC(14,2) NOT NULL DEFAULT 0
);
CREATE INDEX idx_so_date ON sales_orders (order_date);

CREATE TABLE sales_order_items (
  id         SERIAL PRIMARY KEY,
  order_id   INT NOT NULL REFERENCES sales_orders(id),
  product_id INT NOT NULL REFERENCES products(id),
  quantity   INT NOT NULL,
  unit_price NUMERIC(12,2) NOT NULL
);

CREATE TABLE purchase_orders (
  id           SERIAL PRIMARY KEY,
  po_no        VARCHAR(30) NOT NULL UNIQUE,
  supplier_id  INT NOT NULL REFERENCES suppliers(id),
  status       po_status NOT NULL DEFAULT 'sent',
  order_date   TIMESTAMPTZ NOT NULL DEFAULT now(),
  total_amount NUMERIC(14,2) NOT NULL DEFAULT 0
);

CREATE TABLE purchase_order_items (
  id         SERIAL PRIMARY KEY,
  po_id      INT NOT NULL REFERENCES purchase_orders(id),
  product_id INT NOT NULL REFERENCES products(id),
  quantity   INT NOT NULL,
  unit_cost  NUMERIC(12,2) NOT NULL
);

CREATE TABLE invoices (
  id         SERIAL PRIMARY KEY,
  invoice_no VARCHAR(30) NOT NULL UNIQUE,
  order_id   INT NOT NULL REFERENCES sales_orders(id),
  issue_date DATE NOT NULL,
  due_date   DATE NOT NULL,
  amount     NUMERIC(14,2) NOT NULL,
  status     invoice_status NOT NULL DEFAULT 'pending'
);
CREATE INDEX idx_inv_status_due ON invoices (status, due_date);

CREATE TABLE payments (
  id         SERIAL PRIMARY KEY,
  invoice_id INT NOT NULL REFERENCES invoices(id),
  paid_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  amount     NUMERIC(14,2) NOT NULL,
  method     payment_method NOT NULL DEFAULT 'transfer'
);

-- ---------- Tables maintained by pg_cron ----------

-- seeded every minute by job_update_exchange_rates() (keeps history)
CREATE TABLE exchange_rates (
  id             SERIAL PRIMARY KEY,
  base_currency  CHAR(3) NOT NULL,
  quote_currency CHAR(3) NOT NULL,
  rate           NUMERIC(18,6) NOT NULL,
  fetched_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_fx_pair_time ON exchange_rates (base_currency, quote_currency, fetched_at);

-- upserted by job_daily_sales_summary()
CREATE TABLE daily_sales_summary (
  id              SERIAL PRIMARY KEY,
  summary_date    DATE NOT NULL UNIQUE,
  total_orders    INT NOT NULL DEFAULT 0,
  total_revenue   NUMERIC(16,2) NOT NULL DEFAULT 0,
  avg_order_value NUMERIC(16,2) NOT NULL DEFAULT 0,
  generated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- inserted by job_check_low_stock()
CREATE TABLE stock_alerts (
  id            SERIAL PRIMARY KEY,
  product_id    INT NOT NULL REFERENCES products(id),
  warehouse     VARCHAR(50) NOT NULL,
  current_qty   INT NOT NULL,
  reorder_level INT NOT NULL,
  alert_status  VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (alert_status IN ('open','resolved')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- every job writes here — check this table to verify cron is firing
-- (pg_cron also keeps its own log in cron.job_run_details)
CREATE TABLE cron_job_logs (
  id       SERIAL PRIMARY KEY,
  job_name VARCHAR(100) NOT NULL,
  run_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  status   VARCHAR(20) NOT NULL DEFAULT 'success' CHECK (status IN ('success','error')),
  message  VARCHAR(500)
);
CREATE INDEX idx_log_job_time ON cron_job_logs (job_name, run_at);
