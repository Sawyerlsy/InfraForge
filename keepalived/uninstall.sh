#!/bin/bash
# Keepalived 源码安装版卸载脚本
# 适用版本：2.3.3 (CentOS 7)
# 执行要求：root权限

#######################################
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 恢复默认
#######################################

WORK_DIR=$(pwd)

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：此脚本必须以root权限执行${NC}" 
   exit 1
fi

echo -e "${YELLOW}>>> 开始卸载Keepalived...${NC}"

# 1. 停止服务并禁用自启
echo -e "${GREEN}[步骤1] 停止服务...${NC}"
systemctl stop keepalived 2>/dev/null
systemctl disable keepalived 2>/dev/null

# 2. 源码卸载（需在编译目录执行）
echo -e "${GREEN}[步骤2] 执行源码卸载...${NC}"
KEEPALIVED_SOURCE_DIR="$WORK_DIR/keepalived-2.3.3"  # 替换为实际源码路径
if [[ -d "$KEEPALIVED_SOURCE_DIR" ]]; then
    cd "$KEEPALIVED_SOURCE_DIR"
    make uninstall >/dev/null 2>&1 && echo "源码卸载成功"
else
    echo -e "${YELLOW}警告：源码目录不存在，跳过make uninstall${NC}"
fi

# 3. 删除核心文件
echo -e "${GREEN}[步骤3] 删除配置文件与二进制文件...${NC}"
rm -rfv /etc/keepalived               # 配置目录[5](@ref)
rm -fv /usr/local/keepalived/sbin/keepalived  # 主程序[2](@ref)
rm -fv /usr/sbin/keepalived           # 可能存在的符号链接[6](@ref)

# 4. 清理Systemd服务
echo -e "${GREEN}[步骤4] 移除系统服务...${NC}"
rm -fv /etc/systemd/system/keepalived.service
rm -fv /usr/lib/systemd/system/keepalived.service
rm -fv /etc/systemd/system/multi-user.target.wants/keepalived.service
systemctl daemon-reload

# 5. 删除日志和临时文件
echo -e "${GREEN}[步骤5] 清理日志...${NC}"
rm -rfv /var/log/keepalived*          # 日志文件[8](@ref)
rm -fv /var/run/keepalived.pid        # PID文件[5](@ref)

# 6. 删除环境配置
echo -e "${GREEN}[步骤6] 清理环境配置...${NC}"
rm -fv /etc/sysconfig/keepalived      # 环境变量[2](@ref)
rm -fv /etc/init.d/keepalived         # SysVinit脚本（兼容旧版）[6](@ref)

echo -e "${GREEN}>>> 卸载完成！验证步骤：${NC}"
echo "1. 检查进程: ps aux | grep keepalived"
echo "2. 检查文件: ls /usr/local/keepalived 2>/dev/null"
echo "3. 检查服务: systemctl status keepalived 2>/dev/null"