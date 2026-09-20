-- ============================================================================
-- Cuprum 个人主页 · 反馈箱（Supabase）
-- 用法：Supabase Dashboard → SQL Editor → New query → 整段粘贴 → Run
--       脚本可重复执行（幂等），失败重跑不会破坏已有数据。
--
-- 数据模型（与页面 index.html 里发出去的请求一一对应）：
--   · 访客提交：POST /rest/v1/feedback  body = { "message": "..." }
--     不带会话、只用 anon key —— 和参考站
--     https://puyuesun.github.io/spy-personal-homepage/ 完全一样。
--     所以 message 必须存在，且 anon 必须被允许 insert。
--   · 所有者：用邮箱 + 密码登录（Authentication → Users 建账号），
--     邮箱写进 owner_emails 白名单后即可读全部留言、回复、标记已读、删除。
--
-- 隐私模型（由数据库 RLS 强制执行，前端 / anon key 无法绕过）：
--   · anon 只能 INSERT，读不到任何一行（没有 select policy）
--   · 只有 owner_emails 白名单里的账号能 SELECT / UPDATE / DELETE
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 0) 所有者邮箱白名单
--    前端完全不可访问，只有 SQL Editor / service_role 能修改。
-- ---------------------------------------------------------------------------
create table if not exists public.owner_emails (
  email      text primary key,
  created_at timestamptz not null default now()
);

alter table public.owner_emails enable row level security;
-- 故意不建任何 policy：anon / authenticated 读不到也写不了。

-- 👇👇 把下面的邮箱改成你自己的（稍后就用这个邮箱 + 密码登录查看全部反馈）
insert into public.owner_emails (email) values ('18822136876@163.com')
on conflict (email) do nothing;


-- ---------------------------------------------------------------------------
-- 1) 是否是所有者
--    依据 Supabase 签名过的 JWT 里的 email 判断，前端无法伪造。
-- ---------------------------------------------------------------------------
create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.owner_emails o
    where lower(o.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

grant execute on function public.is_owner() to anon, authenticated;


-- ---------------------------------------------------------------------------
-- 2) 留言表（访客那一侧只有一个 message，和参考站一致）
-- ---------------------------------------------------------------------------
-- 2a) 先迁移：若已有旧版「四字段」表（有 body 没有 message），补上 message 并把
--     旧 body 的内容搬过去，旧列保留不动、不丢数据。用动态 SQL 写，所以
--     表还不存在时这里只是空跑，不会报错。
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'feedback' and column_name = 'body')
     and not exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'feedback' and column_name = 'message')
  then
    execute 'alter table public.feedback add column message text';
    execute 'update public.feedback set message = nullif(body, '''') where message is null';
    execute 'alter table public.feedback alter column message set not null';
  end if;
end $$;

-- 2b) 建表
create table if not exists public.feedback (
  id         uuid primary key default gen_random_uuid(),
  message    text not null check (char_length(message) between 1 and 1000),
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists feedback_created_idx on public.feedback (created_at desc);

-- 时间与已读状态由数据库盖章，防止前端伪造
create or replace function public.feedback_stamp()
returns trigger
language plpgsql
as $$
begin
  new.created_at := now();
  new.is_read    := false;
  return new;
end;
$$;

drop trigger if exists feedback_stamp_bi on public.feedback;
create trigger feedback_stamp_bi
  before insert on public.feedback
  for each row execute function public.feedback_stamp();

alter table public.feedback enable row level security;

-- 访客：只允许插入，读不到任何一行
drop policy if exists fb_insert on public.feedback;
create policy fb_insert on public.feedback
  for insert to anon, authenticated
  with check (char_length(message) between 1 and 1000);

-- 所有者：读全部
drop policy if exists fb_select on public.feedback;
create policy fb_select on public.feedback
  for select to authenticated
  using (public.is_owner());

drop policy if exists fb_update on public.feedback;
create policy fb_update on public.feedback
  for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

drop policy if exists fb_delete on public.feedback;
create policy fb_delete on public.feedback
  for delete to authenticated
  using (public.is_owner());

grant insert on public.feedback to anon, authenticated;
grant select, update, delete on public.feedback to authenticated;


-- ---------------------------------------------------------------------------
-- 3) 回复表（只有所有者会写）
-- ---------------------------------------------------------------------------
create table if not exists public.feedback_replies (
  id          uuid primary key default gen_random_uuid(),
  feedback_id uuid not null references public.feedback(id) on delete cascade,
  from_owner  boolean not null default true,
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now()
);

create index if not exists feedback_replies_idx on public.feedback_replies (feedback_id, created_at);

alter table public.feedback_replies enable row level security;

drop policy if exists fbr_select on public.feedback_replies;
create policy fbr_select on public.feedback_replies
  for select to authenticated
  using (public.is_owner());

drop policy if exists fbr_insert on public.feedback_replies;
create policy fbr_insert on public.feedback_replies
  for insert to authenticated
  with check (public.is_owner());

drop policy if exists fbr_delete on public.feedback_replies;
create policy fbr_delete on public.feedback_replies
  for delete to authenticated
  using (public.is_owner());

grant select, insert, delete on public.feedback_replies to authenticated;


-- ---------------------------------------------------------------------------
-- 4) 自检（可选）：跑完会列出三张表与策略数量，看到数字即可
-- ---------------------------------------------------------------------------
select
  'owner_emails'      as 表,
  (select count(*) from public.owner_emails)      as 行数,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'owner_emails')      as 策略数
union all select
  'feedback',
  (select count(*) from public.feedback),
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'feedback')
union all select
  'feedback_replies',
  (select count(*) from public.feedback_replies),
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'feedback_replies');
