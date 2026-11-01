-- =====================================================
-- جمّارة Jommara — المرحلة 5: المنشورات والإعجابات والتعليقات والمتابعة (مشتركة بين كل الطلبة)
-- الصق هذا كله في SQL Editor ثم اضغط Run (آمن لو شغّلته مرتين)
-- يتطلب المراحل 1 و2 و3 و4 من قبل
-- =====================================================

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  unit_key text not null,                 -- جامعة|كلية
  dept text,                              -- القسم (اختياري)
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null default 's',
  title text not null default '' check (char_length(title) <= 200),
  body text not null default '' check (char_length(body) <= 5000),
  media jsonb not null default '[]'::jsonb,
  cm boolean not null default true,
  aud text,
  hide jsonb not null default '[]'::jsonb,
  pinned boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists posts_unit_idx on public.posts (unit_key, created_at desc);
alter table public.posts enable row level security;
drop policy if exists posts_read on public.posts;
create policy posts_read on public.posts for select to authenticated using (true);
drop policy if exists posts_ins on public.posts;
create policy posts_ins on public.posts for insert to authenticated with check (author = auth.uid());
drop policy if exists posts_upd on public.posts;
create policy posts_upd on public.posts for update to authenticated
  using (author = auth.uid() or public.has_scope(unit_key))
  with check (author = auth.uid() or public.has_scope(unit_key));
drop policy if exists posts_del on public.posts;
create policy posts_del on public.posts for delete to authenticated
  using (author = auth.uid() or public.has_scope(unit_key));

-- غير الناشر (المشرف) لا يغيّر إلا التثبيت وفتح/إغلاق التعليقات
create or replace function public.posts_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is distinct from old.author then
    new.title := old.title; new.body := old.body; new.media := old.media;
    new.aud := old.aud; new.hide := old.hide; new.kind := old.kind;
  end if;
  new.author := old.author; new.unit_key := old.unit_key; new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists posts_guard_t on public.posts;
create trigger posts_guard_t before update on public.posts
  for each row execute function public.posts_guard();

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_likes enable row level security;
drop policy if exists pl_read on public.post_likes;
create policy pl_read on public.post_likes for select to authenticated using (true);
drop policy if exists pl_ins on public.post_likes;
create policy pl_ins on public.post_likes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists pl_del on public.post_likes;
create policy pl_del on public.post_likes for delete to authenticated using (user_id = auth.uid());

create table if not exists public.post_comments (
  id bigint generated always as identity primary key,
  post_id uuid not null references public.posts(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  parent bigint references public.post_comments(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists pc_post_idx on public.post_comments (post_id, id);
alter table public.post_comments enable row level security;
drop policy if exists pc_read on public.post_comments;
create policy pc_read on public.post_comments for select to authenticated using (true);
drop policy if exists pc_ins on public.post_comments;
create policy pc_ins on public.post_comments for insert to authenticated with check (
  author = auth.uid()
  and exists (select 1 from public.posts p where p.id = post_id and p.cm)
);
drop policy if exists pc_del on public.post_comments;
create policy pc_del on public.post_comments for delete to authenticated using (
  author = auth.uid()
  or exists (select 1 from public.posts p where p.id = post_comments.post_id and (p.author = auth.uid() or public.has_scope(p.unit_key)))
);

-- المتابعة (الحساب الخاص: طلب ينتظر القبول)
create table if not exists public.follows (
  follower uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  followee uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'ok' check (status in ('ok', 'req')),
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);
create index if not exists follows_followee_idx on public.follows (followee);
alter table public.follows enable row level security;
drop policy if exists fol_read on public.follows;
create policy fol_read on public.follows for select to authenticated using (true);
drop policy if exists fol_ins on public.follows;
create policy fol_ins on public.follows for insert to authenticated with check (follower = auth.uid());
drop policy if exists fol_upd on public.follows;
create policy fol_upd on public.follows for update to authenticated using (followee = auth.uid()) with check (followee = auth.uid());
drop policy if exists fol_del on public.follows;
create policy fol_del on public.follows for delete to authenticated using (follower = auth.uid() or followee = auth.uid());

create or replace function public.follows_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if exists (select 1 from public.profiles p where p.id = new.followee and p.private) then
      new.status := 'req';
    else
      new.status := 'ok';
    end if;
  else
    new.follower := old.follower; new.followee := old.followee;
  end if;
  return new;
end $$;
drop trigger if exists follows_guard_t on public.follows;
create trigger follows_guard_t before insert or update on public.follows
  for each row execute function public.follows_guard();

revoke all on public.posts, public.post_likes, public.post_comments, public.follows from anon;
grant select, insert, update, delete on public.posts, public.post_likes, public.post_comments, public.follows to authenticated;
