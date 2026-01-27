## 一、Miniconda安装配置
### 1、Windows下安装
### 2、CentOS下安装
### 3、环境配置
```shell
# 1. 清除所有已配置的镜像通道（不会删除defaults）
conda config --remove-key channels

# 1. 移除旧的通道配置（按需执行，如果之前配过才需要）
conda config --remove channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
conda config --remove channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/

# 2. 添加清华TUNA镜像（注意顺序）
# free、main（Anaconda官方）	增加了 conda-forge （主流社区）
conda config --add channels defaults
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main/
conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/

# 3. 启用严格优先级：只从高优先级channel中选包
# 默认情况下，Conda 使用 flexible 模式遍历所有 channel 查找兼容版本，这会导致求解器在多个源之间反复比对，尤其当添加了大量第三方 channel 时，“Solving environment”时间呈指数增长
# strict (严格) 模式：当搜索一个包时，Conda会严格按照通道列表的顺序，从高优先级通道中选取所有依赖包。例如，如果 conda-forge 有包A，main 也有，Conda会全部从 conda-forge 中获取，避免混合来源导致的依赖冲突。这能构建出更一致、可重现的环境。
# flexible (灵活) 模式 (默认)：Conda会从所有已配置的通道中混合选取“最新版本”的包，可能导致同一个环境的包来自不同通道，增加环境不稳定的风险
conda config --set channel_priority strict

# 显示来源URL，便于调试
conda config --set show_channel_urls yes

# 4. 验证配置
conda config --show channels 
conda config --show channel_priority
```
## 二、常用命令
```shell
# 查看当前conda配置信息（关注`envs directories`和`package cache`路径）
conda info

# 查看所有已创建的环境
conda env list

# 创建环境
conda create -n data_sentry python=3.11


# 创建并激活环境
conda create -n py_stu python=3.9   # -n 后是环境名称
conda activate py_stu  # 激活py_stu这个环境
conda deactivate # 退回到base
# 删除环境
conda env remove -n py_stu
# 查看已有环境
conda info -e
conda env list
# 包管理用pip和conda都可以，我一般更喜欢用pip

# 安装包（conda和pip都可以，有些pip没有的包可以使用conda来安装）
conda install numpy
pip install numpy
# 如果还是比较慢，可以在pip的包后面加上镜像源
pip install numpy -i https://pypi.doubanio.com/simple/

# 更新包
conda update numpy
pip install --upgrade numpy

# 卸载包
conda remove numpy
pip uninstall numpy

# 查看当前环境已安装的包
conda list
pip list
```
## 三、项目打包部署
