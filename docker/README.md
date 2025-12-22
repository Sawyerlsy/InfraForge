### Docker资源地址
https://download.docker.com/linux/static/stable

### Docker Compose资源地址
https://github.com/docker/compose/releases

### 常用配置

#### 2、自定义Docker seccomp配置
```shell
# 配置seccomp
vim /etc/docker/daemon.json

{
  "insecure-registries": ["core.harbor.domain:32388"],
  "seccomp-profile" : "/etc/docker/seccomp.json"
}

# 创建seccomp配置文件
touch /etc/docker/seccomp.json


# 重新加载服务配置和重启docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# 查看是否生效
docker info | grep seccomp
# Profile: /etc/docker/seccomp.json

#### 3、Docker日志轮转
```shell
# 添加json配置
vim /etc/docker/daemon.json

{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "10"
  }
}

# 重新加载服务配置和重启docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# 查看 Docker 守护进程的默认日志驱动
docker info --format '{{.LoggingDriver}}'

# 查看容器的具体日志配置
docker inspect <container_id> | grep LogConfig -A 10
```
> - 注意：日志轮转配置后仅对之后新增的容器生效,旧容器的日志不会被轮转.对于旧容器有两种方式处理:
>   - 重新创建容器
>   - 在docker compose配置文件中配置logging

### 常用功能
#### 1、清理镜像和容器
```shell
# 删除镜像
docker rmi $(docker images | grep "none" | awk '{print $3}') 

# 删除容器
docker rm $(docker ps -aq --filter "status=exited") 
```

#### 2、创建swarm集群
<h6>在Docker Swarm集群中，管理节点（Manager Nodes） 负责集群的管理和编排，工作节点（Worker Nodes） 则负责运行容器任务。管理节点数量为奇数，最少为3个。
如果只有三台服务器,那么三台服务器都建议作为manager节点,同时运行容器任务</h6>
```shell
# 创建集群,并指定manager节点的IP地址
docker swarm init --advertise-addr 10.194.66.176 --dispatcher-heartbeat 180s

# 在管理节点上获取worker或者manager的加入命令
docker swarm join-token manager
docker swarm join-token worker

# 查看节点
docker node ls

# 退出集群
docker swarm leave --force

# 添加标签
docker node update --label-add app=virtual-station-rebuild --label-add zone=hebei --label-add service=upload production2

# 查看节点信息
docker node inspect <node_id>
docker node inspect --pretty <node_id>

# 创建集群overlay网络
docker network create --driver overlay --attachable --subnet=192.168.0.0/24 --gateway=192.168.0.254  app_net
```
#### 3、设置普通用户docker权限
##### 3.1 让普通用户拥有docker权限
```shell
# 1、检查 docker 组是否存在
cat /etc/group | grep docker
# 如果看到类似 docker:x:994:的输出，说明组已存在。如果不存在，需要创建它
sudo groupadd docker
```

```shell
# 2、将用户 hgits 添加到 docker 组
sudo usermod -aG docker hgits
# -a参数表示“追加”，确保不覆盖用户原有的其他组。
# -G参数指定要加入的组名，这里是 docker。
```

```shell
# 3、让组权限更改立即生效
# - 方法一（推荐）：完全注销当前用户会话，然后重新登录。
# - 方法二（快速生效）：如果不想注销，可以执行以下命令刷新当前会话的组信息
newgrp docker
```
##### 3.2 如果普通用户仍没有权限
```shell
#1. 确认hgits用户已加入docker组
groups hgits
```
```shell
# 2. 检查Docker套接字的属组（关键步骤）
ls -l /var/run/docker.sock
```
```shell
# 3、修改套接字文件的属组（需要root权限）
sudo chown root:docker /var/run/docker.sock
```
```shell
# 4、刷新用户组会话（让更改生效）
newgrp docker
```




























