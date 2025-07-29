如有必要可以采用nfs + keepalived的方式搭建高可用集群,需要配置nfs_check.sh

### 离线环境下如何下载依赖
```shell
# 仅下载rpm包
yum install --downloadonly --downloaddir=./ nfs-utils libnfsidmap keyutils libevent libbasicobjects gssproxy
```

```shell
# 强制安装
rpm -Uvh ./*.rpm --nodeps --force
```
