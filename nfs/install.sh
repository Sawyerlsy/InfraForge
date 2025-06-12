#!/bin/bash
# NFS一键部署脚本（服务端/客户端）支持离线安装
# 支持CentOS/RHEL系统，所有操作在脚本当前目录执行

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以root权限运行！"
    exit 1
fi

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    echo "无法检测操作系统，脚本仅支持CentOS/RHEL"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 离线安装依赖包
install_dependencies() {
    echo "离线安装NFS依赖包..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 检查离线包
    if [ ! -f "${SCRIPT_DIR}/nfs-pack.zip" ]; then
        echo "错误：离线安装包 ${SCRIPT_DIR}/nfs-pack.zip 不存在！"
        exit 1
    fi

    # 创建解压目录
    INSTALL_DIR="${SCRIPT_DIR}/nfs-install"
    mkdir -p "$INSTALL_DIR"

    # 解压到临时目录
    echo "解压离线安装包..."
    unzip -o "${SCRIPT_DIR}/nfs-pack.zip" -d "$INSTALL_DIR"
    if [ $? -ne 0 ]; then
        echo "解压失败！请检查 nfs-pack.zip 文件完整性。"
        exit 1
    fi

    # 处理可能的嵌套目录
    if [ $(ls "$INSTALL_DIR" | wc -l) -eq 1 ]; then
        # 若解压后仅有一个子目录，则进入该目录安装
        SUB_DIR=$(ls "$INSTALL_DIR")
        RPM_DIR="${INSTALL_DIR}/${SUB_DIR}"
    else
        # 若直接解压出多个文件，则使用当前目录
        RPM_DIR="$INSTALL_DIR"
    fi

    # 安装所有 RPM
    echo "安装 RPM 包..."
    rpm -Uvh ${RPM_DIR}/*.rpm --nodeps --force
    if [ $? -ne 0 ]; then
        echo "RPM 包安装失败！"
        exit 1
    fi
    echo "依赖包安装完成！"
}

# 配置服务端
configure_server() {
    echo -e "\n===== NFS服务端配置 ====="

    # 获取共享目录
    read -p "请输入共享目录路径（如 /opt/shared）： " SHARE_DIR

    # 创建目录并设置权限
    mkdir -p $SHARE_DIR
    chmod 777 $SHARE_DIR

    # 获取允许访问的客户端
    read -p "请输入允许访问的客户端（IP/网段，如 192.168.1.0/24 或 *）： " CLIENT_IP

    # 配置exports文件
    echo "$SHARE_DIR $CLIENT_IP(rw,root_squash,all_squash,sync,anonuid=1000,anongid=1000)" >> /etc/exports

    # 启动服务
    echo "启动NFS相关服务..."
    systemctl enable --now rpcbind
    systemctl enable --now nfs-server

    # 应用配置
    exportfs -rv

    # 防火墙配置
    if systemctl is-active --quiet firewalld; then
        echo "配置防火墙..."
        firewall-cmd --permanent --add-service=nfs
        firewall-cmd --permanent --add-service=rpc-bind
        firewall-cmd --permanent --add-service=mountd
        firewall-cmd --reload
    fi

    # 显示配置信息
    echo -e "\n✅ NFS服务端配置完成！"
    echo "共享目录: $SHARE_DIR"
    echo "允许访问: $CLIENT_IP"
    echo "验证命令: showmount -e localhost"
}

# 配置客户端
configure_client() {
    echo -e "\n===== NFS客户端配置 ====="
    # 确保客户端rpcbind服务启动
    systemctl enable --now rpcbind

    # 获取服务端信息（原有代码）
    read -p "请输入NFS服务端IP地址： " SERVER_IP
    read -p "请输入服务端共享目录路径（如 /opt/shared）： " SERVER_SHARE

    # 测试服务端连接（原有代码）
    if ! showmount -e $SERVER_IP &> /dev/null; then
        echo "无法连接NFS服务端！请检查："
        echo "1. 服务端IP是否正确"
        echo "2. 服务端NFS服务是否运行"
        echo "3. 防火墙设置"
        exit 1
    fi

    # 创建挂载点（原有代码）
    read -p "请输入本地挂载点路径（如 /mnt/nfs）： " MOUNT_POINT
    mkdir -p $MOUNT_POINT

    # 挂载NFS共享（原有代码）
    mount -t nfs ${SERVER_IP}:${SERVER_SHARE} $MOUNT_POINT

    # 增强验证：测试文件读写权限（新增）[6,7](@ref)
    touch $MOUNT_POINT/testfile 2>/dev/null
    if [ $? -eq 0 ]; then
        rm -f $MOUNT_POINT/testfile
        echo "✅ 挂载点读写测试成功"
    else
        echo "⚠️ 挂载点无写入权限！请检查服务端exports配置"
    fi

    # 开机挂载设置（原有代码）
    read -p "是否设置开机自动挂载？[y/n] " SET_FSTAB
    if [[ "$SET_FSTAB" =~ [Yy] ]]; then
        echo "${SERVER_IP}:${SERVER_SHARE} $MOUNT_POINT nfs defaults 0 0" >> /etc/fstab
        echo "已添加到/etc/fstab"
    fi

    # 显示配置信息（更新提示）[1,8](@ref)
    echo -e "\n✅ NFS客户端配置完成！"
    echo "服务端: ${SERVER_IP}:${SERVER_SHARE}"
    echo "本地挂载点: $MOUNT_POINT"
    echo "验证命令: mount | grep $MOUNT_POINT"
}

# 主菜单
echo -e "\n===== NFS一键部署脚本 ====="
echo "1. 配置为NFS服务端"
echo "2. 配置为NFS客户端"
echo "3. 退出"

read -p "请选择操作[1-3]: " CHOICE

case $CHOICE in
    1)
        install_dependencies
        configure_server
        ;;
    2)
        install_dependencies
        configure_client
        ;;
    3)
        echo "退出脚本"
        exit 0
        ;;
    *)
        echo "无效选择!"
        exit 1
        ;;
esac
