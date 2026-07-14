# ERP Cron Demo — PostgreSQL + pg_cron

ERP schema บน PostgreSQL 16 ใช้ extension **pg_cron** schedule งาน — logic เป็น plpgsql function ทั้งหมด จัดการ job ผ่าน SQL (`cron.schedule` / `cron.unschedule` / `cron.alter_job`)

## Run

```bash
docker compose up -d --build
```

- `Dockerfile` ต่อยอดจาก `postgres:16` + ติดตั้ง `postgresql-16-cron` (host port `5434`)
- compose command ตั้ง `shared_preload_libraries=pg_cron` และ `cron.database_name=erp`
- Init: `01_schema.sql` → `02_seed.sql` → `03_functions.sql` (job logic) → `04_cron_jobs.sql` (schedule)

## Jobs

| Job | Demo | Production | Function |
|---|---|---|---|
| `update-exchange-rates` | ทุกนาที | `0 * * * *` | `job_update_exchange_rates()` — seed FX rate ใหม่ (random walk) |
| `daily-sales-summary` | ทุกนาที | `0 1 * * *` | `job_daily_sales_summary()` — upsert ยอดขายรายวัน |
| `mark-overdue-invoices` | ทุกนาที | `30 0 * * *` | `job_mark_overdue_invoices()` |
| `check-low-stock` | ทุกนาที | `0 * * * *` | `job_check_low_stock()` |
| `cleanup` | ทุกชั่วโมง | `0 2 * * *` | `job_cleanup()` |

## Verify ว่า cron วิ่งจริง

```bash
docker exec -it erp-pg-cron psql -U erp -d erp
```

```sql
SELECT jobid, jobname, schedule, command FROM cron.job;

-- log ภายในของ pg_cron (สถานะจริงของทุก run รวม error)
SELECT jobname, status, return_message, start_time
FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- log ฝั่ง application
SELECT * FROM cron_job_logs ORDER BY run_at DESC LIMIT 10;
SELECT * FROM exchange_rates ORDER BY fetched_at DESC LIMIT 8;
SELECT * FROM invoices WHERE status = 'overdue';
SELECT * FROM stock_alerts;
SELECT * FROM daily_sales_summary;
```

## ข้อควรรู้

- pg_cron รัน job ใน database ที่ระบุใน `cron.database_name` เท่านั้น (ที่นี่คือ `erp`) — extension ต้องถูก CREATE ใน DB นั้น
- Granularity ต่ำสุดคือ 1 นาที (เวอร์ชันใหม่รองรับ `'5 seconds'` syntax ด้วย)
- Job รันเป็น background worker ใน DB เอง — ถ้า DB down, job ที่พลาดรอบจะ **ไม่** ถูก replay ย้อนหลัง
- managed services รองรับ pg_cron เกือบหมด (RDS, Cloud SQL, Azure, Supabase, Neon) แค่เปิด extension — ไม่ต้อง build image เองแบบ demo นี้


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
