-- ============================================================================
-- Cuprum 个人主页 · 把反馈箱切成「公开留言墙」
-- 用法：Supabase Dashboard → SQL Editor → New query → 整段粘贴 → Run
--       幂等，可以重复跑。
--
-- 为什么需要它：
--   现在页面会用 anon key 读 GET /rest/v1/feedback?select=id,message,created_at
--   来渲染「大家的留言」。但旧版脚本只给了 authenticated 的 SELECT 权限，
--   anon 连表的读权限都没有，于是 PostgREST 报：
--     HTTP 401 · 42501 · permission denied for table feedback
--   这个脚本补上「匿名可读」，并把旧的「只有所有者能读」策略清掉。
--
-- ⚠️ 留言会公开给所有人看。message 里写了什么，任何人都能看到。
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) 清掉旧版结构（邮箱白名单 + 登录看全部，页面已经不用了）
--    ⚠️ 这两张表里若已有数据会一起没掉，要留就先在 Table Editor 里导出。
-- ---------------------------------------------------------------------------
drop policy if exists fb_select on public.feedback;    -- 旧：using (is_owner())，只给 authenticated
drop policy if exists fb_update on public.feedback;
drop policy if exists fb_delete on public.feedback;

drop table if exists public.feedback_replies;          -- 回复表（旧）
drop table if exists public.owner_emails;              -- 邮箱白名单（旧）
drop function if exists public.is_owner();             -- 所有者判断（旧）


-- ---------------------------------------------------------------------------
-- 2) 时间戳只信数据库（旧函数会顺手写 is_read，这里去掉）
-- ---------------------------------------------------------------------------
create or replace function public.feedback_stamp()
returns trigger
language plpgsql
as $$
begin
  new.created_at := now();
  return new;
end;
$$;

drop trigger if exists feedback_stamp_bi on public.feedback;
create trigger feedback_stamp_bi
  before insert on public.feedback
  for each row execute function public.feedback_stamp();


-- ---------------------------------------------------------------------------
-- 3) 权限：所有人可读 + 所有人可写一条，但谁都不能改、不能删
-- ---------------------------------------------------------------------------
alter table public.feedback enable row level security;

-- 读：公开列表（using (true) = 谁都能看）
drop policy if exists fb_select_public on public.feedback;
create policy fb_select_public on public.feedback
  for select to anon, authenticated
  using (true);

-- 写：只允许插入新留言
drop policy if exists fb_insert on public.feedback;
create policy fb_insert on public.feedback
  for insert to anon, authenticated
  with check (char_length(message) between 1 and 1000);

grant select, insert on public.feedback to anon, authenticated;
revoke update, delete on public.feedback from anon, authenticated;

-- 若 id 是 bigint + 序列（老项目就是这样），匿名插入还要拿到序列权限
do $$
declare seq text := pg_get_serial_sequence('public.feedback', 'id');
begin
  if seq is not null then
    execute format('grant usage, select on sequence %s to anon, authenticated', seq);
  end if;
end $$;

-- 新库兜底：表本身还没有message列时补上（老项目已经有，不会重复加）
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'feedback'
                   and column_name = 'message') then
    execute 'alter table public.feedback add column message text';
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 4) 自检：跑完看这里的结果
--    期望：policies = "fb_insert [INSERT], fb_select_public [SELECT]"
--          owner_tables_left = 0、is_owner_left = 0
-- ---------------------------------------------------------------------------
select
  (select count(*) from public.feedback)                                               as row_count,
  (select string_agg(column_name || ':' || data_type, ', ' order by ordinal_position)
     from information_schema.columns
     where table_schema = 'public' and table_name = 'feedback')                        as cols,
  (select string_agg(policyname || ' [' || cmd || ']', ', ' order by policyname)
     from pg_policies
     where schemaname = 'public' and tablename = 'feedback')                           as policies,
  (select count(*) from information_schema.tables
     where table_schema = 'public' and table_name in ('owner_emails','feedback_replies')) as owner_tables_left,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'is_owner')                             as is_owner_left;
