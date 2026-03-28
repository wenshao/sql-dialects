# PostgreSQL: 存储过程

> 参考资料:
> - [PostgreSQL Documentation - CREATE FUNCTION](https://www.postgresql.org/docs/current/sql-createfunction.html)
> - [PostgreSQL Documentation - CREATE PROCEDURE (11+)](https://www.postgresql.org/docs/current/sql-createprocedure.html)
> - [PostgreSQL Documentation - PL/pgSQL](https://www.postgresql.org/docs/current/plpgsql.html)

## 函数 vs 过程: PostgreSQL 的双轨设计

函数（所有版本）: 有返回值，不能事务控制
```sql
CREATE OR REPLACE FUNCTION get_user_count() RETURNS INTEGER AS $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
    RETURN v_count;
END; $$ LANGUAGE plpgsql;

SELECT get_user_count();
```

过程（11+）: 无返回值，可以 COMMIT/ROLLBACK
```sql
CREATE OR REPLACE PROCEDURE transfer(p_from BIGINT, p_to BIGINT, p_amount NUMERIC)
LANGUAGE plpgsql AS $$
DECLARE v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;
    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance: % < %', v_balance, p_amount;
    END IF;
    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
    COMMIT;  -- 过程内可以 COMMIT（函数不行!）
END; $$;

CALL transfer(1, 2, 100.00);
```

设计分析: 为什么 11 才加 PROCEDURE
  PostgreSQL 长期以来用"有副作用的函数"替代存储过程。
  但函数不能 COMMIT/ROLLBACK（函数调用本身在一个事务中）。
  11 引入 PROCEDURE 填补了这个空白——长事务可以中间提交。
  对比: MySQL/Oracle/SQL Server 从一开始就有存储过程。

## 函数的多种返回模式

SQL 语言函数（最简单，纯 SQL）
```sql
CREATE OR REPLACE FUNCTION get_user(p_name VARCHAR)
RETURNS TABLE (id BIGINT, username VARCHAR, email VARCHAR) AS $$
    SELECT id, username, email FROM users WHERE username = p_name;
$$ LANGUAGE sql;
```

OUT 参数
```sql
CREATE OR REPLACE FUNCTION get_stats(
    OUT min_age INT, OUT max_age INT, OUT avg_age NUMERIC
) AS $$
    SELECT MIN(age), MAX(age), AVG(age) FROM users;
$$ LANGUAGE sql;
SELECT * FROM get_stats();
```

SETOF（返回多行）
```sql
CREATE OR REPLACE FUNCTION active_users() RETURNS SETOF users AS $$
    SELECT * FROM users WHERE status = 1;
$$ LANGUAGE sql;
SELECT * FROM active_users();
```

## $$ 美元引号: 函数体的优雅解决方案

没有 $$ 时，函数体中的单引号需要双重转义:
```sql
CREATE FUNCTION f() RETURNS TEXT AS '
    SELECT ''it''''s a test'';
```

' LANGUAGE sql;

使用 $$ 完全消除转义:
```sql
CREATE FUNCTION f() RETURNS TEXT AS $$
    SELECT 'it''s a test';
$$ LANGUAGE sql;
```

嵌套时用自定义标签:
```sql
CREATE FUNCTION outer_func() RETURNS VOID AS $outer$
BEGIN
    EXECUTE $inner$SELECT 'hello'$inner$;
END;
$outer$ LANGUAGE plpgsql;
```

## 多语言支持: PostgreSQL 的可扩展过程语言

LANGUAGE sql:       纯 SQL（最简单，内联优化友好）
LANGUAGE plpgsql:   PL/pgSQL（PostgreSQL 原生过程语言）
LANGUAGE plpython3u: Python（需安装 plpython3u 扩展）
LANGUAGE plv8:       JavaScript（需安装 plv8 扩展）
LANGUAGE plperl:     Perl
LANGUAGE c:          C 语言（最高性能，需编译动态库）

设计分析: 可扩展过程语言架构
  PostgreSQL 的 CREATE LANGUAGE 命令可以注册新的过程语言。
  每种语言提供 call_handler 函数（C 编写），
  PostgreSQL 调用 call_handler 来执行用该语言编写的函数。
  这种架构让 Python/JavaScript/Perl 函数与 SQL 完全集成。

对比:
  MySQL:      只有 SQL（存储过程/函数）
  Oracle:     PL/SQL + Java + C
  SQL Server: T-SQL + CLR（.NET）

## 函数属性: VOLATILITY 和 PARALLEL 标记

```sql
CREATE FUNCTION my_func(x INT) RETURNS INT AS $$
    SELECT x * 2;
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;
```

波动性:
  VOLATILE:  每次调用可能返回不同结果（默认，如 NOW()、RANDOM()）
  STABLE:    同一事务内多次调用返回相同结果（如 current_timestamp）
  IMMUTABLE: 相同输入总是返回相同结果（如数学运算）

对优化器的影响:
  IMMUTABLE: 可以在索引表达式中使用，优化器可以常量折叠
  STABLE:    可以在 IndexScan 中使用（同一查询内值不变）
  VOLATILE:  不能用于索引，每行都要重新计算

并行安全:
  PARALLEL SAFE:       可以在并行查询中执行
  PARALLEL RESTRICTED: 只能在 leader 进程执行
  PARALLEL UNSAFE:     阻止并行查询（默认）

## 安全模式: SECURITY DEFINER vs SECURITY INVOKER

SECURITY INVOKER（默认）: 以调用者权限执行
```sql
CREATE FUNCTION f1() RETURNS VOID AS $$ ... $$ SECURITY INVOKER;
```

SECURITY DEFINER: 以函数创建者权限执行（类似 Unix SUID）
```sql
CREATE FUNCTION admin_only_operation() RETURNS VOID AS $$
BEGIN
    -- 即使普通用户调用，也以 admin 权限执行
    DELETE FROM audit_logs WHERE created_at < NOW() - INTERVAL '1 year';
END; $$ LANGUAGE plpgsql SECURITY DEFINER;
```

SECURITY DEFINER 的安全注意:
  函数内的 search_path 可能被劫持！
  最佳实践: 在函数内显式设置 search_path
```sql
CREATE FUNCTION safe_func() RETURNS VOID AS $$
BEGIN
    SET search_path = public, pg_temp;
    -- ... 操作 ...
END; $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
```

## 横向对比: 存储过程能力

### 过程 vs 函数

  PostgreSQL: 函数(全版本) + 过程(11+, 可 COMMIT)
  MySQL:      函数 + 过程（过程可 COMMIT）
  Oracle:     函数 + 过程（过程最强大，支持包 PACKAGE）
  SQL Server: 函数（不能 DML）+ 过程（可 COMMIT）

### 多语言

  PostgreSQL: SQL + PL/pgSQL + Python + JS + Perl + C（最多）
  Oracle:     PL/SQL + Java + C
  SQL Server: T-SQL + CLR (.NET)
  MySQL:      只有 SQL

### 函数内联

  PostgreSQL: SQL 语言函数可被优化器内联（不创建函数调用开销）
  其他:       通常不内联函数

## 对引擎开发者的启示

(1) SQL 语言函数的内联优化:
    简单的 SQL 函数（LANGUAGE sql）可被优化器展开到外部查询中。
    效果等同于视图——没有函数调用开销，可以参与谓词下推等优化。
    PL/pgSQL 函数不能内联（因为有过程控制流）。

(2) VOLATILITY 标记影响优化决策:
    IMMUTABLE 函数可以在索引表达式中使用、被常量折叠。
    错误标记（如将 VOLATILE 标记为 IMMUTABLE）会导致错误结果。

(3) 可扩展过程语言是 PostgreSQL 生态的基础:
    PostGIS（C语言）、pgvector（C语言）、Supabase Edge Functions（plv8）
    都依赖于这个架构。

## 版本演进

PostgreSQL 全版本: CREATE FUNCTION, PL/pgSQL
PostgreSQL 9.2:   DO $$ ... $$ 块中支持 LANGUAGE 参数
PostgreSQL 11:    CREATE PROCEDURE（支持事务控制）
PostgreSQL 12:    SQL 标准过程调用 CALL
PostgreSQL 14:    PROCEDURE 支持 OUT 参数
