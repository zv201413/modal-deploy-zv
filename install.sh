#!/usr/bin/env bash

cd /root

XRAY_VERSION="26.3.27"
ARGO_VERSION="2026.3.0"
TTYD_VERSION="1.7.7"

curl -sSL -o Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip
unzip -q Xray-linux-64.zip
mv xray /usr/local/bin/xy
rm -rf *

curl -sSL -o /etc/xy.json https://raw.githubusercontent.com/vevc/modal-deploy/refs/heads/main/xray-config.json

curl -sSL -o /usr/local/bin/cf https://github.com/cloudflare/cloudflared/releases/download/$ARGO_VERSION/cloudflared-linux-amd64
chmod +x /usr/local/bin/cf

curl -sSL -o /usr/local/bin/td https://github.com/tsl0922/ttyd/releases/download/$TTYD_VERSION/ttyd.x86_64
chmod +x /usr/local/bin/td

# xy startup
cat > /usr/local/bin/start_xy.sh <<'EOF'
#!/usr/bin/env bash

cd /etc
sed -i "s/YOUR_UUID/$U/g" xy.json
exec xy -c xy.json

EOF
chmod +x /usr/local/bin/start_xy.sh

cat > /etc/supervisor/conf.d/xy.conf <<EOF
[program:xy]
command=start_xy.sh
autostart=true
autorestart=true
stdout_logfile = /dev/null
stderr_logfile = /dev/null

EOF

# cf startup
cat > /etc/supervisor/conf.d/cf.conf <<EOF
[program:cf]
command=cf tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token %(ENV_T)s
autostart=true
autorestart=true
stdout_logfile = /dev/null
stderr_logfile = /dev/null

EOF

# td startup
cat > /etc/supervisor/conf.d/td.conf <<EOF
[program:td]
command=td -p 80 -W bash
autostart=true
autorestart=true
stdout_logfile = /dev/null
stderr_logfile = /dev/null

EOF
