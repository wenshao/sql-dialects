# CockroachDB: 错误处理

> 参考资料:
> - [CockroachDB Documentation - PL/pgSQL](https://www.cockroachlabs.com/docs/stable/plpgsql.html)
> - [CockroachDB Documentation - Error Codes](https://www.cockroachlabs.com/docs/stable/error-handling-and-troubleshooting.html)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## EXCEPTION WHEN (PL/pgSQL 兼容)                      -- 23.1+

```sql
CREATE OR REPLACE FUNCTION safe_insert(p_name VARCHAR, p_email VARCHAR)
RETURNS TEXT AS $$
BEGIN
    INSERT INTO users(username, email) VALUES(p_name, p_email);
    RETURN 'Success';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'Duplicate entry';
    WHEN OTHERS THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

```

## RAISE (抛出消息和异常)

```sql
CREATE OR REPLACE FUNCTION validate_age(p_age INT)
RETURNS VOID AS $$
BEGIN
    IF p_age < 0 THEN
        RAISE EXCEPTION 'Age cannot be negative: %', p_age;
    END IF;
END;
$$ LANGUAGE plpgsql;

```

## 事务重试（CockroachDB 特有模式）

CockroachDB 可能因分布式事务冲突返回重试错误 (40001)
应用层应实现自动重试逻辑

**注意:** CockroachDB 兼容 PostgreSQL EXCEPTION WHEN 语法
**注意:** 分布式环境下 serialization failure (40001) 需要重试
**限制:** PL/pgSQL 功能可能不如 PostgreSQL 完整
