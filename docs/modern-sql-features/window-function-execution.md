# 窗口函数执行模型

窗口函数是 SQL 中实现复杂度最高的查询特性之一。它的执行涉及排序、分区扫描和帧计算三个阶段，每个阶段都有深刻的优化空间。

## 三阶段模型

```
窗口函数的执行分为三个阶段:

1. 排序 (Sort):
   按 PARTITION BY + ORDER BY 排序全量数据
   这是最昂贵的阶段

2. 分区扫描 (Partition Scan):
   按 PARTITION BY 的边界切分数据
   识别每个分区的开始和结束位置

3. 帧计算 (Frame Evaluation):
   在每行的窗口帧 (ROWS/RANGE/GROUPS) 内计算聚合
   这是最复杂的阶段

示例:
  SUM(amount) OVER (PARTITION BY dept ORDER BY hire_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)

  阶段 1: 按 (dept, hire_date) 排序
  阶段 2: 识别每个 dept 的分区边界
  阶段 3: 对每行, 计算前 2 行 + 当前行的 SUM(amount)
```

## 排序阶段的优化

### 共享排序 (Shared Sort)

```sql
-- 查询包含多个窗口函数时, 如果排序键兼容, 可以共享排序

-- 场景: 两个窗口函数的排序键相同
SELECT
    ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC),
    SUM(salary) OVER (PARTITION BY dept ORDER BY salary DESC),
    AVG(salary) OVER (PARTITION BY dept ORDER BY salary DESC)
FROM employees;

-- 优化: 只需一次排序 (dept, salary DESC)
-- 三个窗口函数共用同一个排序结果

-- 排序兼容的条件:
-- PARTITION BY 列相同
-- ORDER BY 列相同 (包括方向)
-- 或一个是另一个的前缀

-- 不兼容的例子:
SELECT
    ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC),
    RANK() OVER (PARTITION BY dept ORDER BY hire_date ASC)
FROM employees;

-- 需要两次排序:
-- 排序 1: (dept, salary DESC) -> ROW_NUMBER
-- 排序 2: (dept, hire_date ASC) -> RANK
```

### 排序分组策略

```
当查询包含多个不同排序键的窗口函数时:

策略 1: 贪心分组
  将窗口函数按排序键分组
  尽量让同一组的窗口函数共享排序

策略 2: 最优分组 (NP-hard)
  考虑排序键之间的兼容关系 (前缀关系)
  找到需要最少排序次数的分组方案

实际实现:
  PostgreSQL: 贪心分组, 按 PARTITION BY + ORDER BY 分组
  MySQL 8.0: 类似, 尝试合并兼容的排序键

示例:
  W1: PARTITION BY a ORDER BY b
  W2: PARTITION BY a ORDER BY b, c
  W3: PARTITION BY a ORDER BY d

  最优分组:
  组 1: W2 (排序 a, b, c), W1 (排序 a, b, 是 W2 的前缀, 可以共用)
  组 2: W3 (排序 a, d)

  总排序次数: 2 (而非 3)
```

### 索引消除排序

```sql
-- 如果数据已按需要的顺序存储, 可以跳过排序

-- PostgreSQL: 利用索引提供有序数据
CREATE INDEX idx_dept_salary ON employees(dept, salary DESC);

SELECT ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC)
FROM employees;

-- 执行计划:
-- WindowAgg
--   -> Index Scan using idx_dept_salary
-- 无需 Sort 节点! 索引已提供有序数据

-- MySQL 8.0: 类似优化
-- 如果索引顺序与窗口函数的排序需求一致, 跳过排序

-- 条件:
-- 索引列 = PARTITION BY 列 + ORDER BY 列
-- 索引方向 = ORDER BY 方向
-- 索引覆盖查询所需的所有列 (Index-Only Scan 更优)
```

## 帧计算策略

### 全量计算 vs 增量计算

```
帧类型决定了计算策略:

1. 无帧 / 整个分区:
   SUM(salary) OVER (PARTITION BY dept)
   每个分区计算一次 SUM, 所有行共享结果
   复杂度: O(N)

2. Unbounded 到 Current Row:
   SUM(salary) OVER (PARTITION BY dept ORDER BY hire_date
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
   累积和: 每行的结果 = 上一行的结果 + 当前行
   增量计算: O(1) per row
   总复杂度: O(N)

3. 固定大小的滑动窗口:
   SUM(salary) OVER (PARTITION BY dept ORDER BY hire_date
                      ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING)

   全量计算: 每行重新计算帧内所有值
   复杂度: O(N * W), W = 窗口大小

   增量计算 (滑动窗口):
   当窗口滑动一行时:
     result = prev_result + new_entering_row - old_leaving_row
   复杂度: O(1) per row, 总 O(N)

   要求: 聚合函数可逆 (SUM 可逆, MAX 不可逆!)
```

