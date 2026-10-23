-- School ERP: multi-tenant Postgres schema (Phase 1 MVP draft)
-- Tenant isolation: school_id on every tenant table, enforced by RLS.
-- Money rule: payments/ledger are append-only; corrections are reversing entries.

create extension if not exists "pgcrypto";

-- ---------- Tenancy & auth ----------
create table schools (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text,
  phone text,
  currency char(3) not null default 'PKR',
  created_at timestamptz not null default now()
);

create table branches (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  name text not null,
  address text,
  unique (school_id, name)
);

create type user_role as enum ('owner','admin','accountant','teacher','parent');

create table school_users (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  auth_user_id uuid not null,              -- Supabase auth.users.id
  role user_role not null,
  branch_id uuid references branches(id),  -- null = all branches
  full_name text not null,
  phone text,
  active boolean not null default true,
  unique (school_id, auth_user_id, role)
);

create table academic_years (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  name text not null,                      -- e.g. 2026-27
  starts_on date not null,
  ends_on date not null,
  is_current boolean not null default false,
  unique (school_id, name)
);

create table classes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  branch_id uuid not null references branches(id),
  name text not null,                      -- Class 5
  sort_order int not null default 0,
  unique (school_id, branch_id, name)
);

create table sections (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  class_id uuid not null references classes(id),
  name text not null,                      -- A
  class_teacher_id uuid references school_users(id),
  unique (class_id, name)
);

-- ---------- Students & guardians ----------
create table guardians (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  user_id uuid references school_users(id),  -- parent login, optional
  full_name text not null,
  phone text not null,                       -- WhatsApp/SMS target
  cnic text,
  unique (school_id, phone)
);

create table students (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  branch_id uuid not null references branches(id),
  admission_no text not null,
  full_name text not null,
  gender text,
  dob date,
  admitted_on date,
  status text not null default 'active',     -- active, left, graduated
  created_at timestamptz not null default now(),
  unique (school_id, admission_no)
);

-- Sibling linking = many students to one guardian
create table student_guardians (
  school_id uuid not null references schools(id),
  student_id uuid not null references students(id),
  guardian_id uuid not null references guardians(id),
  relation text,
  is_primary boolean not null default false,
  primary key (student_id, guardian_id)
);

create table enrollments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  student_id uuid not null references students(id),
  academic_year_id uuid not null references academic_years(id),
  section_id uuid not null references sections(id),
  roll_no text,
  unique (student_id, academic_year_id)
);

-- ---------- Fees ----------
create table fee_heads (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  name text not null,                        -- Tuition, Admission, Exam, Transport
  recurring boolean not null default true,
  unique (school_id, name)
);

create table fee_structures (                -- amount per class per head per year
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  academic_year_id uuid not null references academic_years(id),
  class_id uuid not null references classes(id),
  fee_head_id uuid not null references fee_heads(id),
  amount numeric(12,2) not null check (amount >= 0),
  unique (academic_year_id, class_id, fee_head_id)
);

create table discounts (                     -- per student: sibling, scholarship, staff child
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  enrollment_id uuid not null references enrollments(id),
  fee_head_id uuid references fee_heads(id), -- null = all heads
  kind text not null,                        -- sibling, scholarship, staff, other
  percent numeric(5,2),
  fixed_amount numeric(12,2),
  check (percent is not null or fixed_amount is not null)
);

create table challans (                      -- one per student per billing period
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  enrollment_id uuid not null references enrollments(id),
  challan_no text not null,
  period text not null,                      -- 2026-11
  due_date date not null,
  status text not null default 'issued',     -- issued, partial, paid, void
  created_at timestamptz not null default now(),
  unique (school_id, challan_no),
  unique (enrollment_id, period)
);

create table challan_lines (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  challan_id uuid not null references challans(id),
  fee_head_id uuid not null references fee_heads(id),
  description text,
  amount numeric(12,2) not null            -- negative for discounts, arrears carried as own line
);

-- Append-only ledger: charges are +, payments are -. Never UPDATE/DELETE.
create table ledger_entries (
  id bigint generated always as identity primary key,
  school_id uuid not null references schools(id),
  enrollment_id uuid not null references enrollments(id),
  challan_id uuid references challans(id),
  entry_type text not null check (entry_type in ('charge','payment','reversal','adjustment')),
  amount numeric(12,2) not null,             -- charge +, payment -
  method text,                               -- cash, bank, jazzcash, easypaisa
  reference text,
  reverses_entry_id bigint references ledger_entries(id),
  note text,
  created_by uuid references school_users(id),
  created_at timestamptz not null default now()
);

create table receipts (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  receipt_no text not null,
  ledger_entry_id bigint not null references ledger_entries(id),
  unique (school_id, receipt_no)
);

-- Enforce append-only
create function forbid_ledger_change() returns trigger language plpgsql as $$
begin
  raise exception 'ledger_entries is append-only; insert a reversal instead';
end $$;

create trigger ledger_no_update before update or delete on ledger_entries
  for each row execute function forbid_ledger_change();

-- Balance per student (arrears = positive balance)
create view student_balances as
select school_id, enrollment_id, sum(amount) as balance
from ledger_entries group by school_id, enrollment_id;

-- Defaulters: overdue challans with outstanding balance
create view defaulters as
select b.school_id, b.enrollment_id, b.balance, min(c.due_date) as oldest_due
from student_balances b
join challans c on c.enrollment_id = b.enrollment_id and c.status in ('issued','partial')
where b.balance > 0 and c.due_date < current_date
group by b.school_id, b.enrollment_id, b.balance;

-- ---------- Attendance ----------
create table attendance (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  enrollment_id uuid not null references enrollments(id),
  date date not null,
  status text not null check (status in ('present','absent','late','leave')),
  marked_by uuid references school_users(id),
  client_id uuid,                            -- idempotency key for offline (Hive) sync
  marked_at timestamptz not null default now(),
  synced_at timestamptz not null default now(),
  unique (enrollment_id, date),
  unique (school_id, client_id)
);
create index on attendance (school_id, date);

-- ---------- Messaging ----------
create table message_log (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references schools(id),
  guardian_id uuid not null references guardians(id),
  kind text not null,                        -- fee_reminder, absence
  channel text not null,                     -- sms, whatsapp_link, whatsapp_api
  body text not null,
  status text not null default 'queued',     -- queued, sent, failed
  created_at timestamptz not null default now()
);

create table audit_log (
  id bigint generated always as identity primary key,
  school_id uuid not null references schools(id),
  actor_id uuid references school_users(id),
  action text not null,
  entity text not null,
  entity_id text,
  detail jsonb,
  created_at timestamptz not null default now()
);

-- ---------- Row-level security ----------
create function current_school_ids() returns setof uuid
language sql stable security definer as $$
  select school_id from school_users
  where auth_user_id = auth.uid() and active
$$;

-- Apply to every tenant table (loop keeps it DRY).
do $$
declare t text;
begin
  foreach t in array array[
    'branches','school_users','academic_years','classes','sections','guardians',
    'students','student_guardians','enrollments','fee_heads','fee_structures',
    'discounts','challans','challan_lines','ledger_entries','receipts',
    'attendance','message_log','audit_log']
  loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy tenant_isolation on %I using (school_id in (select current_school_ids())) with check (school_id in (select current_school_ids()))', t);
  end loop;
end $$;

-- TODO (next pass): role-specific policies (teacher: attendance only for own sections;
-- parent: read-only own children via student_guardians; accountant: ledger insert only).
