# PostgreSQL: 动态 SQL

> 参考资料:
> - [PostgreSQL Documentation - PL/pgSQL Dynamic Commands](https://www.postgresql.org/docs/current/plpgsql-statements.html#PLPGSQL-STATEMENTS-EXECUTING-DYN)
> - [PostgreSQL Documentation - PREPARE / EXECUTE](https://www.postgresql.org/docs/current/sql-prepare.html)

## PREPARE / EXECUTE: 会话级预编译

```sql
PREPARE user_by_age(INT) AS SELECT * FROM users WHERE age > $1;
EXECUTE user_by_age(25);
DEALLOCATE user_by_age;
DEALLOCATE ALL;
```

设计分析: PREPARE 的内部机制
  PREPARE 将查询解析、分析、重写后存入会话的 prepared statement 缓存。
  前 5 次 EXECUTE 使用 custom plan（基于实际参数值优化）。
  第 6 次起，如果 generic plan 成本 ≤ custom plan 平均成本，切换为 generic plan。
  plan_cache_mode 参数可以强制 custom/generic（12+）。

对比:
  MySQL:      PREPARE 在 SQL 层（COM_STMT_PREPARE 在协议层）
  Oracle:     PL/SQL 中的 EXECUTE IMMEDIATE，或 cursor
  SQL Server: sp_executesql, EXEC()

## PL/pgSQL EXECUTE: 动态 SQL 的核心

EXECUTE 可执行任意动态构造的 SQL 字符串
```sql
CREATE OR REPLACE FUNCTION run_dynamic(p_table TEXT)
RETURNS SETOF RECORD AS $$
BEGIN
    RETURN QUERY EXECUTE 'SELECT * FROM ' || quote_ident(p_table);
END; $$ LANGUAGE plpgsql;
```

EXECUTE ... USING: 参数化动态 SQL（防注入，8.1+）
```sql
CREATE OR REPLACE FUNCTION find_users(p_status TEXT, p_min_age INT)
RETURNS SETOF users AS $$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT * FROM users WHERE status = $1 AND age >= $2'
        USING p_status, p_min_age;
END; $$ LANGUAGE plpgsql;
```

EXECUTE ... INTO: 结果存入变量
```sql
CREATE OR REPLACE FUNCTION count_rows(p_table TEXT)
RETURNS BIGINT AS $$
DECLARE row_count BIGINT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || quote_ident(p_table) INTO row_count;
    RETURN row_count;
END; $$ LANGUAGE plpgsql;
```

设计要点:
  PL/pgSQL 中的 EXECUTE 与 SQL 层的 EXECUTE（执行预编译语句）是完全不同的!
  PL/pgSQL EXECUTE 每次都重新解析+规划（无缓存），适合动态 DDL/变化的查询。
  普通 PL/pgSQL 语句（非 EXECUTE）会缓存执行计划。

## format(): 安全的动态 SQL 构建 (9.1+)

```sql
CREATE OR REPLACE FUNCTION dynamic_insert(p_table TEXT, p_name TEXT, p_value INT)
RETURNS VOID AS $$
BEGIN
    -- %I = 标识符（自动加引号），%L = 字面量（自动转义），%s = 字符串
    EXECUTE format(
        'INSERT INTO %I (name, value) VALUES (%L, %L)',
        p_table, p_name, p_value
    );
END; $$ LANGUAGE plpgsql;
```

动态 DDL（创建分区）
```sql
CREATE OR REPLACE FUNCTION create_partition(p_year INT)
RETURNS VOID AS $$
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS orders_%s PARTITION OF orders
         FOR VALUES FROM (%L) TO (%L)',
        p_year, p_year || '-01-01', (p_year + 1) || '-01-01'
    );
END; $$ LANGUAGE plpgsql;
```

format() vs 手动拼接:
  quote_ident('table')    → "table"（防止 SQL 注入和保留字冲突）
  quote_literal('value')  → 'value'（正确转义单引号）
  format('%I', 'table')   → "table"（更简洁）
  format('%L', 'it''s')   → 'it''s'（自动转义）

## DO 块: 匿名代码块 (9.0+)

```sql
DO $$
DECLARE tbl RECORD;
BEGIN
    FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ANALYZE ' || quote_ident(tbl.tablename);
    END LOOP;
END $$;
```

$$ 美元引号的设计价值:
  函数体中大量单引号时，传统引号需要双重/三重转义。
  $$ 完全消除了嵌套引号问题。
  可以使用自定义标签: $body$...$body$, $sql$...$sql$

## 动态游标

```sql
CREATE OR REPLACE FUNCTION process_table(p_table TEXT)
RETURNS VOID AS $$
DECLARE cur REFCURSOR; rec RECORD;
BEGIN
    OPEN cur FOR EXECUTE 'SELECT * FROM ' || quote_ident(p_table);
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        -- 处理记录
    END LOOP;
    CLOSE cur;
END; $$ LANGUAGE plpgsql;
```

## 横向对比: 动态 SQL 差异

### 语法

  PostgreSQL: EXECUTE string [USING params]（PL/pgSQL 内）
  MySQL:      PREPARE + EXECUTE + DEALLOCATE（SQL 层）
  Oracle:     EXECUTE IMMEDIATE string [USING params]（PL/SQL 内）
  SQL Server: sp_executesql / EXEC()

### 防注入机制

  PostgreSQL: quote_ident() + quote_literal() + format(%I, %L)
  MySQL:      ? 参数占位符
  Oracle:     USING 绑定变量
  SQL Server: sp_executesql @params

### 匿名块

  PostgreSQL: DO $$ ... $$ (9.0+)
  Oracle:     DECLARE BEGIN ... END;
  MySQL:      无等价功能
  SQL Server: 直接执行 T-SQL 块

## 对引擎开发者的启示

(1) 动态 SQL 的两层设计:
    SQL 层 PREPARE/EXECUTE（计划缓存）vs PL/pgSQL EXECUTE（无缓存）。
    这种分层让用户可以根据场景选择: 重复查询用 PREPARE，变化查询用 EXECUTE。

(2) format() 函数的设计值得借鉴:
    %I 和 %L 将"标识符引用"和"字面量转义"标准化为格式化操作。
    比手动调用 quote_ident/quote_literal 更安全（不容易忘记）。

(3) $$ 美元引号解决了所有嵌套引号问题:
    实现成本低（词法分析器增加一个状态），用户体验提升巨大。

## 版本演进

PostgreSQL 8.1:  EXECUTE ... USING（参数化动态 SQL）
PostgreSQL 9.0:  DO 匿名块
PostgreSQL 9.1:  format() 函数
PostgreSQL 12:   plan_cache_mode 参数（控制 custom/generic plan）
