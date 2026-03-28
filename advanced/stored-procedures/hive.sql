-- Hive: 存储过程与自定义函数 (UDF/UDAF/UDTF)
--
-- 参考资料:
--   [1] Apache Hive - HPL/SQL
--       https://cwiki.apache.org/confluence/display/Hive/HPL-SQL
--   [2] Apache Hive - UDF Development
--       https://cwiki.apache.org/confluence/display/Hive/HivePlugins
--   [3] Apache Hive - TRANSFORM
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Transform

-- ============================================================
-- 1. Hive 没有传统存储过程
-- ============================================================
-- 这是有意的设计选择:
-- 1. 批处理引擎: 存储过程假设低延迟的语句级别执行，Hive 每条 SQL 是一个 MR/Tez 作业
-- 2. 无状态执行: Hive 编译 SQL → DAG → 提交到 YARN，没有持久的服务端会话状态
-- 3. 编排在外部: ETL 流水线由 Airflow/Oozie 等调度工具编排，不需要 SQL 过程式逻辑
--
-- 替代方案体系:
-- UDF/UDAF/UDTF:     单行/聚合/表生成函数（Java 实现）
-- TRANSFORM:          调用外部脚本（Python/Shell/任意语言）
-- Macro:              简单的表达式别名
-- HPL/SQL (2.0+):     过程式语言扩展（使用不广泛）

-- ============================================================
-- 2. UDF: 标量函数 (一行输入 → 一行输出)
-- ============================================================
-- 内置 UDF 示例
SELECT
    UPPER(username),
    LENGTH(email),
    SUBSTR(email, 1, 5),
    CONCAT(first_name, ' ', last_name),
    NVL(phone, 'N/A'),
    COALESCE(phone, mobile, 'N/A')
FROM users;

-- 查看函数
SHOW FUNCTIONS;
DESCRIBE FUNCTION concat;
DESCRIBE FUNCTION EXTENDED concat;

-- 自定义 UDF (Java)
-- public class MyUpperUDF extends UDF {
--     public String evaluate(String input) {
--         return input == null ? null : input.toUpperCase();
--     }
-- }

-- 注册临时函数（会话级）
ADD JAR /path/to/my_udf.jar;
CREATE TEMPORARY FUNCTION my_upper AS 'com.example.udf.MyUpperUDF';
SELECT my_upper(username) FROM users;
DROP TEMPORARY FUNCTION IF EXISTS my_upper;

-- 注册永久函数（Metastore 级，Hive 0.13+）
CREATE FUNCTION analytics.my_upper AS 'com.example.udf.MyUpperUDF'
    USING JAR 'hdfs:///libs/my_udf.jar';
DROP FUNCTION IF EXISTS analytics.my_upper;

-- 设计分析: UDF vs GenericUDF
-- UDF:         简单接口，通过 evaluate() 方法重载实现类型支持
-- GenericUDF:  更灵活，支持复杂类型输入/输出，编译时类型检查
-- 推荐使用 GenericUDF（虽然实现更复杂但能力更强）

-- ============================================================
-- 3. UDAF: 聚合函数 (多行输入 → 一行输出)
-- ============================================================
-- 内置 UDAF
SELECT
    department,
    COUNT(*) AS cnt,
    SUM(salary) AS total_salary,
    COLLECT_LIST(name) AS members,      -- Hive 特有: 聚合为数组
    COLLECT_SET(name) AS unique_members  -- Hive 特有: 聚合为去重数组
FROM employees
GROUP BY department;

-- 自定义 UDAF 需要实现 AbstractGenericUDAFResolver
-- 实现复杂度远高于 UDF（需要实现 init/iterate/merge/terminate 四个阶段）

-- ============================================================
-- 4. UDTF: 表生成函数 (一行输入 → 多行输出)
-- ============================================================
-- UDTF 是 Hive 最独特的函数类型，配合 LATERAL VIEW 使用

-- explode: 展开数组为多行
SELECT id, tag FROM users
LATERAL VIEW EXPLODE(tags) t AS tag;

