# PostgreSQL: 分页查询

> 参考资料:
> - [PostgreSQL Documentation - LIMIT and OFFSET](https://www.postgresql.org/docs/current/queries-limit.html)
> - [PostgreSQL Documentation - DECLARE CURSOR](https://www.postgresql.org/docs/current/sql-declare.html)

## LIMIT / OFFSET（传统分页）

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
SELECT * FROM users ORDER BY id LIMIT 10;              -- 第一页
```

FETCH FIRST（SQL 标准语法，8.4+）
```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```

WITH TIES (13+): 包含并列行
```sql
SELECT * FROM users ORDER BY score DESC FETCH FIRST 10 ROWS WITH TIES;
```

如果第10名和第11名 score 相同，第11名也包含在结果中

## OFFSET 的性能问题: 为什么大偏移量很慢

OFFSET 1000000 意味着 PostgreSQL 必须:
  (1) 执行查询计划获取前 1000010 行
  (2) 丢弃前 1000000 行
  (3) 返回后 10 行
即使有索引，也需要遍历 B-tree 叶子节点 1000000 次。
时间复杂度: O(OFFSET + LIMIT)，而非 O(LIMIT)。

对比:
  所有主流数据库（MySQL/Oracle/SQL Server）都有相同问题。
  这不是 PostgreSQL 的缺陷，而是 OFFSET 语义的固有局限。

带总行数的分页（一次查询获取数据和总数）
```sql
SELECT *, COUNT(*) OVER() AS total_count
FROM users ORDER BY id LIMIT 10 OFFSET 20;
```

> **注意**: COUNT(*) OVER() 需要扫描全部数据，可能很慢

## 键集分页（Keyset Pagination）: 高性能替代方案

第一页
```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

后续页（已知上一页最后一条 id = 100）
```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```

时间复杂度: O(LIMIT)，与页数无关！

多列排序的键集分页（使用 ROW 值比较）
```sql
SELECT * FROM users
WHERE (created_at, id) > ('2025-01-01', 100)
ORDER BY created_at, id
LIMIT 10;
```

ROW 值比较是 PostgreSQL 的一等公民——直接在 B-tree 索引上范围扫描

索引支持:
```sql
CREATE INDEX idx_users_created_id ON users (created_at, id);
```

设计分析: 键集分页 vs OFFSET 分页
  OFFSET:  可随机跳页，但大偏移量慢，排序不稳定（并发INSERT时可能丢行/重复行）
  Keyset:  只能前/后翻页，大数据集恒定速度，排序稳定（基于唯一键）
  推荐:    API 分页（无限滚动）用 Keyset，管理后台（需要跳页）用 OFFSET

## 服务端游标（大数据集逐批处理）

游标在事务中声明，逐批 FETCH
```sql
BEGIN;
DECLARE user_cursor CURSOR FOR SELECT * FROM users ORDER BY id;
FETCH 100 FROM user_cursor;      -- 获取 100 行
FETCH 100 FROM user_cursor;      -- 获取下一批 100 行
FETCH BACKWARD 50 FROM user_cursor; -- 回退 50 行
CLOSE user_cursor;
COMMIT;
```

SCROLL 游标（支持任意方向移动）
```sql
DECLARE scroll_cur SCROLL CURSOR FOR SELECT * FROM users ORDER BY id;
FETCH ABSOLUTE 500 FROM scroll_cur; -- 跳到第500行
```

游标的内部实现:
  游标底层使用 Portal（PostgreSQL 的执行上下文）。
  非 SCROLL 游标是前向流式的——只缓存 FETCH 请求的行数。
  SCROLL 游标需要 tuplestore 缓存所有已访问的行（可能溢出到磁盘）。

## 窗口函数辅助分页

ROW_NUMBER 分页（适合需要精确行号的场景）
```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM users
) t WHERE rn BETWEEN 21 AND 30;
```

> **注意**: 窗口函数方式需要计算所有行的 ROW_NUMBER，性能不如键集分页。

## 横向对比: 分页语法差异

### 语法

  PostgreSQL: LIMIT n OFFSET m（非标准但广泛使用）
              FETCH FIRST n ROWS ONLY（SQL 标准, 8.4+）
  MySQL:      LIMIT m, n 或 LIMIT n OFFSET m
  Oracle:     FETCH FIRST (12c+)，传统用 ROWNUM
  SQL Server: TOP n 或 OFFSET m ROWS FETCH NEXT n ROWS ONLY (2012+)

### WITH TIES

  PostgreSQL: 13+ 支持
  Oracle:     12c+ 支持
  SQL Server: TOP n WITH TIES（但语法不同）
  MySQL:      不支持

### 游标

  PostgreSQL: DECLARE CURSOR（服务端游标，事务范围内）
  MySQL:      SERVER_CURSOR（通过 prepared statement 协议）
  Oracle:     REF CURSOR / SYS_REFCURSOR（PL/SQL）
  SQL Server: DECLARE CURSOR（功能最丰富）

## 对引擎开发者的启示

(1) OFFSET 的 O(N) 问题无法从引擎层面根本解决:
    优化建议: 对于有序索引扫描，OFFSET 可以利用 B-tree 的 leaf page
    链表快速跳过，但仍然是 O(OFFSET) 次 page 访问。

(2) ROW 值比较是键集分页的关键:
    WHERE (a, b) > (v1, v2) 应该能直接映射到 B-tree 索引扫描。
    PostgreSQL 的 B-tree 原生支持 ROW 值比较（btree_compare_scankey）。

(3) WITH TIES 的实现:
    需要在 LIMIT 达到后继续检查后续行是否与最后一行排序键相同。
    实现: 修改 LimitState 节点，在达到 limit 后进入"拖尾"模式。

## 版本演进

PostgreSQL 全版本: LIMIT / OFFSET
PostgreSQL 8.4:   FETCH FIRST ... ROWS ONLY（SQL 标准）
PostgreSQL 13:    FETCH FIRST ... WITH TIES