### 可逆 vs 不可逆聚合

```
可逆聚合 (支持增量更新):
  SUM: 新值 = 旧值 + entering - leaving
  COUNT: 新值 = 旧值 + 1 - 1
  AVG: 通过 SUM 和 COUNT 间接增量

不可逆聚合 (不能简单增量):
  MIN: 如果离开的行是最小值, 需要重新扫描整个帧
  MAX: 同上
  MEDIAN: 不支持增量

不可逆聚合的优化:
  方案 1: 全量重算 -> O(W) per row
  方案 2: 使用有序数据结构 -> O(log W) per row
  方案 3: Segment Tree -> O(log N) per row (预处理 O(N log N))
```

### Segment Tree 优化

```
对于 MIN/MAX 等不可逆聚合的滑动窗口:

Segment Tree (线段树):
  预处理: 构建线段树, O(N log N)
  查询: 任意区间的 MIN/MAX, O(log N) per query

适用场景:
  ROWS BETWEEN k PRECEDING AND k FOLLOWING
  其中 k 不是常量 (每行的帧可能不同大小)

单调队列 (Deque) 优化 (更优):
  对于固定大小的滑动窗口:
  维护一个单调递减的双端队列
  每行: 入队 O(1) 摊销, 出队 O(1)
  总复杂度: O(N)

PostgreSQL 的实现:
  对于可逆聚合: 增量更新
  对于 MIN/MAX: 全量重算 (没有使用 Segment Tree)

Spark SQL:
  滑动窗口默认全量重算
  可以通过 Tungsten 的列式内存格式加速
```

## ROWS vs RANGE vs GROUPS

### 语义差异

```sql
-- 示例数据:
-- dept | salary | name
-- A    | 100    | Alice
-- A    | 100    | Bob
-- A    | 200    | Carol
-- A    | 300    | Dave

-- ROWS: 基于物理行位置
SUM(salary) OVER (ORDER BY salary ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
-- Alice: 100            (只有自己)
-- Bob:   100 + 100 = 200 (Alice + Bob)
-- Carol: 100 + 200 = 300 (Bob + Carol)
-- Dave:  200 + 300 = 500 (Carol + Dave)

-- RANGE: 基于值的范围 (相同值的行是一个"范围")
SUM(salary) OVER (ORDER BY salary RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
-- Alice: 100 + 100 = 200 (所有 salary=100 的行)
-- Bob:   100 + 100 = 200 (所有 salary=100 的行, 与 Alice 相同!)
-- Carol: 100 + 100 + 200 = 400
-- Dave:  100 + 100 + 200 + 300 = 700

-- GROUPS (SQL:2011): 基于 peer group (值相同的行组)
SUM(salary) OVER (ORDER BY salary GROUPS BETWEEN 1 PRECEDING AND CURRENT ROW)
-- Alice: group{100,100}                = 200  (当前组)
-- Bob:   group{100,100}                = 200  (当前组)
-- Carol: group{100,100} + group{200}   = 400  (前一组 + 当前组)
-- Dave:  group{200} + group{300}       = 500  (前一组 + 当前组)
```

### 实现差异

```
ROWS 实现:
  最简单: 按物理位置计数
  帧边界: 当前行 ± N 行
  复杂度: O(1) 定位帧边界

RANGE 实现:
  按值范围确定帧边界
  帧边界: 当前值 ± delta
  需要考虑相同值的行 (peer group)
  复杂度: 需要在排序数据中二分查找边界, O(log N)

  特殊: RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW (默认帧)
  相同值的行得到相同的结果 (与 ROWS 不同!)

GROUPS 实现:
  按 peer group 计数
  帧边界: 当前组 ± N 组
  需要预先识别所有 peer group 的边界
  复杂度: O(G) 预处理, G = group 数; O(1) 定位帧边界

支持情况:
  ROWS:   所有引擎都支持
  RANGE:  大部分引擎支持, 但 RANGE N PRECEDING/FOLLOWING 支持有限
  GROUPS: PostgreSQL 11+, SQLite 3.28+, 其他引擎很少支持
```

