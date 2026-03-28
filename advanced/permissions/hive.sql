-- Hive: 权限管理
--
-- 参考资料:
--   [1] Apache Hive - SQL Standard Based Authorization
--       https://cwiki.apache.org/confluence/display/Hive/SQL+Standard+Based+Hive+Authorization
--   [2] Apache Hive - Authorization
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Authorization
--   [3] Apache Ranger
--       https://ranger.apache.org/

-- ============================================================
-- 1. 三种授权模型
-- ============================================================
-- Hive 提供三种授权模型，反映了从简单到企业级的演进:
--
-- 1. Storage-Based Authorization (默认):
--    利用 HDFS 文件权限控制访问
--    优点: 零配置，与 HDFS 权限一致
--    缺点: 只能控制到目录级别（表/分区），无法控制列级别
--
-- 2. SQL Standard Based Authorization (Hive 2.0+):
--    基于 GRANT/REVOKE 的 SQL 标准权限模型
--    优点: SQL 标准兼容，支持列级权限
--    缺点: 只在 HiveServer2 中生效，直接访问 HDFS 可以绕过
--
-- 3. Apache Ranger / Sentry (企业级):
--    外部集中式权限管理系统
--    优点: 行级过滤、列级掩码、审计日志、多组件统一管理
--    缺点: 额外的运维复杂度

-- ============================================================
-- 2. SQL Standard Based Authorization
-- ============================================================
-- 需要在 hive-site.xml 中配置:
-- hive.security.authorization.manager =
--   org.apache.hadoop.hive.ql.security.authorization.plugin.sqlstd.SQLStdHiveAuthorizerFactory
-- hive.security.authorization.enabled = true
-- hive.server2.enable.doAs = false

-- 数据库权限
GRANT ALL ON DATABASE analytics TO ROLE admin_role;
GRANT SELECT ON DATABASE analytics TO ROLE analyst;
REVOKE ALL ON DATABASE analytics FROM ROLE analyst;

-- 表权限
GRANT SELECT ON TABLE users TO USER alice;
GRANT SELECT, INSERT ON TABLE users TO ROLE etl_role;
GRANT ALL ON TABLE users TO USER admin WITH GRANT OPTION;
REVOKE SELECT ON TABLE users FROM USER alice;

-- 列级权限（Hive 0.12+）
GRANT SELECT (username, email) ON TABLE users TO ROLE analyst;
-- analyst 角色只能查询 username 和 email 列

-- 权限类型:
-- SELECT: 读取数据
-- INSERT: 写入数据
-- UPDATE: 更新数据（ACID 表）
-- DELETE: 删除数据（ACID 表）
-- ALL:    所有权限

-- ============================================================
-- 3. 角色管理
-- ============================================================
CREATE ROLE analyst;
CREATE ROLE data_engineer;

-- 授予角色给用户
GRANT ROLE analyst TO USER alice;
GRANT ROLE data_engineer TO USER bob;
GRANT ROLE analyst TO ROLE data_engineer;  -- 角色继承

-- 撤销角色
REVOKE ROLE analyst FROM USER alice;

-- 查看角色
SHOW ROLES;
SHOW CURRENT ROLES;
SHOW ROLE GRANT USER alice;

-- 设置当前角色
SET ROLE analyst;
SET ROLE ALL;    -- 激活所有角色
SET ROLE NONE;   -- 取消所有角色

DROP ROLE analyst;

-- 管理员权限
GRANT ADMIN OPTION ROLE data_engineer TO USER admin_user;

-- ============================================================
-- 4. 查看权限
-- ============================================================
SHOW GRANT ROLE analyst ON TABLE users;
SHOW GRANT USER alice ON TABLE users;
SHOW GRANT ON TABLE users;
SHOW GRANT USER alice ON DATABASE analytics;

-- ============================================================
-- 5. Apache Ranger: 企业级方案
-- ============================================================
-- 生产环境强烈推荐使用 Ranger 而非 Hive 内置权限。
-- Ranger 提供:
-- 1. 集中式策略管理: Web UI 配置所有组件（Hive/HDFS/HBase/Kafka）权限
-- 2. 行级过滤 (Row-Level Filter):
--    策略: 表=users, 条件=department='{USER}'
--    效果: 用户只能看到自己部门的数据
-- 3. 列级掩码 (Column Masking):
--    策略: 表=users, 列=email, 掩码类型=MASK_SHOW_LAST_4
--    效果: email 显示为 xxxx@xxx.com
-- 4. 审计日志: 记录所有访问操作
-- 5. 标签授权 (Tag-Based): 基于 Atlas 数据分类标签控制访问

-- 设计分析: 为什么 Hive 内置权限不够用?
-- 1. HDFS 绕过: 用户可以直接访问 HDFS 绕过 Hive 权限检查
-- 2. 多引擎问题: Hive 权限在 Spark/Trino 中不生效
-- 3. 无行级安全: SQL Standard Authorization 不支持行级过滤
-- 4. 无数据脱敏: 不能自动掩码敏感数据

-- Storage Based Authorization 示例:
-- HDFS 权限控制:
-- hadoop fs -chmod 750 /user/hive/warehouse/analytics.db/users
-- hadoop fs -chown hive:analysts /user/hive/warehouse/analytics.db/users

-- ============================================================
-- 6. 跨引擎对比: 权限模型
-- ============================================================
-- 引擎          权限模型          行级安全   列级掩码   设计理由
-- MySQL         GRANT/REVOKE      无(手动)   无         OLTP用户级权限
-- PostgreSQL    GRANT + RLS       RLS(9.5+)  无(VIEW)   最灵活的内置权限
-- Oracle        GRANT + VPD       VPD        Data Redact 企业级安全
-- Hive          GRANT + Ranger    Ranger     Ranger     外部化权限管理
-- BigQuery      IAM               无(VIEW)   无(VIEW)   云原生权限
-- Snowflake     RBAC              无(Policy) 动态掩码   云数仓权限
-- Trino         SPI AccessControl Ranger     Ranger     可插拔权限
-- Spark SQL     继承Hive/Ranger   Ranger     Ranger     依赖生态权限

-- ============================================================
-- 7. 已知限制
-- ============================================================
-- 1. 内置权限只通过 HiveServer2 生效: CLI/直接 HDFS 访问绕过权限
-- 2. 无 CREATE USER: 用户由 LDAP/Kerberos 等外部系统管理
-- 3. GRANT 不跨引擎: Hive 的 GRANT 在 Spark SQL 中不生效
-- 4. 无行级安全(内置): 需要 Ranger
-- 5. 无动态数据脱敏(内置): 需要 Ranger
-- 6. 管理员可以绕过所有权限

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================
-- 1. 权限应该外部化: Hive 的经验表明内置权限管理不够强大，
--    Ranger 的成功证明了集中式外部权限系统是正确的方向
-- 2. 存储层权限 vs SQL 层权限: 两层权限是大数据生态的现实，
--    需要在两层之间保持一致性（或用 Ranger 统一管理）
-- 3. 行级安全和列级掩码是企业级必需: PostgreSQL 的 RLS 是内置方案的典范，
--    大数据引擎通常通过外部系统（Ranger/OPA）实现
-- 4. 可插拔权限接口: Trino 的 SystemAccessControl SPI 是好的设计，
--    允许用户选择 Ranger/OPA/自定义权限后端
