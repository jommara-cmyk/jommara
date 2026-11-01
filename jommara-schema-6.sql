-- =====================================================
-- جمّارة Jommara — المرحلة 6: الكروبات الخاصة (بيوزر) + قصص الكروب
-- الصق هذا كله في SQL Editor ثم اضغط Run (آمن لو شغّلته مرتين)
-- يتطلب المراحل 1 إلى 5
-- =====================================================

-- يوزر الكروب + كروب خاص (لا يظهر في القائمة، ينضم إليه الطالب باليوزر فقط)
alter table public.groups add column if not exists un text;
alter table public.groups add column if not exists priv boolean not null default false;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'groups_un_fmt') then
    alter table public.groups add constraint groups_un_fmt check (un is null or un ~ '^[A-Za-z][A-Za-z0-9_]{3,19}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'groups_priv_needs_un') then
    alter table public.groups add constraint groups_priv_needs_un check (not priv or un is not null);
  end if;
end $$;
create unique index if not exists groups_un_lower on public.groups (lower(un)) where un is not null;

-- دوال مساعدة (SECURITY DEFINER لتجنب التكرار الدائري في السياسات)
create or replace function public.is_group_member(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members m where m.group_id = gid and m.user_id = auth.uid())
$$;
grant execute on function public.is_group_member(uuid) to authenticated;

create or replace function public.group_visible(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.groups g
    where g.id = gid and (
      not g.priv or g.created_by = auth.uid() or public.is_group_mgr(g.id) or public.is_group_member(g.id)
    )
  )
$$;
grant execute on function public.group_visible(uuid) to authenticated;

-- القراءة: الكروب الخاص لا يراه إلا أعضاؤه ومشرفوه
drop policy if exists groups_read on public.groups;
-- (شروط على السطر نفسه ليعمل الإدراج مع RETURNING)
create policy groups_read on public.groups for select to authenticated
  using (not priv or created_by = auth.uid() or public.is_group_mgr(id) or public.is_group_member(id));

drop policy if exists gm_read on public.group_members;
create policy gm_read on public.group_members for select to authenticated
  using (user_id = auth.uid() or public.group_visible(group_id));

-- الانضمام المباشر للكروب العام فقط، والخاص عبر الدالة بالأسفل
drop policy if exists gm_ins on public.group_members;
create policy gm_ins on public.group_members for insert to authenticated with check (
  user_id = auth.uid() and exists (
    select 1 from public.groups g where g.id = group_id and (not g.priv or public.is_group_mgr(g.id))
  )
);

drop policy if exists gmsg_read on public.group_messages;
create policy gmsg_read on public.group_messages for select to authenticated using (public.group_visible(group_id));

-- البحث بيوزر الكروب والانضمام إليه
create or replace function public.group_by_un(u text)
returns table(id uuid, name text, img text, unit_key text, un text, priv boolean, n bigint)
language sql stable security definer set search_path = '' as $$
  select g.id, g.name, g.img, g.unit_key, g.un, g.priv,
         (select count(*) from public.group_members m where m.group_id = g.id)
  from public.groups g where lower(g.un) = lower(trim(both '@' from u))
$$;
grant execute on function public.group_by_un(text) to authenticated;

create or replace function public.join_group_by_un(u text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare gid uuid;
begin
  if auth.uid() is null then raise exception 'auth' using errcode = '42501'; end if;
  select g.id into gid from public.groups g where lower(g.un) = lower(trim(both '@' from u));
  if gid is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  insert into public.group_members (group_id, user_id) values (gid, auth.uid()) on conflict do nothing;
  return gid;
end $$;
grant execute on function public.join_group_by_un(text) to authenticated;

-- ---------- قصص الكروب (24 ساعة) ----------
create table if not exists public.group_stories (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 120),
  img text,
  bg text,
  created_at timestamptz not null default now()
);
create index if not exists gst_idx on public.group_stories (group_id, created_at desc);
alter table public.group_stories enable row level security;
drop policy if exists gst_read on public.group_stories;
create policy gst_read on public.group_stories for select to authenticated
  using (created_at > now() - interval '24 hours' and public.group_visible(group_id));
drop policy if exists gst_ins on public.group_stories;
create policy gst_ins on public.group_stories for insert to authenticated with check (
  author = auth.uid() and (public.is_group_mgr(group_id) or public.is_group_member(group_id))
);
drop policy if exists gst_del on public.group_stories;
create policy gst_del on public.group_stories for delete to authenticated
  using (author = auth.uid() or public.is_group_mgr(group_id));

revoke all on public.group_stories from anon;
grant select, insert, delete on public.group_stories to authenticated;
