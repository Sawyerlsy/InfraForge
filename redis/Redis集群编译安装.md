## Redis集群部署
### 1、编译安装
```shell
# 解压及编译安装
tar xzf redis-6.2.19.tar.gz
cd redis-6.2.19
make BUILD_TLS=yes && sudo make install PREFIX=/usr/local/redis
sudo ln -s /usr/local/redis/bin/* /usr/local/bin/
```

### 2、创建目录
```shell
# 创建目录
mkdir -p /data/redis/{7001,7002,7003}/{data,logs,pid,conf}
```
### 3、修改配置
```shell
vim /data/redis/redis_template.conf
```
```properties
# 网络与安全
bind 0.0.0.0                      # 监听所有IP
protected-mode no                 # 允许外部访问
port {port}                         # 实例端口
requirepass hgrica1@    # 集群访问密码
masterauth hgrica1@     # 主从同步密码（与requirepass一致）
tcp-backlog 10240  # 高并发连接队列,需与内核参数net.core.somaxconn=10240匹配，避免连接丢弃

# 集群核心配置
cluster-enabled yes               # 启用集群模式
cluster-config-file nodes-{port}.conf # 自动生成的集群元数据文件
cluster-node-timeout 15000        # 节点失联超时（毫秒）
cluster-replica-validity-factor 10 # 从节点有效性验证
min-replicas-to-write 1           # 防脑裂：至少1个从节点同步才允许写入[4](@ref)

# 持久化与内存
dir /data/redis/{port}/data         # 数据存储路径
appendonly yes                    # 启用AOF持久化
appendfsync everysec              # 平衡性能与数据安全
maxmemory 16gb                    # 建议不超过物理内存70%
maxmemory-policy volatile-lru     # 内存淘汰策略
aof-use-rdb-preamble yes          # 开启混合持久化（核心配置）

# 配置AOF重写规则（防文件膨胀）
auto-aof-rewrite-percentage 100  # 文件增长100%触发重写
auto-aof-rewrite-min-size 64mb   # 最小64MB才触发重写

# 可选：RDB策略（补充备份）
save 3600 1     # 1小时至少1次修改备份

# 日志与进程
daemonize yes
pidfile /data/redis/{port}/pid/redis.pid
logfile /data/redis/{port}/logs/redis.log
```

### 4、生成其他节点配置
```shell
# 批量生成7002/7003配置
for port in 7001 7002 7003; do
  cp -r /data/redis/redis_template.conf /data/redis/$port/conf/redis.conf
  sed -i -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' -e '/^$/d' /data/redis/$port/conf/redis.conf
  sed -i "s/{port}/$port/g" /data/redis/$port/conf/redis.conf
done
```

```shell
# 创建专有用户
useradd -M -s /sbin/nologin redis
chown -R redis:redis /data/redis
```

### 5、启动节点
```shell
# 每台服务器启动3个实例
redis-server /data/redis/7001/conf/redis.conf \
&& redis-server /data/redis/7002/conf/redis.conf \
&& redis-server /data/redis/7003/conf/redis.conf

# 验证进程
ps -ef | grep redis-server  # 应显示3个进程
```

### 6、创建集群
```shell
redis-cli -a hgrica1@ --cluster create \
  192.168.1.101:7001 \
  192.168.1.102:7004 \
  192.168.1.103:7007 \
  192.168.1.101:7002 \
  192.168.1.101:7003 \
  192.168.1.102:7005 \
  192.168.1.102:7006 \
  192.168.1.103:7008 \
  192.168.1.103:7009 \
  --cluster-replicas 2
  
# 前 N 个节点作为主节点，后续节点按顺序作为从节点分配给主节点
# 192.168.1.101:7002 和 192.168.1.101:7003 → 作为192.168.1.101:7001的从节点
# 192.168.1.102:7005 和 192.168.1.102:7006 → 作为192.168.1.102:7004的从节点
# 192.168.1.103:7008 和 192.168.1.103:7009 → 作为192.168.1.103:7007的从节点
```

