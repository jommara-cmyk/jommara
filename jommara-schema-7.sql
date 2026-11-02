-- =====================================================
-- جمّارة Jommara — المرحلة 7: فِرق كرة القدم
-- الصق هذا كله في SQL Editor ثم اضغط Run (آمن لو شغّلته مرتين)
-- يتطلب المراحل 1 إلى 6
-- =====================================================

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 30),
  code text not null,
  logo text,
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create unique index if not exists teams_code_upper on public.teams (upper(code));

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  role text not null default 'player' check (role in ('owner', 'player')),
  pos text,
  no int check (no is null or no between 0 and 99),
  cap boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index if not exists tm_user_idx on public.team_members (user_id);

create table if not exists public.team_matches (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  opp text not null check (char_length(opp) between 1 and 40),
  at timestamptz not null,
  venue text check (venue is null or char_length(venue) <= 60),
  kind text not null default 'ودية',
  our int check (our is null or our between 0 and 99),
  their int check (their is null or their between 0 and 99),
  fm text not null default '4-4-2',
  lineup jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists tmt_team_idx on public.team_matches (team_id, at);

create table if not exists public.team_rsvp (
  match_id uuid not null references public.team_matches(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  status text not null check (status in ('y', 'n', 'm')),
  updated_at timestamptz not null default now(),
  primary key (match_id, user_id)
);

create table if not exists public.team_goals (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.team_matches(id) on delete cascade,
  scorer uuid not null references public.profiles(id) on delete cascade,
  assist uuid references public.profiles(id) on delete set null,
  minute int check (minute is null or minute between 0 and 150)
);
create index if not exists tg_match_idx on public.team_goals (match_id);

create table if not exists public.team_posts (
  id bigint generated always as identity primary key,
  team_id uuid not null references public.teams(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  pinned boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists tp_team_idx on public.team_posts (team_id, id desc);

-- ---------- دوال مساعدة ----------
create or replace function public.is_team_member(tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.team_members m where m.team_id = tid and m.user_id = auth.uid())
$$;
create or replace function public.is_team_owner(tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.teams t where t.id = tid and t.owner = auth.uid())
$$;
create or replace function public.team_of_match(mid uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select team_id from public.team_matches where id = mid
$$;
grant execute on function public.is_team_member(uuid), public.is_team_owner(uuid), public.team_of_match(uuid) to authenticated;

-- ---------- السياسات ----------
alter table public.teams enable row level security;
drop policy if exists teams_read on public.teams;
create policy teams_read on public.teams for select to authenticated using (owner = auth.uid() or public.is_team_member(id));
drop policy if exists teams_ins on public.teams;
create policy teams_ins on public.teams for insert to authenticated with check (owner = auth.uid());
drop policy if exists teams_upd on public.teams;
create policy teams_upd on public.teams for update to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists teams_del on public.teams;
create policy teams_del on public.teams for delete to authenticated using (owner = auth.uid());

alter table public.team_members enable row level security;
drop policy if exists tm_read on public.team_members;
create policy tm_read on public.team_members for select to authenticated using (user_id = auth.uid() or public.is_team_member(team_id));
drop policy if exists tm_upd on public.team_members;
create policy tm_upd on public.team_members for update to authenticated
  using (user_id = auth.uid() or public.is_team_owner(team_id)) with check (user_id = auth.uid() or public.is_team_owner(team_id));
drop policy if exists tm_del on public.team_members;
create policy tm_del on public.team_members for delete to authenticated using (user_id = auth.uid() or public.is_team_owner(team_id));
-- لا إدراج مباشر: الانضمام عبر join_team فقط، والمالك يُضاف تلقائياً

alter table public.team_matches enable row level security;
drop policy if exists tmt_read on public.team_matches;
create policy tmt_read on public.team_matches for select to authenticated using (public.is_team_member(team_id));
drop policy if exists tmt_ins on public.team_matches;
create policy tmt_ins on public.team_matches for insert to authenticated with check (public.is_team_owner(team_id));
drop policy if exists tmt_upd on public.team_matches;
create policy tmt_upd on public.team_matches for update to authenticated using (public.is_team_owner(team_id)) with check (public.is_team_owner(team_id));
drop policy if exists tmt_del on public.team_matches;
create policy tmt_del on public.team_matches for delete to authenticated using (public.is_team_owner(team_id));

alter table public.team_rsvp enable row level security;
drop policy if exists tr_read on public.team_rsvp;
create policy tr_read on public.team_rsvp for select to authenticated using (public.is_team_member(public.team_of_match(match_id)));
drop policy if exists tr_ins on public.team_rsvp;
create policy tr_ins on public.team_rsvp for insert to authenticated with check (user_id = auth.uid() and public.is_team_member(public.team_of_match(match_id)));
drop policy if exists tr_upd on public.team_rsvp;
create policy tr_upd on public.team_rsvp for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists tr_del on public.team_rsvp;
create policy tr_del on public.team_rsvp for delete to authenticated using (user_id = auth.uid());

alter table public.team_goals enable row level security;
drop policy if exists tg_read on public.team_goals;
create policy tg_read on public.team_goals for select to authenticated using (public.is_team_member(public.team_of_match(match_id)));
drop policy if exists tg_ins on public.team_goals;
create policy tg_ins on public.team_goals for insert to authenticated with check (public.is_team_owner(public.team_of_match(match_id)));
drop policy if exists tg_del on public.team_goals;
create policy tg_del on public.team_goals for delete to authenticated using (public.is_team_owner(public.team_of_match(match_id)));

alter table public.team_posts enable row level security;
drop policy if exists tp_read on public.team_posts;
create policy tp_read on public.team_posts for select to authenticated using (public.is_team_member(team_id));
drop policy if exists tp_ins on public.team_posts;
create policy tp_ins on public.team_posts for insert to authenticated with check (author = auth.uid() and public.is_team_owner(team_id));
drop policy if exists tp_upd on public.team_posts;
create policy tp_upd on public.team_posts for update to authenticated using (public.is_team_owner(team_id)) with check (public.is_team_owner(team_id));
drop policy if exists tp_del on public.team_posts;
create policy tp_del on public.team_posts for delete to authenticated using (public.is_team_owner(team_id));

-- ---------- حدود وحماية ----------
-- المالك يُضاف لاعباً تلقائياً (بدور owner) وحد أقصى 3 فرق يملكها الشخص
create or replace function public.teams_after_ins() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.teams t where t.owner = new.owner) > 3 then
    raise exception 'team_limit' using errcode = 'P0001';
  end if;
  insert into public.team_members (team_id, user_id, role) values (new.id, new.owner, 'owner');
  return new;
end $$;
drop trigger if exists teams_after_ins_t on public.teams;
create trigger teams_after_ins_t after insert on public.teams for each row execute function public.teams_after_ins();

-- اللاعب العادي لا يغيّر دوره ولا يعيّن قائداً؛ المالك فقط يعيّن القائد
create or replace function public.tm_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.team_id := old.team_id; new.user_id := old.user_id; new.joined_at := old.joined_at; new.role := old.role;
  if new.cap is distinct from old.cap and not public.is_team_owner(old.team_id) then new.cap := old.cap; end if;
  if auth.uid() is distinct from old.user_id then new.pos := old.pos; new.no := old.no; end if;
  return new;
end $$;
drop trigger if exists tm_guard_t on public.team_members;
create trigger tm_guard_t before update on public.team_members for each row execute function public.tm_guard();

-- المالك لا يغادر فريقه (يحذفه بدلاً من ذلك)
create or replace function public.tm_keep_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.role = 'owner' and exists (select 1 from public.teams t where t.id = old.team_id) then
    raise exception 'owner_stays' using errcode = 'P0001';
  end if;
  return old;
end $$;
drop trigger if exists tm_keep_owner_t on public.team_members;
create trigger tm_keep_owner_t before delete on public.team_members for each row execute function public.tm_keep_owner();

-- الانضمام برمز الفريق (حد أقصى 3 فرق للاعب)
create or replace function public.join_team(c text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid;
begin
  if auth.uid() is null then raise exception 'auth' using errcode = '42501'; end if;
  select t.id into tid from public.teams t where upper(t.code) = upper(trim(c));
  if tid is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.team_members m where m.team_id = tid and m.user_id = auth.uid()) then
    if (select count(*) from public.team_members m where m.user_id = auth.uid()) >= 3 then
      raise exception 'team_limit' using errcode = 'P0001';
    end if;
    insert into public.team_members (team_id, user_id) values (tid, auth.uid());
  end if;
  return tid;
end $$;
grant execute on function public.join_team(text) to authenticated;

revoke all on public.teams, public.team_members, public.team_matches, public.team_rsvp, public.team_goals, public.team_posts from anon;
grant select, insert, update, delete on public.teams, public.team_matches, public.team_rsvp, public.team_goals, public.team_posts to authenticated;
grant select, update, delete on public.team_members to authenticated;
