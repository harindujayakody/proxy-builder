#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

PROJECT="proxy-builder"
INSTALL_DIR="/opt/${PROJECT}"
STATE_DIR="/etc/${PROJECT}"
BIN_PATH="/usr/local/bin/${PROJECT}"
MANAGER_PATH="${INSTALL_DIR}/${PROJECT}.sh"

echo "Installing ${PROJECT}..."

mkdir -p "$INSTALL_DIR" "$STATE_DIR"

apt-get update -y
apt-get install -y squid apache2-utils curl ufw

cat > "$MANAGER_PATH" << 'EOF'
#!/usr/bin/env bash

STATE_DIR="/etc/proxy-builder"
DB_FILE="${STATE_DIR}/proxies.db"
PASS_FILE="${STATE_DIR}/passwd"
SQUID_CONF="/etc/squid/squid.conf"

mkdir -p "$STATE_DIR"
touch "$DB_FILE"
touch "$PASS_FILE"

get_ip() {
curl -4 -s ifconfig.me || hostname -I | awk '{print $1}'
}

random_user() {
echo "user$(tr -dc a-z0-9 </dev/urandom | head -c6)"
}

random_pass() {
tr -dc A-Za-z0-9 </dev/urandom | head -c12
}

random_port() {
shuf -i 20000-40000 -n 1
}

rebuild_squid() {
PORTS=$(awk -F: '{print $2}' "$DB_FILE" | sort -n | uniq)

```
cat > "$SQUID_CONF" <<CONF
```

auth_param basic program /usr/lib/squid/basic_ncsa_auth ${PASS_FILE}
auth_param basic realm proxy-builder
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
CONF

```
for p in $PORTS; do
    echo "http_port $p" >> "$SQUID_CONF"
done

systemctl restart squid
```

}

create_proxy() {

```
IP=$(get_ip)
PORT=$(random_port)
USER=$(random_user)
PASS=$(random_pass)

htpasswd -b "$PASS_FILE" "$USER" "$PASS"

echo "$IP:$PORT:$USER:$PASS" >> "$DB_FILE"

rebuild_squid

ufw allow $PORT/tcp >/dev/null 2>&1

echo ""
echo "Proxy created:"
echo "$IP:$PORT:$USER:$PASS"
echo ""
```

}

list_proxies() {
echo ""
echo "Saved proxies:"
cat "$DB_FILE"
echo ""
}

menu() {
clear
echo "=============================="
echo "       PROXY BUILDER"
echo "=============================="
echo "1) Create Random Proxy"
echo "2) List Proxies"
echo "3) Exit"
echo ""
}

while true; do
menu
read -p "Select: " opt
case $opt in
1) create_proxy ;;
2) list_proxies ;;
3) exit ;;
esac
done
EOF

chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$BIN_PATH"

echo ""
echo "Installation completed!"
echo ""
echo "Run command:"
echo "sudo proxy-builder"
echo ""
echo "GitHub:"
echo "https://github.com/harindujayakody/proxy-builder"
echo ""