## RANGE 帧的数值和时间间隔

```sql
-- RANGE 帧可以指定数值偏移

-- 数值 RANGE:
SELECT SUM(amount) OVER (
    ORDER BY price
    RANGE BETWEEN 10 PRECEDING AND 10 FOLLOWING
)
FROM orders;
-- 帧: 价格在 [current_price - 10, current_price + 10] 范围内的所有行

-- 时间 RANGE (PostgreSQL):
SELECT SUM(amount) OVER (
    ORDER BY order_date
    RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
)
FROM orders;
-- 帧: order_date 在 [current_date - 7 days, current_date] 范围内的行

-- 支持情况:
-- PostgreSQL: 完整支持 RANGE + 数值/时间间隔
-- MySQL 8.0: 支持 RANGE + 数值, 不支持 INTERVAL
-- SQL Server: 支持 RANGE UNBOUNDED/CURRENT ROW, 不支持 N PRECEDING/FOLLOWING
-- BigQuery: 支持 RANGE + 数值
-- Oracle: 完整支持 RANGE + 数值/时间间隔
```

## 内存管理

### Spill to Disk (溢出到磁盘)

```
窗口函数的内存需求:

1. 排序: O(N) 内存 (或外部排序)
2. 分区缓冲: 至少一个分区的数据
3. 帧计算: 取决于帧大小

内存不足时的策略:

排序阶段:
  使用外部排序 (External Merge Sort)
  将数据分成多个 run, 分别排序后归并
  PostgreSQL: work_mem 控制排序内存
  MySQL: sort_buffer_size 控制

分区阶段:
  如果一个分区超过内存:
  方案 A: 溢出到临时文件, 按需回读
  方案 B: 流式处理 (对于不需要回溯的帧类型)

帧计算:
  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW:
    流式处理, O(1) 内存 (只保留累积值)
  ROWS BETWEEN N PRECEDING AND N FOLLOWING:
    O(N) 内存 (只保留帧内的行)
  ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING:
    O(partition_size) 内存 (需要整个分区)
```

### 各引擎的内存控制

```sql
-- PostgreSQL:
SET work_mem = '256MB';  -- 排序和哈希操作的内存限制

-- MySQL:
SET sort_buffer_size = 262144;       -- 排序缓冲
SET window_functions_use_tmp_table = ON;  -- 使用临时表

-- Spark SQL:
SET spark.sql.windowExec.buffer.spill.threshold = 4096;
-- 超过阈值时溢出到磁盘

-- Oracle:
-- PGA_AGGREGATE_TARGET 控制排序内存
-- 超过限制时使用临时表空间 (TEMP tablespace)

-- ClickHouse:
SET max_bytes_before_external_sort = 1073741824;  -- 1GB
-- 超过限制时使用外部排序
```

## 并行执行

### 按 PARTITION BY 并行

```
窗口函数天然适合按分区并行:

1. 按 PARTITION BY 列做数据分发:
   线程 1: dept = 'Engineering'
   线程 2: dept = 'Sales'
   线程 3: dept = 'Marketing'

2. 每个线程独立执行:
   - 排序本分区数据
   - 计算窗口函数
   - 输出结果

3. 汇总所有线程的结果

优化:
  如果数据已按 PARTITION BY 分区 (如 hash 分区表):
  每个线程处理本地分区, 无需数据重分布
  类似 Colocated JOIN 的思路
```

### 无 PARTITION BY 时的并行化

```
如果没有 PARTITION BY, 整个表是一个分区:

SELECT ROW_NUMBER() OVER (ORDER BY salary DESC)
FROM employees;

方案 1: 串行 (最简单)
  无法并行, 因为只有一个分区

方案 2: 分段并行 (适合部分函数)
  1. 将数据分成 N 段, 每段独立排序
  2. 归并排序
  3. 顺序分配 ROW_NUMBER

方案 3: 流水线并行
  排序阶段并行 -> 帧计算阶段串行
  利用排序的并行性

实际情况:
  大部分引擎在无 PARTITION BY 时使用串行
  Spark: 所有数据 shuffle 到一个分区 (性能瓶颈!)
  建议: 避免无 PARTITION BY 的窗口函数在大数据量上使用
```

## 特殊窗口函数的实现

### ROW_NUMBER / RANK / DENSE_RANK

