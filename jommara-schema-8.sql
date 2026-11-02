-- =====================================================
-- جمّارة Jommara — المرحلة 8: محادثة الفريق (كروب كامل لكل فريق)
-- يتطلب المراحل 1 إلى 7. الصقه كله في SQL Editor ثم Run (آمن لو شغّلته مرتين)
-- =====================================================

alter table public.groups add column if not exists team_id uuid references public.teams(id) on delete cascade;
create unique index if not exists groups_team_uq on public.groups (team_id) where team_id is not null;

-- عضو الكروب: مشترك فيه، أو لاعب في الفريق صاحب الكروب
create or replace function public.is_group_member(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members m where m.group_id = gid and m.user_id = auth.uid())
      or exists (select 1 from public.groups g join public.team_members tm on tm.team_id = g.team_id
                 where g.id = gid and tm.user_id = auth.uid())
$$;
-- مشرف الكروب: كما كان، أو مشرف الفريق صاحب الكروب
create or replace function public.is_group_mgr(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.groups g
    where g.id = gid and (public.has_scope(g.unit_key) or auth.uid() = any (g.reps)
      or (g.team_id is not null and exists (select 1 from public.teams t where t.id = g.team_id and t.owner = auth.uid())))
  )
$$;
-- ظهور الكروب: كروب الفريق لأعضاء الفريق فقط
create or replace function public.group_visible(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.groups g
    where g.id = gid and (
      case when g.team_id is not null then public.is_team_member(g.team_id)
      else (not g.priv or g.created_by = auth.uid() or public.is_group_mgr(g.id) or public.is_group_member(g.id)) end
    )
  )
$$;
grant execute on function public.is_group_member(uuid), public.is_group_mgr(uuid), public.group_visible(uuid) to authenticated;

drop policy if exists groups_read on public.groups;
create policy groups_read on public.groups for select to authenticated using (
  case when team_id is not null then public.is_team_member(team_id)
  else (not priv or created_by = auth.uid() or public.is_group_mgr(id) or public.is_group_member(id)) end
);

-- لا أحد ينضم لكروب الفريق بإدراج نفسه: العضوية من الفريق نفسه
drop policy if exists gm_ins on public.group_members;
create policy gm_ins on public.group_members for insert to authenticated with check (
  user_id = auth.uid() and exists (
    select 1 from public.groups g where g.id = group_id and g.team_id is null and (not g.priv or public.is_group_mgr(g.id))
  )
);

drop policy if exists gmsg_ins on public.group_messages;
create policy gmsg_ins on public.group_messages for insert to authenticated with check (
  author = auth.uid() and (public.is_group_mgr(group_id) or public.is_group_member(group_id))
);

-- كروب الفريق لا يُحذف وحده (يُحذف مع الفريق)
drop policy if exists groups_del on public.groups;
create policy groups_del on public.groups for delete to authenticated
  using (team_id is null and (public.has_scope(unit_key) or created_by = auth.uid()));

-- إنشاء كروب مع كل فريق جديد
create or replace function public.teams_after_ins() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.teams t where t.owner = new.owner) > 3 then
    raise exception 'team_limit' using errcode = 'P0001';
  end if;
  insert into public.team_members (team_id, user_id, role) values (new.id, new.owner, 'owner');
  insert into public.groups (unit_key, name, img, created_by, team_id)
    values ('TEAM|' || new.id || '|*|m', new.name, new.logo, new.owner, new.id);
  return new;
end $$;

-- للفرق الموجودة قبل هذه المرحلة
insert into public.groups (unit_key, name, img, created_by, team_id)
  select 'TEAM|' || t.id || '|*|m', t.name, t.logo, t.owner, t.id from public.teams t
  where not exists (select 1 from public.groups g where g.team_id = t.id);

-- تغيير اسم/صورة الكروب يغيّر الفريق أيضاً
create or replace function public.groups_team_sync() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.team_id is not null and (new.name is distinct from old.name or new.img is distinct from old.img) then
    update public.teams set name = left(new.name, 30), logo = new.img where id = new.team_id;
  end if;
  return new;
end $$;
drop trigger if exists groups_team_sync_t on public.groups;
create trigger groups_team_sync_t after update on public.groups for each row execute function public.groups_team_sync();

-- الفريق لا يغيّر ربط كروبه
create or replace function public.groups_team_lock() returns trigger
language plpgsql security definer set search_path = '' as $$
begin new.team_id := old.team_id; return new; end $$;
drop trigger if exists groups_team_lock_t on public.groups;
create trigger groups_team_lock_t before update on public.groups for each row execute function public.groups_team_lock();
