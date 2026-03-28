# Snowflake: 分页 (Pagination)

> 参考资料:
> - [1] Snowflake SQL Reference - SELECT (LIMIT/OFFSET)
>   https://docs.snowflake.com/en/sql-reference/sql/select


## 1. 基本语法


LIMIT / OFFSET（最常用）

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

仅取前 N 行

```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

FETCH FIRST（SQL 标准语法）

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

```

TOP N（SQL Server 兼容）

```sql
SELECT TOP 10 * FROM users ORDER BY id;

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 四种分页语法共存

 Snowflake 同时支持: LIMIT/OFFSET + FETCH FIRST + TOP + QUALIFY
 这是兼容多种方言的策略:
   LIMIT/OFFSET → MySQL/PostgreSQL 习惯
   FETCH FIRST  → SQL 标准 (SQL:2008)
   TOP           → SQL Server 习惯
   QUALIFY       → Snowflake/Teradata 原创

 对比各引擎支持的语法:
   MySQL:      LIMIT n OFFSET m（仅此一种）
   PostgreSQL: LIMIT/OFFSET + FETCH FIRST
   SQL Server: TOP + OFFSET FETCH（不支持 LIMIT）
   Oracle:     FETCH FIRST (12c+) + ROWNUM (传统)
   BigQuery:   LIMIT/OFFSET + FETCH FIRST

### 2.2 QUALIFY 分页: Snowflake 的独特优势

```sql
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (ORDER BY id) BETWEEN 21 AND 30;
```

无需子查询，直接过滤窗口函数结果
比传统的 ROW_NUMBER 子查询方案更简洁

QUALIFY 分组 Top-N:

```sql
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) <= 3;

```

## 3. OFFSET 性能与优化


OFFSET 在 Snowflake 中的执行:
扫描微分区 → 排序 → 跳过 OFFSET 行 → 返回 LIMIT 行
时间复杂度: O(offset + limit)，大 OFFSET 值性能差

带总行数的分页（一次查询获取数据和总数）:

```sql
SELECT *, COUNT(*) OVER() AS total_count
FROM users ORDER BY id LIMIT 10 OFFSET 20;

```

## 4. 键集分页: 高性能替代方案


第一页

```sql
SELECT * FROM users ORDER BY id LIMIT 10;

```

后续页（已知上一页最后 id = 100）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```

利用微分区裁剪: WHERE id > 100 可跳过 MAX(id) <= 100 的分区

多列排序的键集分页

```sql
SELECT * FROM users
WHERE (created_at, id) > ('2025-01-01', 100)
ORDER BY created_at, id LIMIT 10;

```

 键集分页的局限:
   需要有唯一且有序的排序键
   不支持跳到任意页（只能顺序翻页）
   用户无法看到总页数

## 5. RESULT_CACHE 对分页的影响


 相同查询（含参数）24 小时内命中结果缓存:
   SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
   → 第二次执行命中缓存，< 100ms 返回
 但不同页码是不同 SQL 文本，不共享缓存

## 6. ROW_NUMBER 分页（传统子查询方式）


```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
) t WHERE rn BETWEEN 21 AND 30;

```

## 横向对比: 分页能力矩阵

| 能力          | Snowflake     | BigQuery  | PostgreSQL  | MySQL |
|------|------|------|------|------|
| LIMIT/OFFSET  | 支持          | 支持      | 支持        | 支持 |
| FETCH FIRST   | 支持          | 支持      | 支持        | 不支持 |
| TOP           | 支持          | 不支持    | 不支持      | 不支持 |
| QUALIFY 分页  | 支持(独有)    | 支持      | 不支持      | 不支持 |
| WITH TIES     | 不支持        | 不支持    | 支持        | 不支持 |
| CURSOR 分页   | 不支持        | 不支持    | 支持        | 支持 |
| 结果缓存      | RESULT_CACHE  | 缓存      | 无原生      | query_cache |

