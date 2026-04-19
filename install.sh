#!/usr/bin/env bash

# 确保在 /root 目录下操作
cd /root

# 定义组件版本
ARGO_VERSION="2026.3.0"
TTYD_VERSION="1.7.7"

# 预先创建必要的目录，防止 cat 报错
mkdir -p /etc/supervisor/conf.d
mkdir -p /usr/local/bin

# 1. 下载 Cloudflared (用于内网穿透)
curl -sSL -o /usr/local/bin/cf https://github.com/cloudflare/cloudflared/releases/download/$ARGO_VERSION/cloudflared-linux-amd64
chmod +x /usr/local/bin/cf

# 2. 下载 ttyd (Web 终端)
curl -sSL -o /usr/local/bin/td https://github.com/tsl0922/ttyd/releases/download/$TTYD_VERSION/ttyd.x86_64
chmod +x /usr/local/bin/td

# --- 配置 Supervisor 服务 ---

# ttyd 启动配置
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

# --- 保活脚本生成 (Persistent Loop) ---
cat > /tmp/keepalive.sh <<'EOF'
#!/bin/bash
if [ -z "$KPAL" ]; then
  echo "Error: KPAL environment variable is not set."
  exit 1
fi

# 解析 KPAL 环境变量: [RANGE]:[OFFSET]:URL
if [[ "$KPAL" == *":"*":"* ]]; then
    range=$(echo "$KPAL" | cut -d: -f1)
    offset=$(echo "$KPAL" | cut -d: -f2)
    url=$(echo "$KPAL" | cut -d: -f3-)
elif [[ "$KPAL" == *":"* ]]; then
    p1=$(echo "$KPAL" | cut -d: -f1)
    url=$(echo "$KPAL" | cut -d: -f2-)
    range="${p1:-300}"
    offset=60
else
    url="$KPAL"
    range=300
    offset=60
fi

range=${range:-300}
offset=${offset:-60}

if [[ ! "$url" =~ ^http ]]; then
  echo "❌ Error: URL is missing or invalid in KPAL: $KPAL"
  echo "💡 Hint: KPAL format should be RANGE:OFFSET:URL"
  exit 1
fi

echo "🚀 Keepalive started for $url (Range: $range, Offset: $offset)"

while true; do
  if ! [[ "$range" =~ ^[0-9]+$ ]] || [ "$range" -lt 1 ]; then range=300; fi
  if ! [[ "$offset" =~ ^[0-9]+$ ]]; then offset=60; fi

  sleep_time=$((RANDOM % range + offset))
  sleep $sleep_time

  status=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")
  echo "$(date '+%Y-%m-%d %H:%M:%S') [KPAL] range:$range offset:$offset sleep:$sleep_time URL:$url Status:$status" >> /tmp/keepalive.log
  tail -n 20 /tmp/keepalive.log > /tmp/keepalive.tmp && mv /tmp/keepalive.tmp /tmp/keepalive.log
done
EOF
chmod +x /tmp/keepalive.sh

# kpal 启动配置
cat > /etc/supervisor/conf.d/kpal.conf <<EOF
[program:kpal]
command=/tmp/keepalive.sh
autostart=%(ENV_ENABLE_SC)s
autorestart=true
stdout_logfile = /dev/null
stderr_logfile = /dev/null
EOF
