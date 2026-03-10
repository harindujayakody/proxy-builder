#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

INSTALL_DIR="/opt/httphell"
STATE_DIR="/etc/httphell"
BIN_PATH="/usr/local/bin/httphell"
MANAGER_PATH="${INSTALL_DIR}/httphell.sh"

mkdir -p "$INSTALL_DIR" "$STATE_DIR"

apt-get update -y
apt-get install -y curl openssl ufw apache2-utils squid

cat > "$MANAGER_PATH" <<'MANAGER_EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/etc/httphell"
DB_FILE="${STATE_DIR}/proxies.db"
HTPASSWD_FILE="${STATE_DIR}/squid.passwd"
CONF_FILE="/etc/squid/squid.conf"
PROJECT_NAME="HTTPHell"
PROJECT_REPO="https://github.com/harindujayakody/proxyhell"
PROJECT_AUTHOR="Harindu Jayakody"

mkdir -p "$STATE_DIR"
touch "$DB_FILE"
touch "$HTPASSWD_FILE"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
DIM="\033[2m"
BOLD="\033[1m"
RESET="\033[0m"

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Please run with sudo: sudo httphell${RESET}"
    exit 1
  fi
}

line() {
  printf '%*s\n' "${COLUMNS:-70}" '' | tr ' ' '─'
}

title() {
  clear
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}║                        HTTPHELL                             ║${RESET}"
  echo -e "${CYAN}${BOLD}║            HTTP/HTTPS ONE-CLICK INSTALLER                   ║${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo
  echo -e "${DIM}GitHub: ${PROJECT_REPO}${RESET}"
  echo -e "${DIM}Created by: ${PROJECT_AUTHOR}${RESET}"
  echo
}

info()    { echo -e "${BLUE}[INFO]${RESET} $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail()    { echo -e "${RED}[ERR]${RESET}  $*"; }

pause() {
  echo
  read -rp "Press Enter to continue..." _
}

get_public_ip() {
  local ip
  ip="$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(ip -4 addr show "$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)" \
      | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
  fi
  echo "$ip"
}

random_user() {
  echo "u_$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)"
}

random_pass() {
  openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 14
}

port_in_db() {
  local port="$1"
  awk -F: -v p="$port" '$2 == p { found=1 } END { exit(found ? 0 : 1) }' "$DB_FILE"
}

user_in_db() {
  local user="$1"
  awk -F: -v u="$user" '$3 == u { found=1 } END { exit(found ? 0 : 1) }' "$DB_FILE"
}

pick_random_port() {
  local p
  while true; do
    p="$(shuf -i 20000-40000 -n 1)"
    if ! port_in_db "$p"; then
      echo "$p"
      return
    fi
  done
}

pick_unique_user() {
  local u
  while true; do
    u="$(random_user)"
    if ! user_in_db "$u"; then
      echo "$u"
      return
    fi
  done
}

append_proxy() {
  local ip="$1" port="$2" user="$3" pass="$4"
  echo "${ip}:${port}:${user}:${pass}" >> "$DB_FILE"
}

count_proxies() {
  grep -c . "$DB_FILE" 2>/dev/null || true
}

add_htpasswd_user() {
  local user="$1" pass="$2"
  htpasswd -b "$HTPASSWD_FILE" "$user" "$pass" >/dev/null 2>&1
}

remove_htpasswd_user() {
  local user="$1"
  htpasswd -D "$HTPASSWD_FILE" "$user" >/dev/null 2>&1 || true
}

rebuild_squid() {
  cp "$CONF_FILE" "${CONF_FILE}.bak.$(date +%s)" 2>/dev/null || true

  {
    echo "# HTTPHell - Auto-generated Squid config"
    echo "# Do not edit manually"
    echo
    echo "# Basic authentication"
    echo "auth_param basic program /usr/lib/squid/basic_ncsa_auth ${HTPASSWD_FILE}"
    echo "auth_param basic children 10"
    echo "auth_param basic realm HTTPHell Proxy"
    echo "auth_param basic credentialsttl 2 hours"
    echo
    echo "acl authenticated proxy_auth REQUIRED"
    echo "http_access allow authenticated"
    echo "http_access deny all"
    echo
    echo "# Transparent HTTPS tunneling"
    echo "https_port 0 disabled"
    echo
    echo "# Enable CONNECT method for HTTPS"
    echo "acl CONNECT method CONNECT"
    echo
    # Write one http_port per proxy
    awk -F: 'NF>=4 { print "http_port " $2 }' "$DB_FILE"
    echo
    echo "# General settings"
    echo "forwarded_for off"
    echo "via off"
    echo "request_header_access X-Forwarded-For deny all"
    echo "request_header_access Via deny all"
    echo
    echo "coredump_dir /var/spool/squid"
    echo "refresh_pattern ^ftp:          1440  20% 10080"
    echo "refresh_pattern ^gopher:       1440   0% 1440"
    echo "refresh_pattern -i (/cgi-bin/|\?) 0   0% 0"
    echo "refresh_pattern .              0     20% 4320"
    echo
    echo "dns_v4_first on"
    echo "tcp_outgoing_address 0.0.0.0"
  } > "$CONF_FILE"

  squid -k parse 2>/dev/null && {
    systemctl enable squid >/dev/null 2>&1 || true
    systemctl restart squid
  } || {
    fail "Squid config parse error. Restoring backup..."
    cp "${CONF_FILE}.bak."* "$CONF_FILE" 2>/dev/null || true
    systemctl restart squid || true
  }
}

