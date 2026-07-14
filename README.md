# ERP Cron Demo — PostgreSQL + pg_cron

ERP schema on PostgreSQL 16 using the **pg_cron** extension to schedule jobs — all job logic is plain plpgsql functions, and jobs are managed entirely through SQL (`cron.schedule` / `cron.unschedule` / `cron.alter_job`).

## Run

```bash
docker compose up -d --build
```

- `Dockerfile` extends `postgres:16` and installs `postgresql-16-cron` (host port `5434`)
- The compose command sets `shared_preload_libraries=pg_cron` and `cron.database_name=erp`
- Init order: `01_schema.sql` → `02_seed.sql` → `03_functions.sql` (job logic) → `04_cron_jobs.sql` (schedules)

## Jobs

| Job | Demo | Production | Function |
|---|---|---|---|
| `update-exchange-rates` | every minute | `0 * * * *` | `job_update_exchange_rates()` — seeds a new FX rate per pair (random walk) |
| `daily-sales-summary` | every minute | `0 1 * * *` | `job_daily_sales_summary()` — upserts daily sales totals |
| `mark-overdue-invoices` | every minute | `30 0 * * *` | `job_mark_overdue_invoices()` |
| `check-low-stock` | every minute | `0 * * * *` | `job_check_low_stock()` |
| `cleanup` | hourly | `0 2 * * *` | `job_cleanup()` |

## Verify the jobs are firing

```bash
docker exec -it erp-pg-cron psql -U erp -d erp
```

```sql
SELECT jobid, jobname, schedule, command FROM cron.job;

-- pg_cron's own run log (true status of every run, including errors)
SELECT jobname, status, return_message, start_time
FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- application-side log
SELECT * FROM cron_job_logs ORDER BY run_at DESC LIMIT 10;
SELECT * FROM exchange_rates ORDER BY fetched_at DESC LIMIT 8;
SELECT * FROM invoices WHERE status = 'overdue';
SELECT * FROM stock_alerts;
SELECT * FROM daily_sales_summary;
```

## Things to know

- pg_cron only runs jobs in the database named by `cron.database_name` (here: `erp`) — the extension must be created in that database
- Minimum granularity is 1 minute (newer versions also support a `'5 seconds'` syntax)
- Jobs run as background workers inside the database — runs missed while the DB is down are **not** replayed
- Most managed services support pg_cron out of the box (RDS, Cloud SQL, Azure, Supabase, Neon) — just enable the extension, no custom image needed like in this demo

---

## About this demo

This repo is part of the **ERP Cron DB** demo series — one shared ERP schema (master data, sales/purchase orders, invoices, payments) implemented three ways to compare strategies for letting scheduled jobs update/seed data directly in the database (FX rates, daily sales summaries, overdue invoice flagging, low-stock alerts):

| Repo | Engine | Scheduler |
|---|---|---|
| [erp-cron-mysql-events](https://github.com/yunst047/erp-cron-mysql-events) | MySQL 8 | `CREATE EVENT` (built-in) |
| [erp-cron-postgres-pgcron](https://github.com/yunst047/erp-cron-postgres-pgcron) | PostgreSQL 16 | `pg_cron` extension |
| [erp-cron-postgres-go](https://github.com/yunst047/erp-cron-postgres-go) | PostgreSQL 16 | Go service (`robfig/cron`) |

Every job writes to a `cron_job_logs` table, and each stack was spun up and verified end-to-end (jobs firing, data changing as expected) before publishing.

> 🤖 Built and tested entirely by [Claude Code](https://claude.com/claude-code) (Claude Fable 5) — schema design, seed data, cron jobs, Docker setup, and live verification.
