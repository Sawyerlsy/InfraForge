#### 1、脚本头部和基础设置
```shell
#!/bin/bash
set -euo pipefail
```
```text
#!/bin/bash: 指定使用bash解释器执行脚本

set -e: 如果任何命令返回非零退出状态（失败），立即退出脚本

set -u: 使用未定义的变量时报错

set -o pipefail: 管道中任何命令失败，整个管道都视为失败
```

#### 2、变量定义
```shell
DEPLOY_DIR="."
DEFAULT_HARBOR_REGISTRY="core.harbor.domain:32388/virtual-station-rebuild"
HARBOR_DOMAIN="core.harbor.domain:32388"
```

#### 3、颜色定义和日志函数
```shell
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
```

#### 4、检查前提条件
