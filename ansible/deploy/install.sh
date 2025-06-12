#!/bin/bash
# Ansible 离线安装脚本 - 支持密钥自动化处理（优化版）
# 使用说明: 
#   1. 将脚本和所有 RPM 包放在同一目录
#   2. 创建 hosts.txt 文件包含目标 IP（每行一个）
#   3. 执行: chmod +x install.sh && ./install.sh

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 恢复默认颜色

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}❌ 错误：请使用 root 权限执行脚本！${NC}" >&2
   exit 1
fi

# ========== 阶段1: 安装 Ansible ==========
echo -e "\n${BLUE}[1/4] 安装 Ansible RPM 包${NC}"
if command -v ansible &>/dev/null; then
    echo -e "${YELLOW}⏩ 检测到 Ansible 已安装，跳过安装步骤${NC}"
    SKIP_INSTALL=true
else
    # 检查 RPM 包存在性
    if [ -z "$(ls ./*.rpm 2>/dev/null)" ]; then
        echo -e "${RED}❌ 错误：未找到任何 RPM 包！${NC}" >&2
        exit 1
    fi

    if ! rpm -Uvh ./*.rpm --nodeps --force; then
        echo -e "${RED}❌ RPM 安装失败！请检查依赖包完整性${NC}" >&2
        exit 1
    fi

    # 验证安装
    echo -e "\n${GREEN}✅ 安装验证:${NC}"
    ansible --version || {
        echo -e "${RED}❌ Ansible 未正确安装！${NC}"; 
        exit 1
    }
fi

# ========== 阶段2: SSH 密钥配置 ==========
echo -e "\n${BLUE}[2/4] SSH 密钥配置${NC}"
KEY_FILE="/root/.ssh/id_rsa"

# 生成 4096 位 RSA 密钥（仅当不存在时）
if [ ! -f "$KEY_FILE" ]; then
    echo "生成 SSH 密钥对 (RSA 4096位)..."
    ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N '' -q <<< y
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}🔑 密钥生成成功: $KEY_FILE${NC}"
        # 加固密钥权限
        chmod 600 "$KEY_FILE"
        chmod 700 ~/.ssh
    else
        echo -e "${RED}❌ 密钥生成失败！${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⏩ 检测到现有 SSH 密钥: $KEY_FILE，跳过生成${NC}"
fi

# ========== 阶段3: 主机指纹自动化处理（优化版） ==========
echo -e "\n${BLUE}[3/4] 主机指纹处理${NC}"

# 检查 hosts 文件
HOSTS_FILE="hosts.txt"
if [ ! -f "$HOSTS_FILE" ]; then
    echo -e "${RED}❌ 错误：缺少 $HOSTS_FILE 文件（每行一个目标 IP）${NC}" >&2
    exit 1
fi

# 创建临时文件记录本次新增指纹
TEMP_KNOWN_HOSTS=$(mktemp)
NEW_HOST_COUNT=0

# 批量获取主机密钥（带错误处理）
echo "添加主机密钥到 ~/.ssh/known_hosts..."
while read -r ip; do
    # 删除旧记录避免重复添加[6,8](@ref)
    ssh-keygen -R "$ip" >/dev/null 2>&1
    
    # 创建临时文件捕获输出
    temp_file=$(mktemp)
    
    # 尝试获取主机密钥（带超时）
    if ssh-keyscan -T 5 "$ip" 2>/dev/null > "$temp_file"; then
        # 关键修复：验证是否获取到有效密钥
        if [ -s "$temp_file" ]; then
            cat "$temp_file" >> ~/.ssh/known_hosts
            cat "$temp_file" >> "$TEMP_KNOWN_HOSTS"
            echo -e "  ${GREEN}✅ 成功添加 $ip 的密钥指纹${NC}"
            ((NEW_HOST_COUNT++))
        else
            echo -e "  ${YELLOW}⚠️  $ip 无响应，未获取到密钥${NC}"
        fi
    else
        echo -e "  ${RED}❌ $ip 连接失败（命令执行错误）${NC}"
    fi
    
    rm -f "$temp_file"
done < "$HOSTS_FILE"

# 确保known_hosts文件权限正确
chmod 600 ~/.ssh/known_hosts

# ========== 阶段4: 配置验证与优化 ==========
echo -e "\n${BLUE}[4/4] 配置验证与优化${NC}"

# 验证配置
echo -e "\n${GREEN}✅ 配置验证:${NC}"
echo "SSH 私钥: $(ls -l $KEY_FILE | awk '{print $1,$3,$4,$9}')"
echo "已知主机总记录: $(grep -c "^" ~/.ssh/known_hosts) 条"
echo "本次新增有效记录: $NEW_HOST_COUNT 条"

# 清理临时文件
rm -f "$TEMP_KNOWN_HOSTS"

# ========== 完成 ==========
echo -e "\n${GREEN}[完成] Ansible 安装和主机指纹配置成功！${NC}"
echo -e "下一步:"
echo -e "1. 分发公钥: ${YELLOW}ssh-copy-id -i $KEY_FILE user@host${NC}"
echo -e "2. 测试连接: ${YELLOW}ansible -i hosts.txt -m ping all${NC}"