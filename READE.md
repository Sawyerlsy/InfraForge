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
```
