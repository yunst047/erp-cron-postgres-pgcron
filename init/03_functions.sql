-- =====================================================
-- Job logic เขียนเป็น plpgsql function — pg_cron แค่เรียก
-- SELECT job_xxx() ตาม schedule
-- ทุก function เขียน cron_job_logs และ swallow error ลง log
-- =====================================================

-- 1) Seed exchange rates (จำลอง external FX feed: random walk ±0.5% จากเรทล่าสุด)
CREATE OR REPLACE FUNCTION job_update_exchange_rates() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  n INT;
BEGIN
  INSERT INTO exchange_rates (base_currency, quote_currency, rate, fetched_at)
  SELECT DISTINCT ON (base_currency, quote_currency)
         base_currency,
         quote_currency,
         round((rate * (1 + ((random() - 0.5) * 0.01)))::numeric, 6),
         now()
  FROM exchange_rates
  ORDER BY base_currency, quote_currency, fetched_at DESC;

  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_update_exchange_rates', 'success', format('seeded %s new rate rows', n));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_update_exchange_rates', 'error', SQLERRM);
END;
$$;

-- 2) Upsert daily sales summary (7 วันล่าสุด)
CREATE OR REPLACE FUNCTION job_daily_sales_summary() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO daily_sales_summary (summary_date, total_orders, total_revenue, avg_order_value, generated_at)
  SELECT order_date::date,
         COUNT(*),
         COALESCE(SUM(total_amount), 0),
         COALESCE(AVG(total_amount), 0),
         now()
  FROM sales_orders
  WHERE status <> 'cancelled'
    AND order_date >= CURRENT_DATE - 7
  GROUP BY order_date::date
  ON CONFLICT (summary_date) DO UPDATE SET
    total_orders    = EXCLUDED.total_orders,
    total_revenue   = EXCLUDED.total_revenue,
    avg_order_value = EXCLUDED.avg_order_value,
    generated_at    = now();

  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_daily_sales_summary', 'success', 'summary upserted for last 7 days');
EXCEPTION WHEN OTHERS THEN
  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_daily_sales_summary', 'error', SQLERRM);
END;
$$;

-- 3) Mark overdue invoices
CREATE OR REPLACE FUNCTION job_mark_overdue_invoices() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  n INT;
BEGIN
  UPDATE invoices
  SET status = 'overdue'
  WHERE status = 'pending'
    AND due_date < CURRENT_DATE;

  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_mark_overdue_invoices', 'success', format('%s invoice(s) marked overdue', n));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_mark_overdue_invoices', 'error', SQLERRM);
END;
$$;

-- 4) Low-stock alerts (skip ถ้ามี alert เปิดค้างอยู่แล้ว)
CREATE OR REPLACE FUNCTION job_check_low_stock() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  n INT;
BEGIN
  INSERT INTO stock_alerts (product_id, warehouse, current_qty, reorder_level)
  SELECT i.product_id, i.warehouse, i.quantity, p.reorder_level
  FROM inventory i
  JOIN products p ON p.id = i.product_id
  WHERE i.quantity <= p.reorder_level
    AND p.is_active
    AND NOT EXISTS (
      SELECT 1 FROM stock_alerts a
      WHERE a.product_id = i.product_id
        AND a.warehouse  = i.warehouse
        AND a.alert_status = 'open'
    );

  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_check_low_stock', 'success', format('%s new alert(s)', n));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_check_low_stock', 'error', SQLERRM);
END;
$$;

-- 5) Housekeeping
CREATE OR REPLACE FUNCTION job_cleanup() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM cron_job_logs  WHERE run_at     < now() - INTERVAL '7 days';
  DELETE FROM exchange_rates WHERE fetched_at < now() - INTERVAL '30 days';

  INSERT INTO cron_job_logs (job_name, status, message)
  VALUES ('job_cleanup', 'success', 'old logs and fx history trimmed');
END;
$$;
