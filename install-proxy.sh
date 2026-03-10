#!/usr/bin/env bash
set -e

PROJECT="proxy-builder"
INSTALL_DIR="/opt/${PROJECT}"
STATE_DIR="/etc/${PROJECT}"
BIN="/usr/local/bin/${PROJECT}"
MANAGER="${INSTALL_DIR}/${PROJECT}.sh"

echo "Installing ${PROJECT}..."

apt-get update -y
apt-get install -y squid apache2-utils curl ufw

mkdir -p "$INSTALL_DIR"
mkdir -p "$STATE_DIR"

cat > "$MANAGER" <<'EOF'
#!/usr/bin/env bash

STATE_DIR="/etc/proxy-builder"
DB_FILE="${STATE_DIR}/proxies.db"
PASS_FILE="${STATE_DIR}/passwd"
SQUID_CONF="/etc/squid/squid.conf"

mkdir -p "$STATE_DIR"
touch "$DB_FILE"
touch "$PASS_FILE"

get_ip(){
curl -4 -s ifconfig.me || hostname -I | awk '{print $1}'
}

random_user(){
echo "u$(tr -dc a-z0-9 </dev/urandom | head -c6)"
}

random_pass(){
tr -dc A-Za-z0-9 </dev/urandom | head -c12
}

random_port(){
shuf -i 20000-40000 -n 1
}

rebuild_squid(){

PORTS=$(awk -F: '{print $2}' "$DB_FILE" | sort -u)

cat > "$SQUID_CONF" <<CONF
auth_param basic program /usr/lib/squid/basic_ncsa_auth $PASS_FILE
auth_param basic realm proxy-builder
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
CONF

for p in $PORTS
do
echo "http_port $p" >> $SQUID_CONF
done

systemctl restart squid
}

create_one(){

IP=$(get_ip)
PORT=$(random_port)
USER=$(random_user)
PASS=$(random_pass)

htpasswd -b "$PASS_FILE" "$USER" "$PASS"

echo "$IP:$PORT:$USER:$PASS" >> "$DB_FILE"

rebuild_squid

ufw allow $PORT/tcp >/dev/null 2>&1

echo ""
echo "Proxy Created"
echo "$IP:$PORT:$USER:$PASS"
echo ""
}

create_batch(){

read -p "Start port: " START
read -p "How many proxies: " COUNT

IP=$(get_ip)

for ((i=0;i<COUNT;i++))
do

PORT=$((START+i))
USER=$(random_user)
PASS=$(random_pass)

htpasswd -b "$PASS_FILE" "$USER" "$PASS"

echo "$IP:$PORT:$USER:$PASS" >> "$DB_FILE"

ufw allow $PORT/tcp >/dev/null 2>&1

echo "$IP:$PORT:$USER:$PASS"

done

rebuild_squid
}

create_random5(){

IP=$(get_ip)

for i in {1..5}
do

PORT=$(random_port)
USER=$(random_user)
PASS=$(random_pass)

htpasswd -b "$PASS_FILE" "$USER" "$PASS"

echo "$IP:$PORT:$USER:$PASS" >> "$DB_FILE"

ufw allow $PORT/tcp >/dev/null 2>&1

echo "$IP:$PORT:$USER:$PASS"

done

rebuild_squid
}

list_proxies(){

echo ""
echo "Saved Proxies"
echo "----------------------"
cat "$DB_FILE"
echo ""
}

menu(){

clear
echo "=============================="
echo "        PROXY BUILDER"
echo "=============================="
echo "1) Create Random Proxy"
echo "2) Create 5 Random Proxies"
echo "3) Custom Batch Proxies"
echo "4) List Proxies"
echo "5) Exit"
echo ""
}

while true
do

menu

read -p "Select option: " opt

case $opt in

1. create_one ;;
2. create_random5 ;;
3. create_batch ;;
4. list_proxies ;;
5. exit ;;

esac

read -p "Press Enter to continue"

done

EOF

chmod +x "$MANAGER"

ln -sf "$MANAGER" "$BIN"

echo ""
echo "Installation complete"
echo ""
echo "Run:"
echo "sudo proxy-builder"
echo ""
echo "GitHub:"
echo "https://github.com/harindujayakody/proxy-builder"
echo ""