### 7、集群验证与高可用测试
#### 7.1、基础验证
```shell
# 检查集群状态
redis-cli -a hgrica1@ -c -h 192.168.1.101 -p 7001 cluster info
# 输出应包含：cluster_state:ok 和 cluster_slots_assigned:16384
```
```shell
# 查看节点拓扑
redis-cli -a hgrica1@ -c -h 192.168.1.101 -p 7001 cluster nodes
# 确认每个主节点有2个从节点，且分布在其他物理机
```
```shell
# 关闭redis
redis-cli -a hgrica1@ -p 7001 shutdown
```

##### 7.2、故障转移测试
```shell
# 模拟主节点宕机（如192.168.1.101:7001）
redis-cli -a hgrica1 -h 192.168.1.101 -p 7001 DEBUG SEGFAULT

# 观察故障转移（约15秒后）
watch -n 1 'redis-cli -a hgrica1@ cluster nodes | grep master'
# 原从节点（如7002）应升主，且集群状态恢复OK
```
##### 7.3、数据稳定性测试
```shell
# 跨节点写入读取
redis-cli -a hgrica1@ -c -h 192.168.1.101 -p 7001 set foo "cluster_test"
redis-cli -a hgrica1 -c -h 192.168.1.102 -p 7004 get foo  # 应返回"cluster_test"
```


### 8、创建服务
##### 8.1、创建服务文件（以7001为例）
```shell
vi /data/redis/redis_template.service

[Unit]
Description=Redis Cluster Node {port}
After=network.target

[Service]
Type=forking
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /data/redis/{port}/conf/redis.conf
ExecStop=/usr/local/bin/redis-cli -a hgrica1@ -p {port} shutdown
Restart=always
RestartSec=3
WorkingDirectory=/data/redis/{port}/data

[Install]
WantedBy=multi-user.target
```

##### 8.2、启动服务
```shell
# 批量配置
for port in 7001 7002 7003; do
  cp /data/redis/redis_template.service /etc/systemd/system/redis-$port.service
  sed -i "s/{port}/$port/g" /etc/systemd/system/redis-$port.service
  systemctl daemon-reload
  systemctl enable redis-$port
  systemctl start redis-$port
done
```

### 9、常用操作和处理
##### 9.1、添加主节点
```shell
# 添加新节点到集群,默认添加的是主节点（无槽位）
redis-cli -a hgrica1@ --cluster add-node NEW_HOST:NEW_PORT EXISTING_HOST:EXISTING_PORT


# 添加主节点后，由于其初始状态下不包含任何哈希槽，需要手动或通过平衡操作为其分配槽位，它才能真正存储数据 
# 方式1：使用 reshard命令可以重新分配槽位，这是一个交互式过程 
# 执行后会依次询问：
# 要移动多少个槽位（How many slots do you want to move）：根据需求输入数量。
# 接收这些槽位的目标节点ID（What is the receiving node ID）：输入新主节点的ID。
# 从哪些节点转移出这些槽位（Please enter all the source node IDs）：可以输入 all表示从所有现有主节点平均抽取，或输入特定源节点的ID，然后输入 done结束。
# 确认迁移计划（Do you want to proceed with the proposed reshard plan）：输入 yes开始迁移 
redis-cli -a yourpassword --cluster reshard 192.168.1.102:7004

# 方式2：使用 rebalance 自动平衡集群各节点的槽位数量,可指定权重、阈值等 （灵活性低、由集群自动处理，可能导致变动范围过大,不推荐）
# redis-cli --cluster rebalance HOST:PORT
```

##### 9.2、添加从节点
```shell
# EXISTING_HOST:EXISTING_PORT是集群发现的入口
# master-id是cluster nodes中的主节点ID
redis-cli -a hgrica1@ --cluster add-node NEW_HOST:NEW_PORT EXISTING_HOST:EXISTING_PORT --cluster-slave --cluster-master-id <master-id>

# 命令执行成功后会输出：New node added correctly
```

