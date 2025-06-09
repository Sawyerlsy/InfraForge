#!/bin/bash
# Keepalived 离线部署脚本 (支持主从模式)
# 功能：自动部署Keepalived + VIP配置 + Nginx容器监控
set -euo pipefail


# 网卡智能检测
detect_interface() {
    # 获取物理网卡:排除虚拟接口
    mapfile -t PHYS_IFACES < <(ip -o -4 addr show | awk '{if ($2 !~ /^lo$|^docker|^br-|^veth|^tun|^cali|^flannel/ && $9 == "UP");print $2}' | sort -u)
    
    # 默认路由网卡优先
    DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    
    [ -z "$DEFAULT_IFACE" ] && DEFAULT_IFACE=$(
        ip -o -4 addr show | awk '$9~/UP|UNKNOWN/ && $2!~/^lo$/ {print $2; exit}'
    )
    
    # 调试信息输出
    # echo "---------------------------------" >&2
    # echo "默认路由设备：${DEFAULT_IFACE:-未检测到}" >&2
    # echo "物理网卡列表：${PHYS_IFACES[*]:-"未检测到"}" >&2
    # echo "---------------------------------" >&2
    
    # 交互式选择
    if [[ -n "$DEFAULT_IFACE" ]]; then
        echo -e "\n📡 检测到默认路由网卡: $DEFAULT_IFACE" >&2
        read -p "是否使用此网卡? [y/n]: " confirm
        [[ "$confirm" =~ [Yy] ]] && { echo "$DEFAULT_IFACE"; return; }
    fi

    # 多网卡选择
    if [[ ${#PHYS_IFACES[@]} -gt 1 ]]; then
        echo -e "\n🔍 发现多个物理网卡:" >&2
        for i in "${!PHYS_IFACES[@]}"; do
            echo "  [$((i+1))] ${PHYS_IFACES[$i]}">&2
        done
        while true; do
            read -p "请选择序号 (1-${#PHYS_IFACES[@]}): " choice
            [[ "$choice" =~ ^[1-9][0-9]*$ && $choice -le ${#PHYS_IFACES[@]} ]] && {
                echo "${PHYS_IFACES[$((choice-1))]}" 
                return
            }
            echo "无效选择!">&2
        done
    elif [[ ${#PHYS_IFACES[@]} -eq 1 ]]; then
        echo -e "\n🔍 检测到物理网卡: ${PHYS_IFACES[0]}">&2
        read -p "是否使用此网卡? [y/n]: " confirm
        [[ "$confirm" =~ [Yy] ]] && { echo "${PHYS_IFACES[0]}"; return; }
    fi

    # 手动输入
    read -p "请输入网卡名称 (如eth0): " manual_iface
    echo "${manual_iface:-eth0}"
}

function disable_selinux() {
    if [ -f /etc/selinux/config ]; then
        # 1. 优先检查当前运行时状态
        CURRENT_STATE=$(getenforce 2>/dev/null || echo "Disabled")
        
        # 2. 根据当前状态处理
        case "$CURRENT_STATE" in
            Enforcing)
                echo -e "\n🔒 检测到SELinux处于强制模式，正在禁用..."
                setenforce 0
                sed -i '/^[[:space:]]*SELINUX[[:space:]]*=/ s/enforcing/disabled/' /etc/selinux/config
                ;;
            Permissive|Disabled)
                echo -e "\nℹ️  SELinux已处于非强制模式（当前：$CURRENT_STATE）"
                ;;
            *)
                # 3. 配置文件检测（仅当无法获取运行时状态）
                if grep -qE '^[[:space:]]*SELINUX[[:space:]]*=[[:space:]]*enforcing' /etc/selinux/config; then
                    echo -e "\n⚠️  配置文件要求强制模式，但运行时状态未知，强制禁用！"
                    setenforce 0 >/dev/null 2>&1 || true  # 忽略错误
                    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
                fi
                ;;
        esac
    else
        echo -e "\nℹ️  未找到SELinux配置文件，跳过处理"
    fi
}

# 交互式配置
function user_config() {
    # 角色选择
    while true; do
        read -p "请输入 Keepalived 角色 (MASTER|BACKUP): " ROLE
        ROLE=$(echo "$ROLE" | tr '[:lower:]' '[:upper:]')  
        [[ "$ROLE" == "MASTER" || "$ROLE" == "BACKUP" ]] && break
        echo "错误：请输入'MASTER'或'BACKUP'"
    done

    # VIP验证
    while true; do
        read -p "请输入 虚拟IP地址 (VIP): " VIP
        [[ "$VIP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && break
        echo "错误：IP格式无效 (示例: 192.168.1.100)"
    done

    read -p "请输入虚拟路由器ID (MASTER和BACKUP须保持一致,默认:51): " VIRTUAL_ROUTER_ID
    VIRTUAL_ROUTER_ID=${VIRTUAL_ROUTER_ID:-51}

    read -s -p "请输入VRRP认证密码 (默认:@Sy3@lsy): " AUTH_PASS
    AUTH_PASS=${AUTH_PASS:-@Sy3@lsy}
    echo  # 换行

    INTERFACE=$(detect_interface)

    echo -e "\n✅ 最终配置:"
    echo -e "  角色: \033[1;34m$ROLE\033[0m"
    echo -e "  VIP: \033[1;34m$VIP\033[0m"
    echo -e "  网卡: \033[1;34m$INTERFACE\033[0m"
    echo -e "  路由器ID: \033[1;34m$VIRTUAL_ROUTER_ID\033[0m"
    read -p "确认配置? [y/n]: " final_confirm
    [[ "$final_confirm" =~ [Yy] ]] || exit 1
}

# 安装依赖
function install_dependencies() {
    echo -e "\n📦 安装系统依赖..."
    tar -xvf gcc-x86.tar
    rpm -Uvh ./gcc-x86/*.rpm --nodeps --force
    
    tar -xvf openssl.tar
    rpm -Uvh ./openssl/*.rpm --nodeps --force
    
    tar -xvf popt_1.18.orig.tar.gz
    pushd popt-1.18 >/dev/null
    ./configure && make && make install
    popd >/dev/null
    
    tar -xvf daemon-0.8.tar.gz
    pushd daemon-0.8 >/dev/null
    ./configure && make && make install
    popd >/dev/null
}

# 安装Keepalived
function install_keepalived() {
    KEEPALIVED_TAR=$(ls keepalived-*.tar.gz)
    [[ ! "$KEEPALIVED_TAR" =~ keepalived-([0-9.]+)\.tar\.gz ]] && { echo "❌ Keepalived压缩包未找到"; exit 1; }
    KEEPALIVED_VERSION=${BASH_REMATCH[1]}
    
    echo -e "\n🔧 编译Keepalived v$KEEPALIVED_VERSION..."
    tar -xvf "$KEEPALIVED_TAR"
    pushd "keepalived-$KEEPALIVED_VERSION" >/dev/null
    ./configure --prefix=/usr/local/keepalived --disable-ipv6
    make -j$(nproc) && make install
    popd >/dev/null
}

function generate_nginx_check_script() {
    # Nginx监控脚本
    cat > /etc/keepalived/nginx_check.sh <<'EOF'
#!/bin/bash
LOG_FILE="/etc/keepalived/nginx_ha.log"

# 记录日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# 层级1：端口检测（使用curl避免服务假死）
check_port() {
    curl -s -m 2 http://localhost >/dev/null
    return $?
}

# 层级2：进程存在性
check_process() {
    pgrep -x nginx >/dev/null
    return $?
}

# 层级3：HTTP服务（兼容200/301/302/401状态码）
check_http() {
    local timeout=2
    local NGINX_EXPECTED_CODES="200|301|302|401|403|404"
    local url="${NGINX_CHECK_URL:-http://localhost}"
    
    # 使用timeout防止阻塞
    status_code=$(timeout $timeout curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    local ret=$?
    
    # 处理超时及错误码
    if [ $ret -eq 124 ]; then
        log "HTTP检测超时"
        return 1
    elif [ $ret -ne 0 ]; then
        log "Curl错误: $ret"
        return 1
    fi
    
    [[ "$status_code" =~ ^(${NGINX_EXPECTED_CODES:-200})$ ]]
}

# 主检测逻辑
# 分别记录返回值
check_port; port_ret=$?
check_process; process_ret=$?
check_http; http_ret=$?

if [ $port_ret -ne 0 ] || [ $process_ret -ne 0 ] || [ $http_ret -ne 0 ]; then
    log "Nginx异常! 端口:$port_ret 进程:$process_ret HTTP:$http_ret"
    exit 1
else
    exit 0
fi
EOF
    chmod 744 /etc/keepalived/nginx_check.sh

}

function generate_notify_script() {
    # 状态通知脚本
    cat > /etc/keepalived/notify.sh <<'EOF'
#!/bin/bash
case "$1" in
    MASTER)
        echo "$(date '+%Y-%m-%d %H:%M:%S') 切换为MASTER" >> /etc/keepalived/keepalived_notify.log
        # 此处可添加业务恢复逻辑
        ;;
    BACKUP)
        echo "$(date '+%Y-%m-%d %H:%M:%S') 切换为BACKUP" >> /etc/keepalived/keepalived_notify.log
        ;;
    FAULT)
        echo "$(date '+%Y-%m-%d %H:%M:%S') 进入FAULT状态" >> /etc/keepalived/keepalived_notify.log
        ;;
esac
EOF

    chmod 744 /etc/keepalived/notify.sh

}


function generate_keepalived_conf() {
    cat > /etc/keepalived/keepalived.conf <<EOF
! Configuration File for keepalived

global_defs {
   # 定义管理员邮件地址,表示keepalived在发生诸如切换操作时需要发送email通知,以及email发送给哪些邮件地址,可以有多个,每行一个
    #notification_email {    
        #设置报警邮件地址，可以设置多个，每行一个。 需开启本机的sendmail服务 
        #137708020@qq.com
    #}
    #keepalived在发生诸如切换操作时需要发送email通知地址，表示发送通知的邮件源地址是谁
    #notification_email_from 137708020@qq.com
    
    #指定发送email的smtp服务器
    #smtp_server 127.0.0.1
    
    #设置连接smtp server的超时时间
    #smtp_connect_timeout 30
    
    #运行keepalived的机器的一个标识，通常可设为hostname。故障发生时，发邮件时显示在邮件主题中的信息。
    router_id NGINX-1
    vrrp_skip_check_adv_addr
    vrrp_garp_interval 0.5
    vrrp_gna_interval 0.5

    enable_script_security
    script_user root
}

# 定义chk_nginx脚本,脚本执行间隔10秒，权重-10，检测nginx服务是否在运行。有很多方式，比如进程，用脚本检测等等
vrrp_script chk_nginx {  
 
    #这里通过脚本监测    
    script "/etc/keepalived/nginx_check.sh"  
    
    #脚本执行间隔，每2s检测一次
    interval 2    
    
    #脚本结果导致的优先级变更，检测失败（脚本返回非0）则优先级 -15   
    weight -15     
    
    #检测连续2次失败才算是失败。会用weight减少优先级（1-255之间）    
    fall 2     
    
    #检测3次成功才算成功,恢复优先级到初始值
    rise 3                    
}

#定义vrrp实例，VI_1 为虚拟路由的标示符，自己定义名称，keepalived在同一virtual_router_id中priority(0-255)最大的会成为MASTER，也就是接管VIP，当priority最大的主机发生故障后次priority将会接管
vrrp_instance VI_1 { 
 
    #指定keepalived的角色，MASTER表示此主机是主服务器，BACKUP表示此主机是备用服务器。注意这里的state指定instance(Initial)的初始状态，就是说在配置好后，这台服务器的初始状态就是这里指定的，
    #但这里指定的不算，还是得要通过竞选通过优先级来确定。如果这里设置为MASTER，但如若他的优先级不及另外一台，那么这台在发送通告时，会发送自己的优先级，另外一台发现优先级不如自己的高，
    #那么他会就回抢占为MASTER   
    state $ROLE 
    
    #指定HA监测网络的接口。与本机 IP 地址所在的网络接口相同，可通过ip addr 查看
    interface $INTERFACE
 
    # 发送多播数据包时的源IP地址，这里注意了，这里实际上就是在哪个地址上发送VRRP通告，这个非常重要，
    #一定要选择稳定的网卡端口来发送，这里相当于heartbeat的心跳端口，如果没有设置那么就用默认的绑定的网卡的IP，也就是interface指定的IP地址    
    #mcast_src_ip 192.168.10.101
    
    #虚拟路由标识，这个标识是一个数字，同一个vrrp实例使用唯一的标识。即同一vrrp_instance下，MASTER和BACKUP必须是一致的
    virtual_router_id $VIRTUAL_ROUTER_ID    
 
    #定义优先级，数字越大，优先级越高，在同一个vrrp_instance下，MASTER的优先级必须大于BACKUP的优先级   
    priority $([ "$ROLE" == "MASTER" ] && echo 100 || echo 90)

    #设定MASTER与BACKUP负载均衡器之间同步检查的时间间隔，单位是秒.每隔一秒发送一次心跳，确保从服务器存活   
    advert_int 1       
 
    #设置验证类型和密码。主从必须一样
    authentication {    
    
        #设置vrrp验证类型，主要有PASS和AH两种
        auth_type PASS           
        
        #设置vrrp验证密码，在同一个vrrp_instance下，MASTER与BACKUP必须使用相同的密码才能正常通信
        auth_pass $AUTH_PASS           
    }
    
    #VRRP HA 虚拟地址 如果有多个VIP，继续换行填写
    #设置VIP，它随着state变化而增加删除，当state为MASTER的时候就添加，当state为BACKUP的时候则删除，由优先级决定
    virtual_ipaddress {          
        $VIP
    }
    
    #执行nginx检测脚本。注意这个设置不能紧挨着写在vrrp_script配置块的后面（实验中碰过的坑），否则nginx监控失效！！
    track_script {   
 
       #引用VRRP脚本，即在 vrrp_script 部分指定的名字。定期运行它们来改变优先级，并最终引发主备切换。 
       chk_nginx                    
    }

    #当该keepalived切换状态时,执行下面的脚本
    notify_master "/etc/keepalived/notify.sh MASTER"
    notify_backup "/etc/keepalived/notify.sh BACKUP"
    notify_fault "/etc/keepalived/notify.sh FAULT"
}
EOF
}


# 配置Keepalived
function configure_keepalived() {
    echo -e "\n⚙️ 配置Keepalived ($ROLE节点)..."
    mkdir -p /etc/keepalived
    
    # 生成配置文件
    generate_keepalived_conf
    
    # Nginx监控脚本
    generate_nginx_check_script

    # 状态通知脚本
    generate_notify_script
}

# 创建Systemd服务
function create_service() {
    echo -e "\n🛠️ 创建Systemd服务..."
    cat > /etc/systemd/system/keepalived.service <<EOF
[Unit]
Description=Keepalived High Availability Monitor
After=network-online.target syslog.target
Requires=network-online.target

[Service]
Type=forking
PIDFile=/var/run/keepalived.pid
EnvironmentFile=-/etc/sysconfig/keepalived
ExecStart=/usr/local/keepalived/sbin/keepalived -f /etc/keepalived/keepalived.conf \$KEEPALIVED_OPTIONS
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF
}

# 启动服务
function start_service() {
    echo "▶️ 预检配置文件..."
    /usr/local/keepalived/sbin/keepalived -t -f /etc/keepalived/keepalived.conf
    [ $? -ne 0 ] && { echo "❌ 配置检查失败!"; exit 1; }
    echo -e "\n🚀 启动Keepalived服务..."
    systemctl daemon-reload
    systemctl enable keepalived
    systemctl start keepalived
}

# 主流程
function main() {
    user_config
    install_dependencies
    install_keepalived
    configure_keepalived
    create_service
    start_service
    
    echo -e "\n✅ 部署完成！"
    echo "============================================"
    echo " Keepalived路径: /usr/local/keepalived"
    echo " 配置文件: /etc/keepalived/keepalived.conf"
    echo " 运行模式: $ROLE"
    echo " VIP地址: $VIP"
    echo " 网卡: $INTERFACE"
    echo " 路由器ID: $VIRTUAL_ROUTER_ID"
    echo " 操作命令: systemctl [start|stop|status] keepalived"
    echo " 监控脚本: /etc/keepalived/nginx_check.sh"
    echo " 确认MASTER节点是否绑定VIP: ip addr show | grep $VIP"
    echo "============================================"
}

disable_selinux
main