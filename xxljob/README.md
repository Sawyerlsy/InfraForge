-- 在B库执行
-- 1. 关闭当前会话的binlog写入（极其关键！防止DDL回传A库）
SET SESSION sql_log_bin = 0;

-- 2. 执行表结构变更
ALTER TABLE `xxl_job`.`xxl_job_log`
MODIFY COLUMN `executor_param` varchar(2500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL COMMENT '执行器任务参数',
ALGORITHM=INPLACE, LOCK=NONE;

-- 3. 恢复当前会话的binlog写入
SET SESSION sql_log_bin = 1;


必须加 SET SESSION sql_log_bin = 0;，否则 B 库的建表语句会写入自己的 binlog，再回传到 A 库，导致 A 库重复建表报错，复制中断。



-- 在B库执行
-- 先停止 SQL 线程，修改过滤规则
STOP REPLICA SQL_THREAD;

CHANGE REPLICATION FILTER REPLICATE_WILD_IGNORE_TABLE = (
'mysql.%',
'information_schema.%',
'performance_schema.%',
'sys.%',
'zabbix.%'
);

START REPLICA SQL_THREAD;

-- 在A库执行
ALTER TABLE `xxl_job`.`xxl_job_log`
MODIFY COLUMN `executor_param` varchar(2500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL COMMENT '执行器任务参数';








-- 1. 停止SQL线程（IO线程保持运行，继续拉取binlog）
STOP REPLICA SQL_THREAD;

-- 2. 动态修改过滤规则，去掉 xxl_job.xxl_job_log
CHANGE REPLICATION FILTER REPLICATE_WILD_IGNORE_TABLE = (
'mysql.%',
'information_schema.%',
'performance_schema.%',
'sys.%',
'zabbix.%'
);

-- 3. 启动SQL线程
START REPLICA SQL_THREAD;






ALTER TABLE `xxl_job`.`xxl_job_info`
MODIFY COLUMN `executor_param` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL COMMENT '执行器任务参数';

ALTER TABLE `xxl_job`.`xxl_job_log`
MODIFY COLUMN `executor_param` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL COMMENT '执行器任务参数';
