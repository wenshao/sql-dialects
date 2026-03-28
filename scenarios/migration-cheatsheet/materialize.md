# Materialize: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [Materialize Documentation](https://materialize.com/docs/)
> - 一、与 PostgreSQL 兼容性: 基于PostgreSQL协议，大部分语法兼容
> - 差异: 流式物化视图引擎, 支持CDC源, 增量计算
> - 二、数据类型: 兼容PostgreSQL(TEXT, INT, JSONB, TIMESTAMPTZ等)
> - 三、陷阱: 流式引擎(不是传统数据库), CREATE SOURCE定义数据输入,
> - CREATE MATERIALIZED VIEW定义持续查询, 不支持DELETE/UPDATE,
> - 适合实时分析场景, 不适合OLTP
> - 四、自增: 无（数据从外部源流入）
> - 五、日期/字符串: 与 PostgreSQL 相同
> - NOW(); CURRENT_TIMESTAMP; EXTRACT(EPOCH FROM ts);
> - TO_CHAR(ts, 'YYYY-MM-DD HH24:MI:SS');
> - 六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, POSITION, ||
> - ============================================================
> - 七、数据类型映射（从 PostgreSQL/MySQL 到 Materialize）
> - ============================================================
> - PostgreSQL → Materialize: 基本兼容
> - INT → INT, TEXT → TEXT, JSONB → JSONB,
> - TIMESTAMPTZ → TIMESTAMPTZ, BOOLEAN → BOOLEAN,
> - SERIAL → 不支持（数据由外部源提供）
> - MySQL → Materialize:
> - INT → INT, VARCHAR → TEXT/VARCHAR,
> - DATETIME → TIMESTAMP, TINYINT(1) → BOOLEAN,
> - JSON → JSONB, AUTO_INCREMENT → 无
> - 八、函数等价映射
> - PostgreSQL → Materialize: 大部分兼容
> - COALESCE → COALESCE, NOW() → NOW(),
> - STRING_AGG → STRING_AGG (有限支持),
> - ROW_NUMBER/RANK → 支持 (窗口函数)
> - 不支持: UPDATE, DELETE, 存储过程, 触发器
> - 九、常见陷阱补充
> - Materialize 是流式引擎，不是传统数据库
> - CREATE SOURCE 定义外部数据源 (Kafka, PostgreSQL CDC 等)
> - CREATE MATERIALIZED VIEW 定义持续增量计算
> - 不支持 INSERT/UPDATE/DELETE (数据由源推送)
> - 不支持 CREATE TABLE (直接存储数据)
> - 物化视图的结果实时更新
> - 适合场景: 实时仪表盘, CDC 流处理, 事件驱动架构
> - 十、CDC 源配置示例
> - CREATE SOURCE pg_source
> - FROM POSTGRES CONNECTION 'host=... dbname=...'
> - PUBLICATION 'my_pub';
> - 十一、NULL 处理: 与 PostgreSQL 相同
> - COALESCE(a, b, c)
> - NULLIF(a, b)
> - IS DISTINCT FROM / IS NOT DISTINCT FROM
> - 十二、Materialize 特有概念
> - SUBSCRIBE: 订阅查询结果的变更
> - CLUSTER: 计算资源分组
> - INDEX: 加速查询的内存索引