##### 9.3、让指定从节点成为主节点（手动故障转移）
在从节点上执行 *CLUSTER FAILOVER* 命令会发起一次有序的主从切换，原主节点会将其数据同步到该从节点，确保数据安全后再完成角色切换。这是最安全的手动提升方式
在从节点上执行 *CLUSTER FAILOVER* 时，流程如下:
- step1: 执行 *CLUSTER FAILOVER* 命令
- step2: 向集群请求主节点暂停写入
- step3: 等待数据同步完成
- step4: 数据同步异常（包括磁盘空间不足、网络异常、从节点宕机等）时，主节点检测到同步失败或者等待超时，主节点会恢复写入，故障转移失败，集群恢复正常;
- step5: 数据同步成功后, 从节点发起选举，赢得集群中多数节点的投票后升级为主节点，原主节点成为新主节点的从节点，完成角色切换
- step6: 新主节点恢复写入，故障转移完成
```shell
# redis-cli -a hgrica1@ -h 10.194.68.225 -p 7008 cluster failover
# 1. 连接到要提升的从节点
redis-cli -a hgrica1@ -h 192.168.1.101 -p 7002

# 2.1 使用标准模式执行手动故障转移，安全的主从切换，零数据丢失
CLUSTER FAILOVER

# 2.2 使用强制模式执行手动故障转移，主节点宕机时快速选主，跳过偏移量检查，依赖固有同步，数据可能丢失
CLUSTER FAILOVER FORCE

# 2.3 使用强制模式执行手动故障转移，不检查数据，直接抢占主节点，数据可能丢失
CLUSTER FAILOVER TAKEOVER

# 3. 验证节点角色变更
CLUSTER NODES
```

```text
注意: 手动故障转移的选举是由操作人主动执行命令发起，而自动故障转移是当主节点被标记为客观下线后，由其从节点自动触发的。
但不管是哪种情况，都需要集群中多数持有哈希槽的主节点投票同意（超过存活主节点总数的二分之一即N/2 + 1）才会成功。
如果主节点全都宕机或者大部分都宕机，则无法完成故障转移。
```
##### 9.4、删除从节点
从节点没有槽位，直接删除即可
```shell
# redis-cli --cluster del-node <existing-host>:<existing-port> <node-id-of-slave-to-remove>
redis-cli -a hgrica1@ --cluster del-node 192.168.1.102:7004 9d529208e373ed9b6986005e3e62875e4c039abc
```

##### 9.5、删除主节点
删除主节点：必须先将该主节点上所有的哈希槽迁移到其他主节点上，否则删除操作会失败
- 使用 reshard 命令将待删除主节点的所有槽位迁移至其他主节点。
- 确认待删除主节点不再包含任何槽位后，再执行 del-node命令

步骤1：检查当前集群状态
```shell
# 查看当前节点和槽位分布
redis-cli -a hgrica1@ -h 192.168.1.102 -p 7004 CLUSTER NODES

# 检查集群状态
redis-cli -a hgrica1@ --cluster check 192.168.1.102:7004
```

步骤2：将要删除的主节点槽位迁移到其他主节点
假设要删除 192.168.1.101:7001，将其槽位迁移到 192.168.1.102:7004 和 192.168.1.103:7007：
```shell
# 执行reshard操作
redis-cli -a hgrica1@ --cluster reshard 192.168.1.102:7004

# 交互过程示例：
# 1. 输入要移动的槽位数量（如要删除节点有5000个槽位）
How many slots do you want to move (from 1 to 16384)? 5000

# 2. 输入接收槽位的目标节点ID（第一个目标节点）
What is the receiving node ID? <node_id_of_192.168.1.102:7004>

# 3. 输入源节点ID（要删除的节点）
Please enter all the source node IDs.
  Type 'all' to use all the nodes as source nodes for the hash slots.
  Type 'done' once you entered all the source nodes IDs.
Source node #1: <node_id_of_192.168.1.101:7001>
Source node #2: done

# 重复上述过程，将剩余槽位迁移到另一个目标节点
```

步骤3：验证槽位迁移完成
```shell
# 检查要删除的节点是否还有槽位
redis-cli -a hgrica1@ -h 192.168.1.101 -p 7001 CLUSTER NODES | grep "192.168.1.101:7001"

# 预期输出：该节点应该显示没有槽位或者只有极少数槽位
# 例如：<node_id> 192.168.1.101:7001@17001 slave - 0 1234567890000 0 connected
```

步骤4：删除空主节点
```shell
# 确认节点没有槽位后删除
redis-cli -a hgrica1@ --cluster del-node 192.168.1.102:7004 <node_id_of_192.168.1.101:7001>

# 验证节点已删除
redis-cli -a hgrica1@ --cluster check 192.168.1.102:7004
```