```
这三个函数不需要帧, 只需要排序:

ROW_NUMBER: 单调递增计数器
  每行 +1, 无论值是否相同
  实现: 一个简单的计数器

RANK: 跳跃排名
  相同值的行排名相同, 下一个不同值的排名 = 已处理行数 + 1
  实现: 比较当前行与前一行, 相同则排名不变

DENSE_RANK: 不跳跃排名
  相同值的行排名相同, 下一个不同值的排名 = 当前排名 + 1
  实现: 比较当前行与前一行, 不同则排名 + 1

三者都不需要帧计算, 是最高效的窗口函数。
复杂度: 排序 O(N log N) + 扫描 O(N)
```

### LEAD / LAG

```
LEAD(col, N): 当前行之后第 N 行的值
LAG(col, N): 当前行之前第 N 行的值

实现:
  排序后, 维护一个大小为 N+1 的缓冲区
  LEAD: 读取缓冲区中位置 +N 的值
  LAG: 读取缓冲区中位置 -N 的值

边界处理:
  超出分区边界: 返回默认值 (第三个参数) 或 NULL

优化:
  如果 N 是常量 (通常如此), 缓冲区大小固定
  不需要帧计算, 复杂度 O(N)
```

### NTILE

```sql
-- NTILE(N): 将分区分成 N 个大致相等的组
NTILE(4) OVER (ORDER BY salary)
-- 100 行 -> 每组 25 行: 组 1,1,1,...,2,2,2,...,3,3,3,...,4,4,4,...

-- 实现:
-- 1. 计算分区总行数 (需要先扫描一遍或使用统计信息)
-- 2. 每组行数 = total / N, 余数 R = total % N
-- 3. 前 R 组有 (total/N + 1) 行, 后 (N-R) 组有 (total/N) 行

-- 挑战: 需要知道分区总行数
-- 方案 A: 两遍扫描 (第一遍计数, 第二遍分配)
-- 方案 B: 物化分区到内存, 一遍处理
```

## 对引擎开发者的实现建议

### 窗口函数执行器的架构

```
建议的模块化架构:

WindowOperator
├── SortPhase
│   ├── 检查输入是否已排序 (索引 / 下游排序)
│   ├── 排序分组 (合并兼容的窗口函数)
│   └── 外部排序支持 (Spill to Disk)
├── PartitionScanner
│   ├── 分区边界检测 (PARTITION BY 列值变化)
│   └── 分区物化 / 流式处理选择
├── FrameEvaluator
│   ├── RowsFrameEvaluator (物理行帧)
│   ├── RangeFrameEvaluator (值范围帧)
│   └── GroupsFrameEvaluator (分组帧)
└── WindowFunction
    ├── RankingFunction (ROW_NUMBER, RANK, DENSE_RANK)
    ├── LeadLagFunction (LEAD, LAG)
    ├── NtileFunction (NTILE)
    ├── AggregateFunction (SUM, AVG, MIN, MAX, COUNT)
    └── CustomFunction (用户自定义窗口函数)
```

### 关键实现决策

```
1. 是否支持 GROUPS 帧?
   - PostgreSQL 11+ 和 SQLite 支持
   - 实现难度中等, 但使用场景较少
   - 建议: 优先实现 ROWS 和 RANGE, GROUPS 后续添加

2. 增量计算的支持范围?
   - SUM/COUNT/AVG: 必须支持增量
   - MIN/MAX: 全量重算或单调队列
   - 用户自定义聚合: 提供可选的 remove() 接口

3. Spill to Disk?
   - 排序阶段: 必须支持 (外部排序)
   - 帧计算阶段: 可选, 取决于目标场景
   - 分析型引擎: 必须支持 (处理 TB 级数据)
   - OLTP 引擎: 可以限制帧大小, 超过报错

4. 并行度?
   - PARTITION BY 并行: 强烈推荐
   - 无 PARTITION BY: 串行可接受
   - 分布式: 按 PARTITION BY 做 Shuffle
```

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2:2003 Section 7.11 "window function"
- PostgreSQL: [Window Functions Implementation](https://www.postgresql.org/docs/current/xfunc-sql.html#XFUNC-SQL-WINDOW-FUNCTIONS)
- Leis et al.: "Efficient Processing of Window Functions in Analytical SQL Queries" (VLDB 2015)
- Cao et al.: "Optimization of Analytic Window Functions" (VLDB 2012)
- MySQL: [Window Function Optimization](https://dev.mysql.com/doc/refman/8.0/en/window-function-optimization.html)
