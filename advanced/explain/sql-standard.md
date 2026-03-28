# SQL 标准: 执行计划与查询分析

> 参考资料:
> - [ISO/IEC 9075-1:2023 - SQL Standard](https://www.iso.org/standard/76583.html)
> - [SQL:2023 Foundation (ISO/IEC 9075-2:2023)](https://www.iso.org/standard/76584.html)

SQL 标准没有定义 EXPLAIN 语句
各数据库厂商各自实现了查询计划分析功能

## 概念：查询优化器与执行计划

查询执行流程：
1. 解析（Parse）：SQL 文本 → 语法树
2. 绑定（Bind）：解析标识符、验证语义
3. 优化（Optimize）：生成并选择最优执行计划
4. 执行（Execute）：按计划执行查询

查询优化器的类型：
- 基于规则（RBO, Rule-Based Optimization）
- 基于成本（CBO, Cost-Based Optimization）—— 现代主流
- 自适应优化（Adaptive Optimization）

## 主流数据库的执行计划语法对比

PostgreSQL / MySQL / MariaDB / SQLite / DuckDB:
EXPLAIN SELECT ...;
EXPLAIN ANALYZE SELECT ...;

Oracle:
EXPLAIN PLAN FOR SELECT ...;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

SQL Server:
SET SHOWPLAN_ALL ON;
SET STATISTICS PROFILE ON;

DB2:
EXPLAIN PLAN FOR SELECT ...;

## 执行计划中的关键概念

扫描方式（Scan Types）：
- 全表扫描（Full Table Scan / Seq Scan）
- 索引扫描（Index Scan）
- 索引全扫描（Index Full Scan）
- 仅索引扫描（Index Only Scan）
- 位图扫描（Bitmap Scan）

连接方式（Join Types）：
- 嵌套循环（Nested Loop）
- 哈希连接（Hash Join）
- 排序合并连接（Sort Merge Join）

其他操作：
- 排序（Sort）
- 聚合（Aggregate）
- 过滤（Filter）
- 物化（Materialize）
- 并行（Parallel）

成本指标：
- 估算行数（Estimated Rows）
- 估算成本（Estimated Cost）
- 实际行数（Actual Rows，EXPLAIN ANALYZE 时）
- 实际时间（Actual Time，EXPLAIN ANALYZE 时）

## 常见优化建议

1. 全表扫描 → 考虑添加索引
2. 排序操作 → 考虑索引排序
3. 嵌套循环大表 → 考虑哈希连接
4. 估算行数偏差大 → 更新统计信息
5. 临时表/排序溢出 → 增加工作内存

- **注意：EXPLAIN 不是 SQL 标准的一部分**
- **注意：各数据库的执行计划格式差异很大**
- **注意：EXPLAIN ANALYZE 会实际执行查询（DML 操作需要在事务中回滚）**
- **注意：执行计划的解读需要结合具体数据库的文档**
