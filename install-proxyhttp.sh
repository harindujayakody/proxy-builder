#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

INSTALL_DIR="/opt/proxyhttp"
STATE_DIR="/etc/proxyhttp"
BIN_PATH="/usr/local/bin/proxyhttp"
MANAGER_PATH="${INSTALL_DIR}/proxyhttp.sh"

mkdir -p "$INSTALL_DIR" "$STATE_DIR"

apt-get update -y
apt-get install -y curl openssl apache2-utils ufw gawk sed grep coreutils squid

cat > "$MANAGER_PATH" <<'MANAGER_EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/etc/proxyhttp"
DB_FILE="${STATE_DIR}/proxies.db"
PASSWD_FILE="${STATE_DIR}/passwd"
SQUID_CONF="/etc/squid/squid.conf"
PROJECT_NAME="ProxyHTTP"
PROJECT_REPO="https://github.com/YOUR_GITHUB_USERNAME/proxyhttp"
PROJECT_AUTHOR="YOUR_NAME"

mkdir -p "$STATE_DIR"
touch "$DB_FILE"
touch "$PASSWD_FILE"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"
DIM="\033[2m"

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Please run with sudo: sudo proxyhttp${RESET}"
    exit 1
  fi
}

line() {
  printf '%*s\n' "${COLUMNS:-70}" '' | tr ' ' '─'
}

title() {
  clear
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}${BOLD}║                        PROXYHTTP                            ║${RESET}"
  echo -e "${CYAN}${BOLD}║            HTTP / HTTPS ONE-CLICK INSTALLER                 ║${RESET}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
  echo
  echo -e "${DIM}GitHub: ${PROJECT_REPO}${RESET}"
  echo -e "${DIM}Created by: ${PROJECT_AUTHOR}${RESET}"
  echo
}

info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
fail() { echo -e "${RED}[ERR]${RESET}  $*"; }

pause() {
  echo
  read -rp "Press Enter to continue..." _
}

get_public_ip() {
  local ip
  ip="$(curl -4 -s https://ifconfig.me || true)"
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return
  fi
  hostname -I | awk '{print $1}'
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

add_auth_user() {
  local user="$1" pass="$2"
  if grep -q "^${user}:" "$PASSWD_FILE" 2>/dev/null; then
    htpasswd -b "$PASSWD_FILE" "$user" "$pass" >/dev/null 2>&1
  else
    htpasswd -b "$PASSWD_FILE" "$user" "$pass" >/dev/null 2>&1
  fi
}

append_proxy() {
  local ip="$1" port="$2" user="$3" pass="$4"
  echo "${ip}:${port}:${user}:${pass}" >> "$DB_FILE"
}

count_proxies() {
  grep -c . "$DB_FILE" 2>/dev/null || true
}

rebuild_squid() {
  local ports
  ports="$(awk -F: 'NF>=4 {print $2}' "$DB_FILE" | sort -n | uniq)"

  cp "$SQUID_CONF" "${SQUID_CONF}.bak.$(date +%s)" 2>/dev/null || true

  {
    echo "auth_param basic program /usr/lib/squid/basic_ncsa_auth ${PASSWD_FILE}"
    echo "auth_param basic realm ProxyHTTP"
    echo "acl authenticated proxy_auth REQUIRED"
    echo "http_access allow authenticated"
    echo "http_access deny all"
    echo
    while read -r port; do
      [[ -n "$port" ]] && echo "http_port ${port}"
    done <<< "$ports"
    echo
    echo "via off"
    echo "forwarded_for delete"
    echo "request_header_access X-Forwarded-For deny all"
    echo "request_header_access Via deny all"
    echo "cache deny all"
    echo "dns_v4_first on"
    echo "visible_hostname proxyhttp"
  } > "$SQUID_CONF"

  systemctl enable squid >/dev/null 2>&1 || true
  systemctl restart squid
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
  echo -e "${BOLD}Password File:${RESET} ${PASSWD_FILE}"
  echo -e "${BOLD}Command      :${RESET} sudo proxyhttp"
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

  add_auth_user "$user" "$pass"
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

  ok "Creating ${count} proxies..."
  echo

  for ((i=0; i<count; i++)); do
    port=$((start_port + i))
    user="$(pick_unique_user)"
    pass="$(random_pass)"
    add_auth_user "$user" "$pass"
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

  ok "Creating 5 random proxies..."
  echo

  for ((i=1; i<=5; i++)); do
    port="$(pick_random_port)"
    user="$(pick_unique_user)"
    pass="$(random_pass)"
    add_auth_user "$user" "$pass"
    append_proxy "$ip" "$port" "$user" "$pass"
    ports+=("$port")
    show_proxy_result "$ip" "$port" "$user" "$pass"
  done

  rebuild_squid
  open_ports "${ports[@]}"
  echo
  ok "Created 5 random proxies"
}

list_proxies() {
  local total
  total="$(count_proxies)"

  echo
  echo -e "${MAGENTA}${BOLD}Saved Proxies${RESET}"
  line

  if [[ "$total" -eq 0 ]]; then
    warn "No proxies created yet."
    return
  fi

  cat "$DB_FILE"
  echo
  ok "Total proxies: ${total}"
}

show_usage_example() {
  local ip
  ip="$(get_public_ip)"
  echo
  echo -e "${CYAN}${BOLD}Example usage:${RESET}"
  echo "HTTP_PROXY=http://USER:PASS@${ip}:PORT"
  echo "HTTPS_PROXY=http://USER:PASS@${ip}:PORT"
  echo
  echo "curl -x http://USER:PASS@${ip}:PORT https://api.ipify.org"
  echo
}

show_recommended_ports() {
  echo
  echo -e "${CYAN}${BOLD}Recommended ports:${RESET} 3128, 8080, 8888, 20000-40000"
  echo -e "${CYAN}${BOLD}Avoid ports:${RESET} 1-1023, 22, 25, 53, 80, 443, 3306, 5432"
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
  echo -e "${BOLD}1)${RESET} Random Single Proxy Generate"
  echo -e "${BOLD}2)${RESET} Choose Port and Quantity"
  echo -e "${BOLD}3)${RESET} Random 5 Proxies"
  echo -e "${BOLD}4)${RESET} List / Show Created Proxies"
  echo -e "${BOLD}5)${RESET} Usage Example"
  echo -e "${BOLD}6)${RESET} Recommended Ports"
  echo -e "${BOLD}7)${RESET} Credits"
  echo -e "${BOLD}8)${RESET} Exit"
  echo
}

main() {
  require_root
  while true; do
    menu
    read -rp "Select option [1-8]: " choice
    case "$choice" in
      1) create_one_random; pause ;;
      2) create_custom_batch; pause ;;
      3) create_random_five; pause ;;
      4) list_proxies; pause ;;
      5) show_usage_example; pause ;;
      6) show_recommended_ports; pause ;;
      7) show_credits; pause ;;
      8) exit 0 ;;
      *) fail "Invalid option"; sleep 1 ;;
    esac
  done
}

main
MANAGER_EOF

chmod +x "$MANAGER_PATH"
ln -sf "$MANAGER_PATH" "$BIN_PATH"

echo
echo "Installed successfully."
echo "Project : ProxyHTTP"
echo "Command : sudo proxyhttp"
echo "GitHub  : https://github.com/YOUR_GITHUB_USERNAME/proxyhttp"
echo
