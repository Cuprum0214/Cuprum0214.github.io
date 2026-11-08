# 反馈箱（公开留言墙）· 数据库脚本怎么跑

> 一句话：**把 `public-read.sql` 整段粘到 Supabase → SQL Editor → Run。**
> 跑完之后页面上的「大家的留言」就能读到数据了。

## 现在的状态

| 部分 | 状态 |
|---|---|
| `outputs/personal-homepage/index.html` | 已改成公开留言墙：所有人可读、取消邮箱密码登录、去掉「我的留言（本机留档）」和「主页所有者」面板 |
| 数据库 | **还没切**。匿名访客没有 `feedback` 表的读权限，页面会显示「⚠︎ 没能载入留言列表 · HTTP 401 · 42501 permission denied for table feedback」 |

PostgREST 把原因写得很直白：`Grant the required privileges to the current role with: GRANT SELECT ON public.feedback TO anon;`

旧脚本只给了 `authenticated` 的读权限，读策略也只对 `authenticated` 生效，所以访客（anon key）读不到任何一行 —— 提交（INSERT）一直是好的。

## 第一步：跑 `public-read.sql`（必须）

Supabase Dashboard → **SQL Editor** → New query → 把 `public-read.sql` 整段粘进去 → **Run**。

它是幂等的，跑几次都行。跑完最后会输出一行自检，期望看到：

```
policies = "fb_insert [INSERT], fb_select_public [SELECT]"
owner_tables_left = 0
is_owner_left = 0
```

看到 `fb_select_public` 就说明匿名可读了。只想要最小改动的话，下面这三句就够：

```sql
grant select on public.feedback to anon;

drop policy if exists fb_select_public on public.feedback;
create policy fb_select_public on public.feedback
  for select to anon, authenticated
  using (true);
```

## 第二步：确认

- 刷新页面，点右下角徽标，「大家的留言」应该能列出留言，折叠状态下标题右边也有条数。
- 或者让 DeepWorks 跑 `.deepworks/tmp/check_public_read.py`（只读探针，只用 anon key，不写库）。

## ⚠️ 关于 `schema.sql`

**`schema.sql` 是旧稿，已经被 `public-read.sql` 取代。** 它里面还在：

- 建 `owner_emails` 邮箱白名单表
- 建 `is_owner()` 函数
- 建只给 `authenticated` 的 `fb_select / fb_update / fb_delete` 策略
- 建 `feedback_replies` 回复表

**别在跑完 `public-read.sql` 之后再跑它**，否则读策略又会被换回「只有登录的所有者能看」，页面会再次变成「没能载入留言列表」。

想彻底换掉它的内容：把 `public-read.sql` 的内容整段覆盖进 `schema.sql` 即可（两者等价，`public-read.sql` 多了「补 message 列」的兜底）。

（之所以保留它、另外新建文件：覆盖写入 `schema.sql` 的操作连续几次被中断，没写成；不改它也不会影响页面。）

## ⚠️ 关于隐私

**留言是公开的。** `message` 里写了什么，任何人都能看到；里面的昵称、关系、设备、内容都会随正文一起公开。页面在输入框下方和提交成功的提示里都写明了这一点，但数据库这一层没法替你判断内容里有没有隐私信息。

## 数据模型（与 `index.html` 里的请求一一对应）

```
写入  POST /rest/v1/feedback            body = { "message": "..." }
读取  GET  /rest/v1/feedback?select=id,message,created_at&order=created_at.desc&limit=100
```

- 时间戳由触发器盖章，前端传什么都不作数。
- 权限：`select` + `insert` 给 `anon, authenticated`；`update` / `delete` 一律收回 —— 谁都不能改、不能删。
