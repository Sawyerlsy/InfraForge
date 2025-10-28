当前keepalived默认配置的是nginx检查脚本,请根据需要进行修改
journalctl -u keepalived -n 20


### keepalived部署及调试
##### 1、在两个keepalived节点中分别查看日志进行验证
```shell
# 查看keepalived服务日志
journalctl -u keepalived -n 20

# 查看keepalived切换通知
less /etc/keepalived/keepalived_notify.log

# 查看nginx_check.sh 输出的错误日志
less /etc/keepalived/nginx_ha.log
```
##### 2、查看VIP挂载情况(VIP只会挂载在MASTER节点中)
```shell
ip addr | grep 10.194.65
# inet 10.194.65.143/24 brd 10.194.65.255 scope global noprefixroute ens160
# inet 10.194.65.145/24 scope global secondary ens160
# 显示结果为ens160网卡中绑定了两个地址,一个是主IP地址，一个是次IP地址
# 两者的作用域都是global,表明两个IP地址可以被其他网络中的设备访问，是全局有效的
```