##### 9.6、检查集群状态
***check***命令可以对集群进行全面的健康检查，包括节点数量、角色、槽位分布、槽位状态等
```shell
# 确保每个主节点有足够的从节点
redis-cli -a hgrica1@ --cluster check 192.168.1.102:7004

# 预期输出应该显示：
# [OK] All nodes agree about slots configuration.
# >>> Check for open slots...
# >>> Check slots coverage...
# [OK] All 16384 slots covered.
```


##### 9.7、验证数据是否同步完成
从节点升级为主节点时，同步过程中或结束后可以验证数据是否同步完成

> 关键指标： 
> - master_repl_offset == slave_repl_offset （理论上不可能完全一致,只要不持续增长，小于100kb即可）
> - lag = 0（延迟秒数，0表示无延迟, 小于等于1都是正常的） 
> - master_link_status: up

- 检查复制偏移量
```shell
# 在主节点上检查
redis-cli -a hgrica1@ -h 192.168.1.102 -p 7004 INFO replication
# 关注：
# master_repl_offset:xxxxxx
# slaveX:ip=192.168.1.101,port=7002,offset=xxxxxx,lag=0

# 在从节点上检查
redis-cli -a hgrica1@ -h 192.168.1.101 -p 7002 INFO replication
# 关注：
# master_repl_offset:xxxxxx
# slave_repl_offset:xxxxxx
```
- 实时监控同步进度
```shell
# 持续监控复制状态
watch -n 0.5 "redis-cli -a hgrica1@ -h 192.168.1.101 -p 7002 INFO replication | grep -E '(offset|lag|status)'"

# 输出示例：
# master_repl_offset:12567890
# slave_repl_offset:12567890
# master_last_io_seconds_ago:1
# slave_lag:0
```

##### 9.8 修复开放槽位问题
如果集群的16384个哈希槽中，有部分槽位没有被任何主节点负责，那么就会出现开放槽位问题。
这个可能的原因如下:
- 主节点故障且无可用从节点
```text
# 场景: 主节点宕机，且没有从节点或从节点也故障
M: node1 [fail] slots: 0-5000 [OPEN]
S: node2 [fail]  # 从节点也故障
# 结果: 槽位0-5000变成开放槽位
```
- 故障转移失败
```text
# 场景: 主节点下线，但从节点选举失败
M: node1 [fail] slots: 5000-10000
S: node2 [slave]  # 由于网络分区无法选举
S: node3 [slave]  # 数据太旧不符合升级条件
# 结果: 槽位5000-10000无人负责
```
- 集群重新分片中断
```text
# 场景: 数据迁移过程中操作被中断
>>> Migrating slot 1234 from nodeA to nodeB
[INTERRUPTED]  # 迁移过程被强制终止
# 结果: 槽位1234处于"迁移中"状态，既不在A也不在B
```
- 节点移除操作不当
```text
# 场景: 移除主节点前未重新分配其槽位
redis-cli --cluster del-node 10.0.0.1:7001 <node-id>
# 警告: 节点负责的槽位将变成开放槽位
```

- 手动配置错误
```text
# 场景: 手动执行CLUSTER SETSLOT错误
CLUSTER SETSLOT 1000 NODE <wrong-node-id>
# 结果: 槽位1000指向不存在的节点
```

- 网络分区导致脑裂
```text
# 场景: 网络分区，部分节点无法通信
节点组A: 认为节点组B已下线，选举新主节点
节点组B: 认为自己正常，继续服务
# 结果: 部分槽位在不同分区中有不同主节点，恢复后产生冲突
```

类似的错误信息如下:
> Check for open slots...  
> [WARNING] The following slots are open: 1000, 1001, 1002  
> [ERROR] Not all 16384 slots are covered by nodes.  

修复方法如下：
- 方法1：使用 --cluster fix 自动修复
```shell
# 自动检测并修复开放槽位
redis-cli -a hgrica1@ --cluster fix 10.194.68.223:7001

# 修复过程:
# 1. 扫描所有开放槽位
# 2. 将开放槽位分配给健康的主节点
# 3. 重新平衡集群状态
```

