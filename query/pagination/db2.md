# IBM Db2: 分页 (Pagination)

> 参考资料:
> - [Db2 SQL Reference - SELECT](https://www.ibm.com/docs/en/db2/11.5?topic=statements-select)
> - [Db2 SQL Reference - FETCH FIRST](https://www.ibm.com/docs/en/db2/11.5?topic=clause-fetch-first-clause)
> - [Db2 SQL Reference - OPTIMIZE FOR](https://www.ibm.com/docs/en/db2/11.5?topic=clauses-optimize-clause)
> - [Db2 Window Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


## FETCH FIRST（Db2 原创语法，后被 SQL 标准采纳）


## FETCH FIRST N ROWS ONLY（Db2 的原创语法，比 SQL 标准更早）

```sql
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## SQL 标准: OFFSET + FETCH（Db2 11.1+）

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```

## FETCH NEXT（等价于 FETCH FIRST）

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

## FETCH FIRST with PERCENT（取前 N% 的行）

```sql
SELECT * FROM users ORDER BY age DESC FETCH FIRST 10 PERCENT ROWS ONLY;
```

## FETCH with WITH TIES（包含并列行）

```sql
SELECT * FROM users ORDER BY age FETCH FIRST 10 ROWS WITH TIES;
```

## LIMIT 语法（Db2 不支持）


Db2 不支持 LIMIT / OFFSET 语法:
SELECT * FROM users ORDER BY id LIMIT 10;           -- 不支持
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20; -- 不支持
替代方案: 使用 FETCH FIRST 语法（SQL 标准）
Db2 是 FETCH FIRST 语法的发明者，比 LIMIT 更"标准"

## OPTIMIZE FOR（Db2 特有的查询提示）


## OPTIMIZE FOR N ROWS: 告知优化器期望返回的行数

```sql
SELECT * FROM users ORDER BY id
FETCH FIRST 10 ROWS ONLY
OPTIMIZE FOR 10 ROWS;
```

作用:
影响优化器的访问路径选择（倾向于索引扫描而非全表扫描）
影响预取策略（减少预取量，适合分页场景）
不改变查询结果，只影响执行计划
OPTIMIZE FOR 1 ROW:
告知优化器只期望 1 行（最大程度倾向于索引访问）
即使 FETCH FIRST 返回多行，OPTIMIZE FOR 1 仍可加速
SELECT * FROM users WHERE id > 100 ORDER BY id
FETCH FIRST 10 ROWS ONLY
OPTIMIZE FOR 1 ROW;

## OFFSET 的性能问题


Db2 中 OFFSET 的执行:
1. 执行查询计划获取前 offset + limit 行
2. 丢弃前 offset 行
3. 返回后 limit 行
时间复杂度: O(offset + limit)
OPTIMIZE FOR 与 OFFSET 的配合:
OPTIMIZE FOR offset + limit ROWS 可帮助优化器选择更优的访问路径
对于大 offset，优化器可能选择避免预取过多数据页

## 键集分页（Keyset Pagination）: 高性能替代方案


## 第一页

```sql
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## 后续页（已知上一页最后一条 id = 100）

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id
FETCH FIRST 10 ROWS ONLY;
```

## 多列排序的键集分页

```sql
SELECT * FROM users
WHERE created_at > TIMESTAMP '2025-01-01'
   OR (created_at = TIMESTAMP '2025-01-01' AND id > 100)
ORDER BY created_at, id
FETCH FIRST 10 ROWS ONLY;
```

## 窗口函数辅助分页


## ROW_NUMBER 分页

```sql
SELECT * FROM (
    SELECT u.*, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users u
) t
WHERE rn BETWEEN 21 AND 30;
```

## 分组后 Top-N

```sql
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;
```

## RANK / DENSE_RANK 分页（包含并列排名）

```sql
SELECT * FROM (
    SELECT *, RANK() OVER (ORDER BY score DESC) AS rnk
    FROM users
) t WHERE rnk <= 10;
```

## 服务端游标（存储过程中使用）


可滚动游标（在存储过程 / 嵌入式 SQL 中使用）
DECLARE cur SCROLL CURSOR FOR SELECT * FROM users ORDER BY id;
FETCH ABSOLUTE 21 FROM cur;      -- 跳到第 21 行
FETCH RELATIVE 10 FROM cur;      -- 从当前位置前进 10 行
FETCH PRIOR FROM cur;            -- 回退一行
CLOSE cur;
游标的实现:
Db2 的可滚动游标在 Temp 表空间中缓存结果集
INSENSITIVE 游标: 快照，不反映其他事务的修改
SENSITIVE 游标: 实时反映修改（性能开销更大）

## Db2 特有说明


Db2 的分页特性:
FETCH FIRST:     支持（Db2 原创，SQL 标准采纳）
OFFSET:          支持（11.1+，SQL 标准）
WITH TIES:       支持（包含并列行）
PERCENT:         支持（取前 N%）
OPTIMIZE FOR:    支持（查询提示，影响执行计划）
LIMIT:           不支持（非 SQL 标准）
Db2 三个版本的分页差异:
Db2 for LUW (Linux/Unix/Windows):  完整支持上述所有特性
Db2 for z/OS:                      支持大部分特性，OFFSET 需特定版本
Db2 for i (AS/400):                支持基本特性，语法略有差异
FETCH FIRST 的历史:
Db2 是 FETCH FIRST 语法的发明者
SQL:2008 标准正式采纳了这一语法
因此 Db2 的分页语法最接近 SQL 标准

## 版本演进

Db2 V8:   FETCH FIRST N ROWS ONLY（原创语法）
Db2 V9:   OPTIMIZE FOR 增强
Db2 V10:  窗口函数增强（ROW_NUMBER, RANK, DENSE_RANK）
Db2 11.1: OFFSET 支持（SQL 标准完整支持）
Db2 11.5: WITH TIES 支持，PERCENT 支持

## 横向对比: 分页语法差异


语法对比:
Db2:        FETCH FIRST + OFFSET（SQL 标准最佳实践者）
Oracle:     FETCH FIRST (12c+) / ROWNUM
SQL Server: TOP + OFFSET-FETCH (2012+)
PostgreSQL: LIMIT / OFFSET + FETCH FIRST
MySQL:      LIMIT / OFFSET（不支持 FETCH FIRST）
SQL 标准兼容度对比:
Db2:        FETCH FIRST + OFFSET（最标准，语法发明者）
PostgreSQL: FETCH FIRST + OFFSET（SQL 标准兼容，13+ 支持 WITH TIES）
Oracle:     FETCH FIRST + OFFSET（12c+ 标准，WITH TIES 支持）
SQL Server: OFFSET-FETCH（2012+，TOP WITH TIES 也支持）
MySQL:      LIMIT / OFFSET（非标准语法）
