-- =====================================================
-- جمّارة Jommara — المرحلة 4: الكروبات ورسائلها والصلاحيات (مشتركة بين كل الطلبة)
-- الصق هذا كله في SQL Editor ثم اضغط Run (آمن لو شغّلته مرتين)
-- يتطلب أن تكون شغّلت المراحل 1 و 2 و 3 من قبل
-- =====================================================

-- ---------- الأدوار: مسؤول جامعة / مشرف كلية أو قسم (التعيين لك أنت فقط) ----------
create table if not exists public.roles (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('univ', 'mod')),
  scope text not null,          -- univ: "جامعة الموصل" | mod: "جامعة الموصل|التمريض" أو "جامعة الموصل|الهندسة|قسم كذا"
  created_at timestamptz not null default now(),
  unique (user_id, role, scope)
);
alter table public.roles enable row level security;
drop policy if exists roles_read on public.roles;
create policy roles_read on public.roles for select to authenticated using (true);
drop policy if exists roles_admin_ins on public.roles;
create policy roles_admin_ins on public.roles for insert to authenticated with check (public.is_admin());
drop policy if exists roles_admin_del on public.roles;
create policy roles_admin_del on public.roles for delete to authenticated using (public.is_admin());

-- هل المنفِّذ مشرف عام أو له دور يغطي هذا المكان؟ (المفتاح: جامعة|كلية|قسم|دراسة)
create or replace function public.has_scope(uk text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.is_admin() or exists (
    select 1 from public.roles r
    where r.user_id = auth.uid() and (uk = r.scope or uk like r.scope || '|%')
  )
$$;
grant execute on function public.has_scope(text) to authenticated;

-- ---------- الكروبات ----------
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  unit_key text not null,       -- جامعة|كلية|قسم أو *|m أو e
  name text not null check (char_length(name) between 3 and 40),
  img text,
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  reps uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (unit_key, name)
);
create index if not exists groups_unit_idx on public.groups (unit_key);
alter table public.groups enable row level security;

create or replace function public.is_group_mgr(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.groups g
    where g.id = gid and (public.has_scope(g.unit_key) or auth.uid() = any (g.reps))
  )
$$;
grant execute on function public.is_group_mgr(uuid) to authenticated;

drop policy if exists groups_read on public.groups;
create policy groups_read on public.groups for select to authenticated using (true);

-- إنشاء كروب: المشرف العام، أو من له دور يغطي المكان، أو ممثل كروب في نفس الكلية
drop policy if exists groups_ins on public.groups;
create policy groups_ins on public.groups for insert to authenticated with check (
  created_by = auth.uid() and (
    public.has_scope(unit_key)
    or exists (
      select 1 from public.groups g
      where auth.uid() = any (g.reps)
        and split_part(g.unit_key, '|', 1) = split_part(groups.unit_key, '|', 1)
        and split_part(g.unit_key, '|', 2) = split_part(groups.unit_key, '|', 2)
    )
  )
);
drop policy if exists groups_upd on public.groups;
create policy groups_upd on public.groups for update to authenticated
  using (public.is_group_mgr(id)) with check (public.is_group_mgr(id));
drop policy if exists groups_del on public.groups;
create policy groups_del on public.groups for delete to authenticated
  using (public.has_scope(unit_key) or created_by = auth.uid());

-- تعيين الممثلين للمشرف العام فقط
create or replace function public.groups_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.unit_key := old.unit_key;   -- لا يتغيّر مكان الكروب بعد إنشائه
    if new.reps is distinct from old.reps and not public.is_admin() then
      raise exception 'only_admin_appoints' using errcode = '42501';
    end if;
  else
    if cardinality(new.reps) > 0 and not public.is_admin() then new.reps := '{}'; end if;
  end if;
  return new;
end $$;
drop trigger if exists groups_guard_t on public.groups;
create trigger groups_guard_t before insert or update on public.groups
  for each row execute function public.groups_guard();

