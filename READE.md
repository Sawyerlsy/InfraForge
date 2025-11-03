### 国产化问题集锦
##### 1、银河麒麟系统可能预装了 Podman，而 Podman 与 Docker 的守护进程（dockerd）存在冲突。当两者同时运行时，可能导致权限问题
```shell
# 卸载 Podman
sudo yum remove podman -y
# 重启 Docker
sudo systemctl restart docker
```

##### 2、调整open files限制
```shell
# 修改limits.conf,当前会话重新登录即可,已经运行的应用需要重启
cat >> /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
* soft memlock unlimited
* hard memlock unlimited
* soft nproc 120000
* hard nproc 120000
EOF

# 查看是否生效
# open files：对应配置中的 nofile，应显示为 65535。
# max user processes：对应配置中的 nproc，应显示为 120000
ulimit -a

# 如果没有生效,或者root生效而其他的用户不生效,则检测limits.d目录是否存在20-nproc.conf, 90-nproc.conf等文件
ls /etc/security/limits.d/

# 如果有对应的文件,则增加权限配置即可，如:
root       soft    nproc     unlimited
```
#### 3、内存敏感型的应用建议关闭swap
```shell
# 临时关闭swap
sudo swapoff -a

# 永久关闭swap 
sed -i '/swap/d' /etc/fstab # 删除包含swap的行

# 可选：调整内核参数（彻底禁用 Swap 倾向）
echo "vm.swappiness=0" | sudo tee -a /etc/sysctl.conf  # 禁止内核使用 Swap
sudo sysctl -p 

# 查看是否已禁用
free -hm
swapon --show
```

#### 4、内核参数调整
```shell
# 激进内存策略，避免申请失败，但需防范 OOM
echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
# 显著提升高并发服务的连接容量，需与应用配置协同
echo "net.core.somaxconn = 10240" >> /etc/sysctl.conf
sysctl -p

# 验证参数
cat /proc/sys/vm/overcommit_memory  # 应为 1
cat /proc/sys/net/core/somaxconn    # 应为 10240
```
> - Redis 集群部署时，这两个参数是必备优化项，可减少 Cannot allocate memory 错误和连接超时问题
> - 若物理内存紧张，优先考虑 vm.overcommit_memory=2 并增加 Swap 空间
