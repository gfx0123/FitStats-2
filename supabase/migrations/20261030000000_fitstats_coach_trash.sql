-- What the coach deleted (a routine, a logged workout, a journal day), kept for 30 days so it
-- can be put back (the coach's restore_deleted tool). kind: routine | workout_log | journal;
-- item: the row as it was.
create table if not exists public.fs_coach_trash (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('routine', 'workout_log', 'journal')),
  item jsonb not null,
  label text,
  deleted_at timestamptz not null default now()
);

create index if not exists fs_coach_trash_deleted_at on public.fs_coach_trash (deleted_at desc);

alter table public.fs_coach_trash enable row level security;
revoke all on table public.fs_coach_trash from anon, authenticated;
grant all on table public.fs_coach_trash to service_role;
