-- =====================================================
-- pg_cron schedules
-- Requires shared_preload_libraries=pg_cron and cron.database_name=erp
-- (already set via docker-compose command)
--
-- NOTE: demo schedules are aggressive (every minute) so you can
-- watch them fire — production schedules noted per job.
--
-- Managing jobs later:
--   SELECT * FROM cron.job;
--   SELECT cron.unschedule('update-exchange-rates');
--   SELECT cron.alter_job(job_id, schedule => '0 * * * *');
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- production: '0 * * * *' (hourly)
SELECT cron.schedule('update-exchange-rates', '* * * * *',
                     $$SELECT job_update_exchange_rates()$$);

-- production: '0 1 * * *' (daily at 01:00)
SELECT cron.schedule('daily-sales-summary', '* * * * *',
                     $$SELECT job_daily_sales_summary()$$);

-- production: '30 0 * * *'
SELECT cron.schedule('mark-overdue-invoices', '* * * * *',
                     $$SELECT job_mark_overdue_invoices()$$);

-- production: '0 * * * *'
SELECT cron.schedule('check-low-stock', '* * * * *',
                     $$SELECT job_check_low_stock()$$);

-- housekeeping hourly (production: '0 2 * * *')
SELECT cron.schedule('cleanup', '0 * * * *',
                     $$SELECT job_cleanup()$$);

-- keep pg_cron's own run-detail log from growing unbounded (built-in table)
SELECT cron.schedule('purge-cron-run-details', '0 3 * * *',
                     $$DELETE FROM cron.job_run_details WHERE end_time < now() - INTERVAL '7 days'$$);
