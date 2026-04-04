#!/usr/bin/env bash

# 确保在 /root 目录下操作
cd /root

# 定义组件版本
ARGO_VERSION="2026.3.0"
TTYD_VERSION="1.7.7"
SUPERCRONIC_VERSION="0.2.44"

# 预先创建必要的目录，防止 cat 报错
mkdir -p /etc/supervisor/conf.d
mkdir -p /usr/local/bin

# 1. 下载 Cloudflared (用于内网穿透)
curl -sSL -o /usr/local/bin/cf https://github.com/cloudflare/cloudflared/releases/download/$ARGO_VERSION/cloudflared-linux-amd64
chmod +x /usr/local/bin/cf

# 2. 下载 ttyd (Web 终端)
curl -sSL -o /usr/local/bin/td https://github.com/tsl0922/ttyd/releases/download/$TTYD_VERSION/ttyd.x86_64
chmod +x /usr/local/bin/td

# 3. 下载 Supercronic (用于定时保活任务)
curl -sSL -o /usr/local/bin/sc https://github.com/aptible/supercronic/releases/download/v$SUPERCRONIC_VERSION/supercronic-linux-amd64
chmod +x /usr/local/bin/sc

# --- 配置 Supervisor 服务 ---

# ttyd 启动配置 (使用环境变量中的 USER 和 PASS 进行鉴权)
# 注意：添加了 -W 参数允许网页写入/交互
cat > /etc/supervisor/conf.d/td.conf <<EOF
[program:td]
command=/usr/local/bin/td -p 80 -W -c %(ENV_USER)s:%(ENV_PASS)s bash
autostart=true
autorestart=true
stdout_logfile = /dev/null
stderr_logfile = /dev/null
EOF

# Cloudflared 启动配置
cat > /etc/supervisor/conf.d/cf.conf <<EOF
[program:cf]
command=/usr/local/bin/cf tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token %(ENV_T)s
autostart=true
autorestart=true
stdout_logfile = /dev/null
stderr_logfile = /dev/null
EOF

# --- 保活脚本与 Crontab ---
cat > /usr/local/bin/keepalive.sh <<'EOF'
#!/bin/bash
# 检查环境变量 E 是否存在，避免空请求
if [ -z "$E" ]; then
  exit 0
fi
# 随机休眠防止检测
sleep $((RANDOM % 300))
status=$(curl -o /dev/null -s -w "%{http_code}" $E/status)
echo `date "+%Y-%m-%d %H:%M:%S"` - Status: $status > /tmp/keepalive.log
EOF
chmod +x /usr/local/bin/keepalive.sh

cat > /etc/my-crontab <<EOF
*/5 * * * * /usr/local/bin/keepalive.sh
EOF

# Supercronic 启动配置
cat > /etc/supervisor/conf.d/sc.conf <<EOF
[program:sc]
directory=/etc
command=/usr/local/bin/sc /etc/my-crontab
autostart=%(ENV_ENABLE_SC)s
autorestart=true
stdout_logfile = /dev/null
stderr_logfile = /dev/null
EOF