- 方法2：使用 --cluster reshard 手动重新分片
```shell
# 手动重新分配槽位
redis-cli -a hgrica1@ --cluster reshard 10.194.68.223:7001

# 交互式操作:
How many slots do you want to move? 5462           # 输入要移动的槽位数
What is the receiving node ID? dbde59ee...         # 输入目标节点ID
Please enter all the source node IDs.
  Type 'all' to use all the nodes as source nodes.
  Type 'done' once you entered all the source nodes.
Source node #1: all                                # 从所有节点抽取槽位
```

- 方法3：手动分配特定槽位
```shell
# 针对特定开放槽位进行分配
# 步骤1: 连接到目标主节点
redis-cli -a hgrica1@ -h 10.194.68.223 -p 7001

# 步骤2: 手动添加槽位 (假设槽位1000-2000开放)
10.194.68.223:7001> CLUSTER ADDSLOTS 1000 1001 1002 ... 2000

# 或者使用脚本批量操作
for slot in {1000..2000}; do
  redis-cli -a hgrica1@ -h 10.194.68.223 -p 7001 CLUSTER ADDSLOTS $slot
done
```

- 方法4：从备份恢复
```shell
# 如果数据丢失严重，从备份恢复
# 步骤1: 停止所有Redis实例
redis-cli -a hgrica1@ -h 10.194.68.223 -p 7001 SHUTDOWN

# 步骤2: 恢复RDB/AOF备份文件
cp /backup/dump.rdb /data/redis/dump.rdb

# 步骤3: 重启集群并修复拓扑
redis-cli -a hgrica1@ --cluster fix 10.194.68.223:7001
```
##### 9.8、计算健属于哪个槽
```shell
redis-cli -a hgrica1@ CLUSTER KEYSLOT <key_name>
```

##### 9.9、批量执行命令
redis-cli --cluster call会向集群中每个在线节点发送指定的命令，并返回执行结果  
使用 --cluster-only-masters或 --cluster-only-replicas参数，可以指定命令仅在所有主节点或所有从节点上执行
```shell
# 批量配置管理
redis-cli --cluster call <host:port> CONFIG SET timeout 300

# 批量信息收集与监控
redis-cli --cluster call <host:port> INFO MEMORY

# 批量数据清理
redis-cli --cluster call <host:port> FLUSHALL

# 批量状态检查
redis-cli --cluster call <host:port> DBSIZE
```

预期的结果如下:
```text
/data # redis-cli -a hgrica1@ --cluster call 10.194.68.225:7008 CLUSTER FORGET 9d529208e373ed9b6986005e3e62875e4c039abc
Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
>>> Calling CLUSTER FORGET 9d529208e373ed9b6986005e3e62875e4c039abc
10.194.68.225:7008: ERR Unknown node 9d529208e373ed9b6986005e3e62875e4c039abc

10.194.68.223:7002: OK
10.194.68.224:7006: OK
10.194.68.224:7005: OK
10.194.68.223:7001: OK
10.194.68.224:7004: OK
10.194.68.225:7009: ERR Unknown node 9d529208e373ed9b6986005e3e62875e4c039abc

10.194.68.225:7007: ERR Unknown node 9d529208e373ed9b6986005e3e62875e4c039abc

10.194.68.223:7003: OK
```
> ##### 返回 OK 的节点：已经处理成功，代表目标节点已经忘记了该节点。
> ##### 返回 ERR Unknown node 的节点：代表目标节点不认识该节点,无需处理


##### 9.10、修复集群信息不一致
如果cluster nodes能够显示7003节点,但是check命令不显示，并且使用forget命令无法遗忘7003节点，此时可以考虑使用使用CLUSTER RESET HARD重置节点的集群信息。

作用： 重置单个节点的集群状态

- 清空该节点的所有集群信息（节点表、槽位分配等）

- 重置节点ID（生成新的随机ID）

- 将节点设置为独立模式（不再是集群的一部分）

- 不影响集群中的其他节点

使用场景：
- 节点配置错误需要重新加入集群
- 节点数据损坏需要重新初始化
- 节点被意外移除后需要重新加入
- 节点层面的故障恢复