open_ports() {
  local p
  for p in "$@"; do
    ufw allow "${p}/tcp" >/dev/null 2>&1 || true
  done
}

show_proxy_result() {
  local ip="$1" port="$2" user="$3" pass="$4"
  echo -e "${GREEN}${BOLD}${ip}:${port}:${user}:${pass}${RESET}"
  echo -e "  ${DIM}curl -x http://${user}:${pass}@${ip}:${port} https://ifconfig.me${RESET}"
}

show_summary() {
  local total pub_ip
  total="$(count_proxies)"
  pub_ip="$(get_public_ip)"

  echo
  line
  echo -e "${BOLD}Project      :${RESET} ${PROJECT_NAME}"
  echo -e "${BOLD}Public IPv4  :${RESET} ${pub_ip:-N/A}"
  echo -e "${BOLD}Total Proxies:${RESET} ${total}"
  echo -e "${BOLD}Database     :${RESET} ${DB_FILE}"
  echo -e "${BOLD}Command      :${RESET} sudo httphell"
  echo -e "${BOLD}GitHub       :${RESET} ${PROJECT_REPO}"
  line
  echo
}

create_one_random() {
  local ip port user pass

  ip="$(get_public_ip)"
  [[ -z "$ip" ]] && { fail "No public IPv4 detected."; return; }

  port="$(pick_random_port)"
  user="$(pick_unique_user)"
  pass="$(random_pass)"

  add_htpasswd_user "$user" "$pass"
  append_proxy "$ip" "$port" "$user" "$pass"
  rebuild_squid
  open_ports "$port"

  ok "Random single HTTP/HTTPS proxy created"
  echo
  show_proxy_result "$ip" "$port" "$user" "$pass"
}

create_custom_batch() {
  local count start_port end_port ip
  read -rp "Enter start port: " start_port
  read -rp "How many proxies: " count

  if ! [[ "$start_port" =~ ^[0-9]+$ ]] || (( start_port < 1024 || start_port > 65000 )); then
    fail "Start port must be between 1024 and 65000."
    return
  fi

  if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count < 1 || count > 500 )); then
    fail "Count must be between 1 and 500."
    return
  fi

  end_port=$((start_port + count - 1))
  if (( end_port > 65535 )); then
    fail "Port range exceeds 65535."
    return
  fi

  ip="$(get_public_ip)"
  [[ -z "$ip" ]] && { fail "No public IPv4 detected."; return; }

  local i port user pass
  local ports=()

  for ((i=0; i<count; i++)); do
    port=$((start_port + i))
    if port_in_db "$port"; then
      fail "Port already exists: $port"
      return
    fi
  done

  ok "Creating ${count} HTTP/HTTPS proxies..."
  echo

  for ((i=0; i<count; i++)); do
    port=$((start_port + i))
    user="$(pick_unique_user)"
    pass="$(random_pass)"
    add_htpasswd_user "$user" "$pass"
    append_proxy "$ip" "$port" "$user" "$pass"
    ports+=("$port")
    show_proxy_result "$ip" "$port" "$user" "$pass"
  done

  rebuild_squid
  open_ports "${ports[@]}"
  echo
  ok "Created ${count} proxies on ports ${start_port}-${end_port}"
}

create_random_five() {
  local ip user pass port
  local ports=()
  local i

  ip="$(get_public_ip)"
  [[ -z "$ip" ]] && { fail "No public IPv4 detected."; return; }

  ok "Creating 5 random HTTP/HTTPS proxies..."
  echo

  for ((i=1; i<=5; i++)); do
    port="$(pick_random_port)"
    user="$(pick_unique_user)"
    pass="$(random_pass)"
    add_htpasswd_user "$user" "$pass"
    append_proxy "$ip" "$port" "$user" "$pass"
    ports+=("$port")
    show_proxy_result "$ip" "$port" "$user" "$pass"
  done

  rebuild_squid
  open_ports "${ports[@]}"
  echo
  ok "Created 5 random proxies"
}

