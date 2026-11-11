-- جمّارة 60: محفظة المحلل كاملة للمشتركين (قراءة فقط) — تستبدل دالة ملف 58
create or replace function public.chn_portfolio()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if not public.chn_access() then raise exception 'forbidden'; end if;
  select coalesce(jsonb_agg(to_jsonb(s) - 'owner' order by s.created_at), '[]'::jsonb)
  into r
  from public.stock_items s
  join public.profiles p on p.id = s.owner and lower(p.username) = 'tamem';
  return r;
end $$;
revoke all on function public.chn_portfolio() from public, anon;
grant execute on function public.chn_portfolio() to authenticated;