```shell
# 1. 在7003节点上重置集群状态
# 会清除节点的集群信息，如果节点是主节点且持有数据，需要先使用FLUSHALL等命令清空数据，否则重置可能不成功
# 这个命令通常不应该在一个正常运行的集群中对一个健康的节点直接使用
redis-cli -a hgrica1@ -h 10.194.68.223 -p 7003 CLUSTER RESET HARD

# 2. 将7003重新加入集群
redis-cli -a hgrica1@ --cluster add-node 10.194.68.223:7003 10.194.68.224:7004 --cluster-slave --cluster-master-id dbde59ee6d2723f9404154328a7929010a7e678a

# 3. 检查集群节点信息是否同步
redis-cli -a hgrica1@ -h 10.194.68.224 -p 7004 CLUSTER NODES | grep 7003
```


### 10、注意事项
#### 10.1、reids节点宕机处理
```text
（1）检查集群状态：cluster nodes和使用--cluster check
（2）宕机节点上能够重新启动,redis实例可以正常启动：
    a. 集群状态正常且主从节点分布合理,则无需处理
    b. 集群状态异常或者主从节点分布不合理,则需要手动修复集群状态
（3）宕机节点无法重新启动,redis实例无法恢复：
    a. 重新安装redis实例
    b. 从集群中移除对应的fail节点
    c. 将新的节点加入集群
```
> 注意：在redis集群中优先使用del node命令删除节点,如果del node失败再考虑CLUSTER FORGET命令。
> CLUSTER FORGET命令是节点级别的，需要在每个节点中执行。并且CLUSTER FORGET有60秒遗忘保护期，对同一个节点ID执行后，60秒内不能再次执行
- 方式一：使用批处理命令执行CLUSTER FORGET
```shell
# 清理失效从节点 29768f0e...
redis-cli -a hgrica1@ --cluster call 10.194.68.224:7004 CLUSTER FORGET 29768f0e8683c214d1917b6f96089dfdc2cf7ccb

# 清理失效主节点 caf6f392...
redis-cli -a hgrica1@ --cluster call 10.194.68.224:7004 CLUSTER FORGET caf6f39296079ae02fd7e5e79f50ea90b8678740
```
预期的结果如下:
```text
/data # redis-cli -a hgrica1@ --cluster call 10.194.68.225:7008 CLUSTER FORGET 9d529208e373ed9b6986005e3e62875e4c039abc
Warning: Using a password with '-a' or '-u' option on the command line interface may not be safe.
>>> Calling CLUSTER FORGET 9d529208e373ed9b6986005e3e62875e4c039abc
10.194.68.225:7008: ERR Unknown node 9d529208e373ed9b6986005e3e62875e4c039abc

10.194.68.223:7002: OK
10.194.68.224:7006: OK
10.194.68.224:7005: OK
10.194.68.223:7001: OK
10.194.68.224:7004: OK
10.194.68.225:7009: ERR Unknown node 9d529208e373ed9b6986005e3e62875e4c039abc

10.194.68.225:7007: ERR Unknown node 9d529208e373ed9b6986005e3e62875e4c039abc

10.194.68.223:7003: OK
```

- 方式二：使用脚本分别连接各个节点执行CLUSTER FORGET
```shell
#!/bin/bash
PASSWORD="hgrica1@"
NODE_IDS="29768f0e8683c214d1917b6f96089dfdc2cf7ccb caf6f39296079ae02fd7e5e79f50ea90b8678740 9d529208e373ed9b6986005e3e62875e4c039abc"

NODES=(
  "10.194.68.223:7001"
  "10.194.68.223:7002"
  "10.194.68.223:7003"
  "10.194.68.224:7004"
  "10.194.68.224:7005"
  "10.194.68.224:7006"
  "10.194.68.225:7007"
  "10.194.68.225:7008"
  "10.194.68.225:7009"
)

for NODE in "${NODES[@]}"; do
  HOST=${NODE%:*}
  PORT=${NODE#*:}
  echo "Processing $HOST:$PORT"
  
  for NODE_ID in $NODE_IDS; do
    redis-cli -a $PASSWORD -h $HOST -p $PORT CLUSTER FORGET $NODE_ID
    sleep 1  # 避免过快执行
  done
done
```
> ##### 结果阐述：
> ##### 返回 OK 的节点：已经处理成功，代表目标节点已经忘记了该节点。
> ##### 返回 ERR Unknown node 的节点：代表目标节点不认识该节点,无需处理
