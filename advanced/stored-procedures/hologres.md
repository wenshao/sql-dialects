# Hologres: 存储过程和函数

> 参考资料:
> - [Hologres SQL Reference](https://help.aliyun.com/zh/hologres/user-guide/overview-27)
> - [Hologres Built-in Functions](https://help.aliyun.com/zh/hologres/user-guide/built-in-functions)
> - Hologres 兼容 PostgreSQL 语法，支持部分函数功能
> - ============================================================
> - SQL 函数
> - ============================================================

```sql
CREATE OR REPLACE FUNCTION full_name(first TEXT, last TEXT)
RETURNS TEXT
AS $$
    SELECT first || ' ' || last;
$$ LANGUAGE sql;

SELECT full_name('Alice', 'Smith');
```

## PL/pgSQL 函数（部分兼容）


```sql
CREATE OR REPLACE FUNCTION get_user_count()
RETURNS BIGINT AS $$
DECLARE
    v_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

SELECT get_user_count();
```

## 带参数的函数

```sql
CREATE OR REPLACE FUNCTION get_user_status(p_id BIGINT)
RETURNS TEXT AS $$
DECLARE
    v_status INT;
BEGIN
    SELECT status INTO v_status FROM users WHERE id = p_id;
    IF v_status = 1 THEN
        RETURN 'active';
    ELSIF v_status = 0 THEN
        RETURN 'inactive';
    ELSE
        RETURN 'unknown';
    END IF;
END;
$$ LANGUAGE plpgsql;
```

## 表返回函数


```sql
CREATE OR REPLACE FUNCTION active_users()
RETURNS SETOF users AS $$
    SELECT * FROM users WHERE status = 1;
$$ LANGUAGE sql;

SELECT * FROM active_users();
```

## 返回 TABLE 类型

```sql
CREATE OR REPLACE FUNCTION users_by_age(min_age INT, max_age INT)
RETURNS TABLE (id BIGINT, username TEXT, age INT) AS $$
    SELECT id, username, age FROM users WHERE age BETWEEN min_age AND max_age;
$$ LANGUAGE sql;

SELECT * FROM users_by_age(18, 30);
```

## 内置函数和扩展


## Hologres 提供丰富的内置函数

```sql
SELECT
    upper(username),
    length(email),
    substring(email, 1, 5),
    concat(first_name, ' ', last_name),
    coalesce(phone, 'N/A'),
    now(),
    date_trunc('day', created_at)
FROM users;
```

## JSON 函数

```sql
SELECT
    json_extract_path_text(data::json, 'name'),
    jsonb_extract_path(data::jsonb, 'address', 'city')
FROM events;
```

## 数组和聚合函数


## 数组操作

```sql
SELECT array_agg(username) FROM users WHERE status = 1;
SELECT unnest(ARRAY[1, 2, 3]);
```

## 窗口函数

```sql
SELECT
    id, username,
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_num,
    RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS rank
FROM users;
```

## CALL 语句（Hologres 特有）


## Hologres 使用 CALL 设置表属性（不是传统的存储过程调用）

```sql
CALL set_table_property('users', 'orientation', 'column');
CALL set_table_property('users', 'clustering_key', 'id');
CALL set_table_property('users', 'time_to_live_in_seconds', '7776000');
```

## 删除函数


```sql
DROP FUNCTION IF EXISTS full_name(TEXT, TEXT);
DROP FUNCTION IF EXISTS get_user_count();
```

注意：Hologres 兼容大部分 PostgreSQL 函数语法
注意：PL/pgSQL 支持程度有限（不支持所有 PostgreSQL PL/pgSQL 特性）
注意：不支持 CREATE PROCEDURE（PostgreSQL 11+ 的存储过程语法）
注意：CALL 语句用于 Hologres 专有的系统过程，不是通用过程调用
注意：复杂 ETL 逻辑建议在外部编排工具中实现
