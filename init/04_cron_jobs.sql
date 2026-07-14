-- =====================================================
-- pg_cron schedules
-- ต้องมี shared_preload_libraries=pg_cron และ cron.database_name=erp
-- (ตั้งไว้แล้วใน docker-compose command)
--
-- NOTE: demo schedules are aggressive (every minute) so you can
-- watch them fire — production schedules noted per job.
--
-- จัดการ job ภายหลัง:
--   SELECT * FROM cron.job;
--   SELECT cron.unschedule('update-exchange-rates');
--   SELECT cron.alter_job(job_id, schedule => '0 * * * *');
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- production: '0 * * * *' (ทุกชั่วโมง)
SELECT cron.schedule('update-exchange-rates', '* * * * *',
                     $$SELECT job_update_exchange_rates()$$);

-- production: '0 1 * * *' (ตี 1 ทุกวัน)
SELECT cron.schedule('daily-sales-summary', '* * * * *',
                     $$SELECT job_daily_sales_summary()$$);

-- production: '30 0 * * *'
SELECT cron.schedule('mark-overdue-invoices', '* * * * *',
                     $$SELECT job_mark_overdue_invoices()$$);

-- production: '0 * * * *'
SELECT cron.schedule('check-low-stock', '* * * * *',
                     $$SELECT job_check_low_stock()$$);

-- housekeeping ทุกชั่วโมง (production: '0 2 * * *')
SELECT cron.schedule('cleanup', '0 * * * *',
                     $$SELECT job_cleanup()$$);

-- เก็บ log ภายในของ pg_cron เองไม่ให้บวม (built-in table)
SELECT cron.schedule('purge-cron-run-details', '0 3 * * *',
                     $$DELETE FROM cron.job_run_details WHERE end_time < now() - INTERVAL '7 days'$$);