-- posexplode: 带位置信息的展开（0.13+）
SELECT id, pos, tag FROM users
LATERAL VIEW POSEXPLODE(tags) t AS pos, tag;

-- OUTER LATERAL VIEW: 保留空数组的行（0.12+）
SELECT id, tag FROM users
LATERAL VIEW OUTER EXPLODE(tags) t AS tag;

-- explode MAP: 展开 Map 为 key-value 行
SELECT id, key, value FROM users
LATERAL VIEW EXPLODE(properties) t AS key, value;

-- 多个 LATERAL VIEW 嵌套
SELECT id, tag, perm FROM users
LATERAL VIEW EXPLODE(tags) t1 AS tag
LATERAL VIEW EXPLODE(permissions) t2 AS perm;

-- ============================================================
-- 5. TRANSFORM: 调用外部脚本
-- ============================================================
-- Hive 允许将数据通过 stdin/stdout 传给外部脚本处理

-- Python 脚本
ADD FILE process.py;
SELECT TRANSFORM(id, username, email)
    USING 'python3 process.py'
    AS (new_id BIGINT, result STRING)
FROM users;

-- Shell 脚本
SELECT TRANSFORM(line) USING '/bin/cat' AS (output STRING) FROM raw_data;

-- 设计分析: TRANSFORM 的价值
-- TRANSFORM 允许用任意语言实现数据处理逻辑（Python/R/Shell），
-- 这比 Java UDF 的开发成本低得多。但代价是:
-- 1. 性能: 进程间通信（序列化 → stdin → 外部进程 → stdout → 反序列化）
-- 2. 可靠性: 外部脚本崩溃会导致整个 Task 失败
-- 3. 部署: 脚本需要部署到所有节点上

-- ============================================================
-- 6. Macro: 表达式别名 (Hive 0.12+)
-- ============================================================
CREATE TEMPORARY MACRO add_tax(price DOUBLE) price * 1.1;
SELECT add_tax(100.0);

CREATE TEMPORARY MACRO full_name(first STRING, last STRING) CONCAT(first, ' ', last);
SELECT full_name('Alice', 'Smith');

DROP TEMPORARY MACRO IF EXISTS add_tax;

-- Macro 本质上是文本替换，不是函数调用。
-- 适合简单的计算公式，不适合复杂逻辑。

-- ============================================================
-- 7. HPL/SQL: 过程式扩展 (Hive 2.0+)
-- ============================================================
-- HPL/SQL 提供类似 PL/SQL 的过程式能力:
-- IF/ELSE, WHILE, FOR, CURSOR, EXCEPTION
-- 运行方式: hplsql -f script.sql
-- 使用率极低，大多数团队选择 Python + Airflow

-- ============================================================
-- 8. 跨引擎对比: 可扩展性设计
-- ============================================================
-- 引擎          存储过程    UDF 语言    表生成函数(UDTF)
-- MySQL         支持(SQL)   无外部UDF   无
-- PostgreSQL    PL/pgSQL    C/Python/JS 返回 SETOF
-- Oracle        PL/SQL      Java/C      TABLE() 函数
-- Hive          不支持      Java        UDTF + LATERAL VIEW
-- Spark SQL     不支持      Scala/Java  explode + generator
-- BigQuery      不支持      JS UDF      不支持
-- Trino         不支持      Java SPI    不支持
-- Flink SQL     不支持      Java/Scala  UDTF
-- ClickHouse    不支持      C++         arrayJoin

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================
-- 1. UDF/UDAF/UDTF 三级接口是好的抽象: 覆盖了标量、聚合、展开三种场景
-- 2. TRANSFORM 是低门槛扩展的好设计: 允许用 Python 写 UDF 极大降低了学习曲线
-- 3. 存储过程不是大数据引擎的必需: Hive 证明了外部编排可以替代存储过程
-- 4. LATERAL VIEW 是 UNNEST 的 Hive 方言: SQL 标准的 UNNEST 更简洁，
--    但 LATERAL VIEW 的显式语法更清晰地表达了"展开+连接"的语义
