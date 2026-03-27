-- Hive: 权限管理
--
-- 参考资料:
--   [1] Apache Hive - SQL Standard Based Authorization
--       https://cwiki.apache.org/confluence/display/Hive/SQL+Standard+Based+Hive+Authorization
--   [2] Apache Hive - Authorization
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Authorization

-- Hive 支持多种授权模式

-- ============================================================
-- 授权模式选择
-- ============================================================

-- 1. Storage Based Authorization（基于 HDFS 权限）
-- 2. SQL Standards Based Authorization（基于 SQL 标准，Hive 0.13+）
-- 3. Apache Ranger / Apache Sentry（外部授权框架，推荐）
-- 4. Default Hive Authorization（旧模式，不推荐）

-- ============================================================
-- SQL Standards Based Authorization（SSBA）
-- ============================================================

-- 配置（hive-site.xml）：
-- hive.security.authorization.manager =
--     org.apache.hadoop.hive.ql.security.authorization.plugin.sqlstd.SQLStdHiveAuthorizerFactory
-- hive.security.authorization.enabled = true
-- hive.server2.enable.doAs = false

-- ============================================================
-- 用户和角色管理
-- ============================================================

-- 创建角色
CREATE ROLE analyst;
CREATE ROLE data_engineer;

-- 查看角色
SHOW ROLES;
SHOW CURRENT ROLES;

-- 授予角色给用户
GRANT ROLE analyst TO USER alice;
GRANT ROLE data_engineer TO USER bob;

-- 撤销角色
REVOKE ROLE analyst FROM USER alice;

-- 删除角色
DROP ROLE analyst;

-- 设置当前角色
SET ROLE analyst;
SET ROLE ALL;  -- 激活所有角色

-- ============================================================
-- 数据库权限
-- ============================================================

GRANT ALL ON DATABASE mydb TO ROLE data_engineer;
GRANT SELECT ON DATABASE mydb TO ROLE analyst;

REVOKE ALL ON DATABASE mydb FROM ROLE analyst;

-- ============================================================
-- 表权限
-- ============================================================

GRANT SELECT ON TABLE users TO ROLE analyst;
GRANT SELECT, INSERT ON TABLE users TO ROLE data_engineer;
GRANT ALL ON TABLE users TO ROLE data_engineer;

-- 列级权限
GRANT SELECT (username, email) ON TABLE users TO ROLE analyst;

REVOKE SELECT ON TABLE users FROM ROLE analyst;

-- ============================================================
-- 权限类型
-- ============================================================

-- SELECT: 读取数据
-- INSERT: 插入数据
-- UPDATE: 更新数据（ACID 表）
-- DELETE: 删除数据（ACID 表）
-- ALL: 所有权限

-- ============================================================
-- 查看权限
-- ============================================================

SHOW GRANT ROLE analyst ON TABLE users;
SHOW GRANT USER alice ON TABLE users;
SHOW GRANT ON TABLE users;

-- ============================================================
-- Apache Ranger（推荐的企业级方案）
-- ============================================================

-- Ranger 提供集中式的细粒度授权管理
-- 支持 Hive、HDFS、HBase、Kafka 等组件统一管理

-- Ranger 功能：
-- 1. 基于策略的授权（Policy-Based）
-- 2. 行级过滤（Row-Level Filter）
-- 3. 列级掩码（Column Masking）
-- 4. 审计日志
-- 5. 标签（Tag）授权

-- Ranger 行级过滤策略（在 Ranger UI 中配置）：
-- 表: users
-- 过滤条件: department = '{USER}'
-- 效果: 用户只能看到自己部门的数据

-- Ranger 列级掩码策略（在 Ranger UI 中配置）：
-- 表: users
-- 列: email
-- 掩码类型: MASK_SHOW_LAST_4
-- 效果: email 显示为 xxxx@xxx.com

-- ============================================================
-- Storage Based Authorization
-- ============================================================

-- 基于 HDFS 的文件权限
-- Hive 表对应 HDFS 目录
-- HDFS 权限（owner/group/other）控制访问

-- hadoop fs -chmod 750 /user/hive/warehouse/mydb.db/users
-- hadoop fs -chown hive:analysts /user/hive/warehouse/mydb.db/users

-- ============================================================
-- 管理员权限
-- ============================================================

-- Hive 管理员（配置在 hive-site.xml）
-- hive.users.in.admin.role = hive,admin

-- 管理员角色
GRANT ADMIN OPTION ROLE data_engineer TO USER admin;

-- 注意：推荐使用 Apache Ranger 进行企业级权限管理
-- 注意：SQL Standards Based Authorization 需要通过 HiveServer2 访问
-- 注意：直接访问 HDFS 可能绕过 Hive 权限
-- 注意：Ranger 提供行级过滤和列级掩码
-- 注意：存储层和 SQL 层的权限需要分别管理
