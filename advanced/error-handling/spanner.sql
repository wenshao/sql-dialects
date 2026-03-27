-- Google Cloud Spanner: Error Handling
--
-- 参考资料:
--   [1] Cloud Spanner Documentation
--       https://cloud.google.com/spanner/docs/reference/standard-sql/

-- ============================================================
-- Spanner 不支持服务端错误处理
-- ============================================================
-- Spanner 没有存储过程或异常处理语法

-- 应用层替代方案 (Python):
-- from google.cloud import spanner
-- from google.api_core import exceptions
-- try:
--     database.run_in_transaction(update_fn)
-- except exceptions.Aborted:
--     # 事务冲突，Spanner 客户端自动重试
-- except exceptions.NotFound as e:
--     print(f'Not found: {e}')
-- except exceptions.AlreadyExists as e:
--     print(f'Already exists: {e}')

-- Spanner gRPC 错误码:
-- OK (0), CANCELLED (1), INVALID_ARGUMENT (3),
-- NOT_FOUND (5), ALREADY_EXISTS (6), ABORTED (10),
-- RESOURCE_EXHAUSTED (8), INTERNAL (13)

-- 注意：Spanner 使用 gRPC 错误码
-- 注意：事务冲突 (ABORTED) 由客户端库自动重试
-- 限制：无 SQL 级别的错误处理语法
