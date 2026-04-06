### 1、当前keepalived默认配置的是nginx检查脚本,请根据需要进行修改

### 2、抢占模式和非抢占模式
Keepalived **默认就是抢占模式**。这意味着，如果原主节点（Master）在发生故障后恢复了，它会凭借更高的优先级（Priority），自动“抢回”VIP和主节点地位[reference:0][reference:1]。

---

#### 📝2.1 如何设置为非抢占模式

要实现非抢占，需要修改所有相关节点的 `/etc/keepalived/keepalived.conf` 配置文件，主要遵循以下两个关键步骤：

*   **1. 将节点的状态都设为 `BACKUP`**
    *   在非抢占模式下，所有的节点（无论优先级高低）在配置文件中都必须将 `state` 设置为 `BACKUP`，而不能是 `MASTER`。

*   **2. 在所有节点上添加 `nopreempt` 参数**
    *   在 `vrrp_instance` 配置块内，添加 `nopreempt` 参数。该参数的作用就是禁止优先级高的节点在恢复后去抢占VIP。
    *   **注意**：有些资料提到只在高优先级节点配置 `nopreempt` 也可以，但将所有节点统一配置是更稳妥和推荐的做法。

---

#### 💡 2.2 配置示例

下面是一个标准的非抢占模式配置示例。你需要将以下配置分别用于你的两台服务器（注意修改`router_id`和`priority`的值）：

```bash
# 节点A (通常作为主节点)
global_defs {
   router_id LVS_DEVEL_A    # 此节点的唯一标识，可自定义
}

vrrp_script chk_app {
    script "/usr/local/bin/check.sh"
        
    #脚本执行间隔，每2s检测一次
    interval 2

    #脚本结果导致的优先级变更，检测失败（脚本返回非0）则优先级 -15
    # 注意：不设置 weight 参数
    #weight -15

    #检测连续2次失败才算是失败。会用weight减少优先级（1-255之间）
    fall 2

    #检测3次成功才算成功,恢复优先级到初始值
    rise 3
}


vrrp_instance VI_1 {
    state BACKUP            # ★ 关键1: 所有节点状态都设为 BACKUP
    nopreempt               # ★ 关键2: 添加此参数，禁止抢占
    interface eth0
    virtual_router_id 51
    priority 100            # 节点A优先级较高，通常为Master
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        192.168.1.100/24
    }
    
     track_script {
        chk_app
    }
}
```

```bash
# 节点B (备节点)
global_defs {
   router_id LVS_DEVEL_B    # 节点B的唯一标识
}

vrrp_script chk_app {
    script "/usr/local/bin/check.sh"
    #脚本执行间隔，每2s检测一次
    interval 2

    #脚本结果导致的优先级变更，检测失败（脚本返回非0）则优先级 -15
    # 注意：不设置 weight 参数
    #weight -15

    #检测连续2次失败才算是失败。会用weight减少优先级（1-255之间）
    fall 2

    #检测3次成功才算成功,恢复优先级到初始值
    rise 3
}

vrrp_instance VI_1 {
    state BACKUP            # ★ 关键1: 状态也是 BACKUP
    nopreempt               # ★ 关键2: 同样添加 nopreempt
    interface eth0
    virtual_router_id 51
    priority 90             # 节点B优先级较低，通常为Backup
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        192.168.1.100/24
    }
    
     track_script {
        chk_app
    }
}
```

---

#### ⚠️ 注意事项

*   **`nopreempt` 生效条件**：`nopreempt` 参数只在节点状态为 `BACKUP` 时才会生效。因此，**必须将所有节点的 `state` 设置为 `BACKUP`**[reference:7][reference:8]。初始Master角色会由优先级（`priority`）更高的节点担任。

*   **与健康检查 (`track_script`) 的联动**：如果使用 `track_script` 进行健康检查，并希望通过它触发故障转移，那么在你的健康检查脚本中**不要配置 `weight` 参数**[reference:9][reference:10]。配置 `weight` 后，脚本失败只会降低节点优先级，可能不会触发VIP切换[reference:11]。

*   **完全宕机 vs. 应用故障**：
    *   **节点完全宕机**：即使配置了 `nopreempt`，VIP 依然会切换。这是 VRRP 协议的基本功能。
    *   **应用故障（节点存活）**：如上条所述，要让应用故障触发切换，应确保 `track_script` 不设置 `weight` 参数。

### 3、 keepalived部署及调试
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
