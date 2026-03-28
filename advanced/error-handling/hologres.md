# Hologres: 错误处理 (Error Handling)

> 参考资料:
> - [Hologres Documentation - Error Codes](https://www.alibabacloud.com/help/en/hologres/error-codes)
> - [Hologres Documentation - SQL Reference](https://www.alibabacloud.com/help/en/hologres/developer-reference/sql-reference)
> - [Hologres Documentation - Best Practices](https://www.alibabacloud.com/help/en/hologres/best-practices)
> - ============================================================
> - 1. Hologres 错误处理概述
> - ============================================================
> - Hologres 是阿里云实时数仓，兼容 PostgreSQL 协议和部分语法。
> - 但存储过程/PL/pgSQL 支持有限，不支持 EXCEPTION WHEN 等服务端错误处理。
> - 错误处理主要依赖应用层捕获 + SQL 防御性写法。
> - ============================================================
> - 2. 应用层错误捕获
> - ============================================================
> - Python (psycopg2) 示例: 基本错误捕获
> - import psycopg2
> - conn = psycopg2.connect(host='hgprecn-xxx.hologres.aliyuncs.com', port=80, ...)
> - cursor = conn.cursor()
> - try:
> - cursor.execute("INSERT INTO users VALUES(1, 'test')")
> - conn.commit()
> - except psycopg2.errors.UniqueViolation as e:
> - print(f'Unique constraint violation: {e}')
> - conn.rollback()
> - except psycopg2.errors.NotNullViolation as e:
> - print(f'NOT NULL violation: {e}')
> - conn.rollback()
> - except psycopg2.errors.ForeignKeyViolation as e:
> - print(f'Foreign key violation: {e}')
> - conn.rollback()
> - except psycopg2.Error as e:
> - print(f'General error: {e.pgcode} - {e.pgerror}')
> - conn.rollback()
> - Java (JDBC) 示例:
> - try {
> - stmt.executeUpdate("INSERT INTO users VALUES(1, 'test')");
> - } catch (java.sql.SQLIntegrityConstraintViolationException e) {
> - // 约束违反 (SQLSTATE 23xxx)
> - } catch (java.sql.SQLException e) {
> - // 通用 SQL 错误
> - }
> - ============================================================
> - 3. Hologres 常见错误码
> - ================================================================
> - Hologres 兼容 PostgreSQL SQLSTATE 编码:
> - 23505 = 唯一约束违反 (Unique Violation)
> - 23502 = NULL 约束违反 (Not Null Violation)
> - 23503 = 外键约束违反 (Foreign Key Violation)
> - 42P01 = 表不存在 (Undefined Table)
> - 42703 = 列不存在 (Undefined Column)
> - 42P07 = 表已存在 (Duplicate Table)
> - 42501 = 权限不足 (Insufficient Privilege)
> - 08006 = 连接失败 (Connection Failure)
> - 53200 = 内存不足 (Out of Memory)
> - HV000 = FDW 错误 (Foreign Data Wrapper Error)
> - Hologres 特有错误码:
> - HGERR_code = 内部执行引擎错误
> - ERPC_ERROR = 分布式 RPC 通信错误
> - OOM_ERROR = 资源超限（内存/CPU）
> - ============================================================
> - 4. SQL 层面的错误避免: 防御性写法
> - ============================================================
> - 使用 IF NOT EXISTS 避免建表冲突

```sql
CREATE TABLE IF NOT EXISTS users (
    id    INT PRIMARY KEY,
    name  TEXT,
    email TEXT
);
```

## 安全插入: INSERT ON CONFLICT (UPSERT)                -- Hologres 支持

```sql
INSERT INTO users(id, name, email)
VALUES(1, 'alice', 'alice@example.com')
ON CONFLICT (id) DO UPDATE SET
    name  = EXCLUDED.name,
    email = EXCLUDED.email;
```

## 条件插入: 仅在记录不存在时插入

```sql
INSERT INTO users(id, name)
SELECT 2, 'bob'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = 2);
```

## 安全删除

```sql
DELETE FROM users WHERE id = 999;
```

## Hologres 特有错误场景与处理


场景 1: 分区表操作错误
错误: ALTER TABLE partitioned_table ADD COLUMN col INT;
原因: Hologres 分区表不支持直接 ALTER，需要使用 Partitioned Table DDL
解决: 通过重建分区表或使用 RESHAPE CLUSTER 迁移
场景 2: 内存超限 (OOM)
错误: Query canceled due to memory limit exceeded
解决: 减少查询复杂度或增加实例资源
SET statement_mem = '2048MB';  -- 增加单查询内存上限
SELECT ... LIMIT 1000;          -- 分批查询
场景 3: 并发写入冲突
错误: Conflict with another transaction
解决: Hologres 使用 MVCC，短事务冲突自动重试
长事务建议拆分为多个小事务以减少冲突窗口
场景 4: FDW 外表查询失败
错误: HV000: Failed to connect to foreign data wrapper
解决: 检查外部数据源连接配置
SELECT * FROM hologres_fdw_external_table;  -- 验证外表连通性

## 诊断: 系统视图


## 查看当前活跃查询（排查长事务/死锁）

```sql
SELECT query_id, query_text, state, duration_ms
FROM hologres.hg_query_history
ORDER BY query_start DESC
LIMIT 20;
```

## 查看慢查询

```sql
SELECT query_id, query_text, duration_ms, query_start
FROM hologres.hg_query_history
WHERE duration_ms > 5000   -- 超过 5 秒的查询
ORDER BY duration_ms DESC;
```

## 查看资源使用情况（排查 OOM）

```sql
SELECT query_id, query_text, peak_memory_bytes
FROM hologres.hg_query_history
ORDER BY peak_memory_bytes DESC
LIMIT 10;
```

## 查看表统计信息（排查查询计划异常）

```sql
SELECT schemaname, tablename, n_live_tup, n_dead_tup
FROM pg_stat_user_tables;
```

## 查看当前连接

```sql
SELECT pid, usename, application_name, state, query
FROM pg_stat_activity
WHERE state != 'idle';
```

## Hologres 与 PostgreSQL 错误处理的差异

PostgreSQL:     完整 PL/pgSQL 支持 (EXCEPTION WHEN, RAISE, GET STACKED DIAGNOSTICS)
Hologres:      不支持 PL/pgSQL 的 EXCEPTION WHEN 块
共同点:         SQLSTATE 编码兼容，psycopg2 驱动通用
共同点:         pg_stat_activity 系统视图可用
差异:           Hologres 无子事务/SAVEPOINT 支持
差异:           Hologres 错误消息包含更多分布式执行上下文

## 版本说明

Hologres V0.7:  基础 PostgreSQL 兼容，基础错误码
Hologres V0.10: 新增 hg_query_history 视图，查询诊断增强
Hologres V1.1:  新增 INSERT ON CONFLICT 支持
Hologres V1.3:  改进 OOM 错误消息，增加资源使用建议
Hologres V2.0:  增强分布式错误追踪和诊断能力
注意: 不支持 EXCEPTION WHEN, DECLARE HANDLER, SIGNAL, RESIGNAL
注意: 错误处理在应用层通过 PostgreSQL 兼容驱动实现
限制: 不支持 PL/pgSQL 存储过程（仅支持简单的 SQL 函数）
