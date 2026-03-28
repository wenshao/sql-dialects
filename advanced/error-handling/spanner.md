# Spanner: 错误处理

> 参考资料:
> - [Cloud Spanner Documentation - Error Codes](https://cloud.google.com/spanner/docs/reference/errors)
> - [Cloud Spanner Documentation - Transactions](https://cloud.google.com/spanner/docs/transactions)
> - [Cloud Spanner Documentation - SQL Reference](https://cloud.google.com/spanner/docs/reference/standard-sql/)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## Spanner 错误处理概述

Google Cloud Spanner 是全球分布式关系数据库，没有存储过程或 SQL 级异常处理。
错误处理通过 gRPC 状态码 + 客户端库重试机制实现。
Spanner 的事务冲突由客户端库自动重试（ABORTED → exponential backoff）。

## 应用层错误捕获


Python 示例: 基本 try/except
from google.cloud import spanner
from google.api_core import exceptions as gcp_exceptions

client = spanner.Client()
instance = client.instance('my-instance')
database = instance.database('my-database')

try:
    def update_fn(transaction):
        transaction.execute_update(
            'INSERT INTO users (id, name) VALUES (@id, @name)',
            params={'id': 1, 'name': 'alice'},
            param_types={'id': spanner.param_types.INT64, 'name': spanner.param_types.STRING}
        )
    database.run_in_transaction(update_fn)
except gcp_exceptions.Aborted as e:
    print(f'Transaction aborted (conflict): {e}')
except gcp_exceptions.AlreadyExists as e:
    print(f'Resource already exists: {e}')
except gcp_exceptions.NotFound as e:
    print(f'Resource not found: {e}')
except gcp_exceptions.InvalidArgument as e:
    print(f'Invalid argument: {e}')
except gcp_exceptions.PermissionDenied as e:
    print(f'Permission denied: {e}')
except gcp_exceptions.InternalServerError as e:
    print(f'Internal error: {e}')
except gcp_exceptions.GoogleAPICallError as e:
    print(f'API error [{e.code}]: {e.message}')

Java 示例:
import com.google.cloud.spanner.SpannerException;
import com.google.cloud.spanner.AbortedException;
try {
    database.runInTransaction(transaction -> {
        transaction.executeUpdate(Statement.of("INSERT INTO users ..."));
    });
} catch (AbortedException e) {
    // 事务冲突，通常由客户端库自动重试
} catch (SpannerException e) {
    System.out.println("Error [" + e.getErrorCode() + "]: " + e.getMessage());
}

## Spanner gRPC 错误码


Spanner 使用 gRPC (Google RPC) 状态码，不遵循 SQL 标准 SQLSTATE:
  OK (0)                  = 成功
  CANCELLED (1)           = 操作被取消
  UNKNOWN (2)             = 未知错误
  INVALID_ARGUMENT (3)    = 参数无效 (SQL 语法错误、类型不匹配等)
  DEADLINE_EXCEEDED (4)   = 操作超时
  NOT_FOUND (5)           = 资源不存在 (表/数据库/索引)
  ALREADY_EXISTS (6)      = 资源已存在
  PERMISSION_DENIED (7)   = 权限不足
  RESOURCE_EXHAUSTED (8)  = 资源超限 (配额、存储等)
  FAILED_PRECONDITION (9) = 前置条件不满足 (Schema 冲突等)
  ABORTED (10)            = 事务冲突（核心错误码，触发自动重试）
  OUT_OF_RANGE (11)       = 值超范围
  UNIMPLEMENTED (12)      = 不支持的操作
  INTERNAL (13)           = 内部错误
  UNAVAILABLE (14)        = 服务不可用
  DATA_LOSS (15)          = 数据丢失

## SQL 层面的错误避免: 防御性写法


使用 IF NOT EXISTS 避免对象已存在错误
```sql
CREATE TABLE IF NOT EXISTS users (
    id    INT64 NOT NULL,
    name  STRING(100),
) PRIMARY KEY (id);

```

安全插入: 使用 INSERT OR UPDATE (Mutation API)
或在客户端库中使用 commit_timestamp 避免时间戳冲突

使用 COALESCE 避免空值错误
```sql
SELECT id, COALESCE(name, 'UNKNOWN') AS name FROM users;

```

使用 SAFE_DIVIDE 替代除法 (NULLIF 模拟)
```sql
SELECT id, numerator / NULLIF(denominator, 0) AS ratio FROM metrics;

```

使用 IF 条件避免无效操作
```sql
SELECT id, IF(value > 0, LOG(value), NULL) AS log_value FROM measurements;

```

## Spanner 特有错误场景与处理


场景 1: 事务冲突 (ABORTED)
错误: Transaction was aborted due to concurrent modification
解决: Spanner 客户端库自动重试（run_in_transaction 会重试 ABORTED 事务）
原理: Spanner 使用 TrueTime + MVCC，读写冲突会 ABORT 后发起者
最佳实践: 保持事务短小，减少冲突概率

场景 2: Schema 变更冲突
错误: FAILED_PRECONDITION - Schema change already in progress
解决: 检查当前 Schema 变更状态，等待完成后再操作
  SELECT * FROM information_schema.change_stream_options;

场景 3: 资源配额超限
错误: RESOURCE_EXHAUSTED - Quota exceeded
解决: 减少并发查询数或申请更多配额

场景 4: 分布式查询超时
错误: DEADLINE_EXCEEDED
解决: 优化查询（添加二级索引、减少扫描量）或增加超时时间

## 诊断: 系统视图与监控


查看数据库 Schema 信息
```sql
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = '';

```

查看列信息（排查类型错误）
```sql
SELECT table_name, column_name, spanner_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'users';

```

查看索引信息
```sql
SELECT table_name, index_name, index_type
FROM information_schema.indexes;

```

Cloud Console 监控:
  - Spanner Console > Monitoring: QPS, Latency, Error rates
  - Cloud Logging: 查询详细错误日志
  - Cloud Monitoring: 自定义告警 (ABORTED rate > threshold)

查询统计信息
```sql
SELECT text, execution_stats, all_scan_stats
FROM spanner_sys.query_stats_top_hour
ORDER BY avg_latency_seconds DESC
LIMIT 10;

```

## 事务重试机制 (核心设计)

Spanner 的 ABORTED 错误是设计上预期的，不是真正的"错误"：
  (a) 客户端库 (run_in_transaction) 自动捕获 ABORTED 并重试
  (b) 重试使用 exponential backoff 策略
  (c) 重试次数默认有限（通常 5-10 次）
  (d) 用户代码需要是幂等的（多次执行结果一致）

这与 PostgreSQL/MySQL 的锁等待机制不同:
  PostgreSQL: 读写冲突时等待或立即报错（取决于隔离级别）
  MySQL:      悲观锁等待
  Spanner:    乐观并发，冲突时 ABORT 并重试

## 版本说明

Spanner 通用:  gRPC 错误码，客户端库自动重试
Spanner 2021:  新增 information_schema 视图
Spanner 2022:  增强 query_stats_top 诊断视图
Spanner 2023:  新增 change streams，增强 Schema 变更错误处理
**注意:** 无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER 语法
**注意:** gRPC 状态码与 SQL 标准 SQLSTATE 完全不同
**注意:** ABORTED 事务重试是 Spanner 错误处理的核心机制
**限制:** 不支持存储过程、触发器