-- ---------- عضوية الكروب: كل طالب في كروب واحد فقط ----------
create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists gm_user_idx on public.group_members (user_id);
alter table public.group_members enable row level security;
drop policy if exists gm_read on public.group_members;
create policy gm_read on public.group_members for select to authenticated using (true);
drop policy if exists gm_ins on public.group_members;
create policy gm_ins on public.group_members for insert to authenticated with check (user_id = auth.uid());
drop policy if exists gm_del on public.group_members;
create policy gm_del on public.group_members for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

create or replace function public.gm_one_group() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() and exists (
    select 1 from public.group_members m where m.user_id = new.user_id and m.group_id <> new.group_id
  ) then
    raise exception 'one_group' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists gm_one_group_t on public.group_members;
create trigger gm_one_group_t before insert on public.group_members
  for each row execute function public.gm_one_group();

-- عدد أعضاء كل كروب في مكان معيّن
create or replace function public.group_counts(uk text)
returns table(group_id uuid, n bigint)
language sql stable security invoker set search_path = '' as $$
  select m.group_id, count(*) from public.group_members m
  join public.groups g on g.id = m.group_id
  where g.unit_key = uk group by m.group_id
$$;
grant execute on function public.group_counts(text) to authenticated;

-- ---------- رسائل الكروب ----------
create table if not exists public.group_messages (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.groups(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 2000),
  media jsonb not null default '[]'::jsonb,
  reply jsonb,
  pinned boolean not null default false,
  edited boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists gmsg_idx on public.group_messages (group_id, id);
alter table public.group_messages enable row level security;
drop policy if exists gmsg_read on public.group_messages;
create policy gmsg_read on public.group_messages for select to authenticated using (true);
drop policy if exists gmsg_ins on public.group_messages;
create policy gmsg_ins on public.group_messages for insert to authenticated with check (
  author = auth.uid() and (
    public.is_group_mgr(group_id)
    or exists (select 1 from public.group_members m where m.group_id = group_messages.group_id and m.user_id = auth.uid())
  )
);
drop policy if exists gmsg_upd on public.group_messages;
create policy gmsg_upd on public.group_messages for update to authenticated
  using (author = auth.uid() or public.is_group_mgr(group_id))
  with check (author = auth.uid() or public.is_group_mgr(group_id));
drop policy if exists gmsg_del on public.group_messages;
create policy gmsg_del on public.group_messages for delete to authenticated
  using (author = auth.uid() or public.is_group_mgr(group_id));

-- غير صاحب الرسالة (المشرف) لا يغيّر إلا التثبيت، والطالب العادي لا يثبّت
create or replace function public.gmsg_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is distinct from old.author then
    new.body := old.body; new.media := old.media; new.reply := old.reply; new.edited := old.edited;
  end if;
  new.author := old.author; new.group_id := old.group_id; new.created_at := old.created_at;
  if new.pinned is distinct from old.pinned and not (public.is_group_mgr(old.group_id) or auth.uid() = old.author) then
    new.pinned := old.pinned;
  end if;
  return new;
end $$;
drop trigger if exists gmsg_guard_t on public.group_messages;
create trigger gmsg_guard_t before update on public.group_messages
  for each row execute function public.gmsg_guard();

-- ---------- مرفقات الكروب (صور/ملفات/صوت) ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('gmedia', 'gmedia', true, 20971520)
on conflict (id) do update set public = true, file_size_limit = 20971520;
drop policy if exists gmedia_read on storage.objects;
create policy gmedia_read on storage.objects for select using (bucket_id = 'gmedia');
drop policy if exists gmedia_ins on storage.objects;
create policy gmedia_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'gmedia' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- صلاحيات التنفيذ ----------
revoke all on public.roles, public.groups, public.group_members, public.group_messages from anon;
grant select, insert, update, delete on public.roles, public.groups, public.group_members, public.group_messages to authenticated;
