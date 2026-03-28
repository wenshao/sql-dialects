# Oracle: 临时表

> 参考资料:
> - [Oracle SQL Language Reference - CREATE TABLE (Global Temporary Tables)](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html)
> - [Oracle SQL Language Reference - Private Temporary Tables (18c+)](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html)

## 全局临时表 GTT（Oracle 的独特设计）

事务级（事务提交时自动清空数据）
```sql
CREATE GLOBAL TEMPORARY TABLE gtt_session_calc (
    calc_id   NUMBER,
    user_id   NUMBER,
    amount    NUMBER(10,2)
) ON COMMIT DELETE ROWS;
```

会话级（会话结束时自动清空数据）
```sql
CREATE GLOBAL TEMPORARY TABLE gtt_user_cache (
    user_id   NUMBER,
    username  VARCHAR2(100)
) ON COMMIT PRESERVE ROWS;
```

Oracle GTT 的关键设计决策:
  表结构是永久的（CREATE 一次，数据字典中永久存在）
  数据是临时的（每个会话独立，互不可见）

这与其他数据库的临时表设计截然不同:

横向对比:
  Oracle:     GTT 结构永久 + 数据临时（DDL 一次，反复使用）
  PostgreSQL: CREATE TEMP TABLE（结构和数据都临时，会话结束时消失）
  MySQL:      CREATE TEMPORARY TABLE（同 PostgreSQL）
  SQL Server: #table / ##table（# 局部，## 全局，都临时）

Oracle 设计的优缺点:
  优点: 结构永久 → 不需要每次创建，减少 DDL 开销和锁竞争
        可以预先创建索引和约束
  缺点: 结构是全局的 → 不够灵活，不同业务需求可能冲突
        需要 DBA 预先创建（不能在存储过程中动态创建）

对引擎开发者的启示:
  PostgreSQL/MySQL 的"按需创建"模型更灵活，适合动态场景。
  Oracle 的"预定义结构"模型适合固定的 ETL 流程。
  推荐: 支持两种模式（CREATE TEMPORARY TABLE + GTT）。

## GTT 使用

```sql
INSERT INTO gtt_user_cache
SELECT id, username FROM users WHERE status = 1;

SELECT * FROM gtt_user_cache;                  -- 只能看到当前会话的数据
```

索引（也是临时的，但定义是永久的）
```sql
CREATE INDEX idx_gtt_user ON gtt_user_cache(user_id);
```

GTT 的存储特点:
  不记录 redo 日志（仅记录 undo），写入性能优于普通表
  使用临时表空间（TEMPORARY TABLESPACE）
  不需要 COMMIT 就可以查询（不像 INSERT /*+ APPEND */ 需要先 COMMIT）

## 私有临时表 PTT（18c+）

PTT 的表结构也是临时的（只在当前会话存在）
名称必须以 ORA$PTT_ 前缀开头

```sql
CREATE PRIVATE TEMPORARY TABLE ora$ptt_results (
    id    NUMBER,
    value NUMBER
) ON COMMIT PRESERVE ROWS;
```

事务级 PTT（提交时删除表结构和数据）
```sql
CREATE PRIVATE TEMPORARY TABLE ora$ptt_calc (
    id NUMBER, result NUMBER
) ON COMMIT DROP DEFINITION;
```

PTT 不记录 redo/undo 日志，性能最好

```sql
INSERT INTO ora$ptt_results VALUES (1, 100);
SELECT * FROM ora$ptt_results;
DROP TABLE ora$ptt_results;
```

GTT vs PTT:
  GTT: 结构永久、数据临时、需要预先 CREATE
  PTT: 结构临时、数据临时、可以动态 CREATE（18c+）
  PTT 更接近其他数据库的 TEMPORARY TABLE 行为

## CTE 作为轻量级替代

```sql
WITH monthly_sales AS (
    SELECT user_id, TRUNC(order_date, 'MM') AS month,
           SUM(amount) AS total
    FROM orders GROUP BY user_id, TRUNC(order_date, 'MM')
)
SELECT user_id, month, total,
       LAG(total) OVER (PARTITION BY user_id ORDER BY month) AS prev
FROM monthly_sales;
```

CTE 物化提示
```sql
WITH /*+ MATERIALIZE */ expensive_calc AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT * FROM expensive_calc WHERE total > 1000;
```

## PL/SQL 集合类型（内存表替代）

```sql
DECLARE
    TYPE t_user_rec IS RECORD (id NUMBER, username VARCHAR2(100));
    TYPE t_user_tab IS TABLE OF t_user_rec INDEX BY PLS_INTEGER;
    v_users t_user_tab;
BEGIN
    SELECT id, username BULK COLLECT INTO v_users
    FROM users WHERE status = 1;
    FOR i IN 1..v_users.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(v_users(i).username);
    END LOOP;
END;
/
```

PL/SQL 集合 vs 临时表:
  集合: 全在内存，适合小数据量，无 I/O 开销
  临时表: 可以溢出到磁盘，适合大数据量，支持索引

## CONNECT BY 生成临时序列（Oracle 特有技巧）

生成数字序列（不需要临时表）
```sql
SELECT LEVEL AS n FROM DUAL CONNECT BY LEVEL <= 100;
```

生成日期序列
```sql
SELECT DATE '2024-01-01' + LEVEL - 1 AS d
FROM DUAL CONNECT BY LEVEL <= 31;
```

横向对比:
  Oracle:     CONNECT BY LEVEL（独有语法）
  PostgreSQL: generate_series(1, 100)
  MySQL:      递归 CTE（8.0+）
  SQL Server: master.dbo.spt_values 或递归 CTE

## 数据字典查询

查看临时表空间使用
```sql
SELECT tablespace_name, bytes_used, bytes_free
FROM v$temp_space_header;
```

查看当前会话的临时空间使用
```sql
SELECT username, segtype, blocks
FROM v$tempseg_usage WHERE username = USER;
```

## 对引擎开发者的总结

1. Oracle GTT 的"结构永久+数据临时"设计与其他数据库不同，各有优劣。
2. 18c PTT 补充了"动态创建临时表"的能力，更接近行业标准。
3. GTT 不记录 redo 是性能优势; PTT 连 undo 也不记录，更快。
4. CONNECT BY LEVEL 是 Oracle 生成序列的独有技巧，其他引擎用 generate_series。
5. PL/SQL 集合类型可以替代小型临时表，避免 I/O 开销。