delete_proxy() {
  local total
  total="$(count_proxies)"

  if [[ "$total" -eq 0 ]]; then
    warn "No proxies to delete."
    return
  fi

  echo
  echo -e "${MAGENTA}${BOLD}Select proxy to delete:${RESET}"
  line
  nl -ba "$DB_FILE"
  echo
  read -rp "Enter line number to delete (0 to cancel): " lineno

  if [[ "$lineno" == "0" ]]; then return; fi

  if ! [[ "$lineno" =~ ^[0-9]+$ ]] || (( lineno < 1 || lineno > total )); then
    fail "Invalid selection."
    return
  fi

  local entry user port
  entry="$(sed -n "${lineno}p" "$DB_FILE")"
  user="$(echo "$entry" | cut -d: -f3)"
  port="$(echo "$entry" | cut -d: -f2)"

  remove_htpasswd_user "$user"
  sed -i "${lineno}d" "$DB_FILE"

  ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true

  rebuild_squid
  ok "Deleted proxy on port ${port} (user: ${user})"
}

list_proxies() {
  local total
  total="$(count_proxies)"

  echo
  echo -e "${MAGENTA}${BOLD}Saved HTTP/HTTPS Proxies${RESET}"
  line

  if [[ "$total" -eq 0 ]]; then
    warn "No proxies created yet."
    return
  fi

  local ip port user pass
  while IFS=: read -r ip port user pass; do
    echo -e "${GREEN}${ip}:${port}:${user}:${pass}${RESET}"
    echo -e "  ${DIM}curl -x http://${user}:${pass}@${ip}:${port} https://ifconfig.me${RESET}"
  done < "$DB_FILE"

  echo
  ok "Total proxies: ${total}"
}

show_test_commands() {
  local total
  total="$(count_proxies)"

  if [[ "$total" -eq 0 ]]; then
    warn "No proxies created yet."
    return
  fi

  echo
  echo -e "${CYAN}${BOLD}Test Commands (curl)${RESET}"
  line

  local ip port user pass
  while IFS=: read -r ip port user pass; do
    echo -e "${BOLD}Port ${port}:${RESET}"
    echo "  curl -x http://${user}:${pass}@${ip}:${port} https://ifconfig.me"
    echo "  curl -x https://${user}:${pass}@${ip}:${port} https://ifconfig.me"
    echo
  done < "$DB_FILE"
}

show_recommended_ports() {
  echo
  echo -e "${CYAN}${BOLD}Recommended ports:${RESET} 3128, 8080, 8888, 20000-40000"
  echo -e "${CYAN}${BOLD}Avoid ports:${RESET} 1-1023, 22, 25, 53, 80, 443, 3306, 5432"
  echo
  echo -e "${CYAN}${BOLD}Protocol info:${RESET}"
  echo "  HTTP  - Plain HTTP proxy, works with http:// and https:// via CONNECT"
  echo "  HTTPS - Same port handles both; clients use CONNECT method for TLS"
  echo
}

show_credits() {
  echo
  line
  echo -e "${BOLD}Project :${RESET} ${PROJECT_NAME}"
  echo -e "${BOLD}Author  :${RESET} ${PROJECT_AUTHOR}"
  echo -e "${BOLD}GitHub  :${RESET} ${PROJECT_REPO}"
  line
  echo
}

menu() {
  title
  show_summary
  echo -e "${BOLD}1)${RESET} Random Single Proxy Generate ${DIM}(recommended random port)${RESET}"
  echo -e "${BOLD}2)${RESET} Choose Port and Quantity"
  echo -e "${BOLD}3)${RESET} Random 5 Proxies"
  echo -e "${BOLD}4)${RESET} List / Show Created Proxies"
  echo -e "${BOLD}5)${RESET} Test Commands"
  echo -e "${BOLD}6)${RESET} Delete a Proxy"
  echo -e "${BOLD}7)${RESET} Recommended Ports"
  echo -e "${BOLD}8)${RESET} Credits"
  echo -e "${BOLD}9)${RESET} Exit"
  echo
}

main() {
  require_root
  while true; do
    menu
    read -rp "Select option [1-9]: " choice
    case "$choice" in
      1) create_one_random; pause ;;
      2) create_custom_batch; pause ;;
      3) create_random_five; pause ;;
      4) list_proxies; pause ;;
      5) show_test_commands; pause ;;
      6) delete_proxy; pause ;;
      7) show_recommended_ports; pause ;;
      8) show_credits; pause ;;
      9) exit 0 ;;
      *) fail "Invalid option"; sleep 1 ;;
    esac
  done
}

main
MANAGER_EOF

chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$BIN_PATH"

echo
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                        HTTPHELL                             ║"
echo "║            HTTP/HTTPS ONE-CLICK INSTALLER                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo
echo "Installed successfully."
echo "Project : HTTPHell"
echo "Command : sudo httphell"
echo "GitHub  : https://github.com/harindujayakody/proxyhell"
echo
echo "Run: sudo httphell"
echo
