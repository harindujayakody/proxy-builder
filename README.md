# ProxyBuilder

> HTTP/HTTPS SOCKS Proxy — One-Click Installer with Username/Password Authentication

![Platform](https://img.shields.io/badge/platform-Ubuntu%20%2F%20Debian-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Powered by](https://img.shields.io/badge/powered%20by-Squid-orange)

---

## Overview

**ProxyBuilder** is a one-click bash installer that sets up fully authenticated HTTP/HTTPS forward proxies on any Ubuntu or Debian VPS. Each proxy gets a unique random port, username, and password — all managed through a simple interactive menu.

Built on [Squid](http://www.squid-cache.org/), the industry-standard proxy daemon.

---

## Features

- ✅ One-command install
- ✅ HTTP & HTTPS (CONNECT tunnel) support
- ✅ Per-proxy username/password authentication (`htpasswd`)
- ✅ Random port generation (20000–40000 range)
- ✅ Batch proxy creation (custom port + quantity)
- ✅ UFW firewall rules managed automatically
- ✅ Delete proxies cleanly (removes user, port, firewall rule)
- ✅ Built-in test commands
- ✅ No-log headers (`X-Forwarded-For`, `Via` stripped)
- ✅ Persistent proxy database at `/etc/proxybuilder/proxies.db`

---

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04 or Debian 10+
- Root or sudo access
- Public IPv4 address

---

## Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/harindujayakody/proxy-builder/main/install-proxy.sh)
```

That's it. After install, launch the manager anytime with:

```bash
sudo proxybuilder
```

---

## Menu Options

```
╔══════════════════════════════════════════════════════════════╗
║                      PROXY BUILDER                          ║
║            HTTP/HTTPS ONE-CLICK INSTALLER                   ║
╚══════════════════════════════════════════════════════════════╝

1) Random Single Proxy     (random port, instant)
2) Choose Port and Quantity
3) Random 5 Proxies
4) List Proxies
5) Test Commands
6) Delete a Proxy
7) Recommended Ports
8) Credits
9) Exit
```

---

## Proxy Format

All proxies are saved to `/etc/proxybuilder/proxies.db` in this format:

```
IP:PORT:USERNAME:PASSWORD
```

Example:
```
203.0.113.10:27453:u_ab3f9c12:xR7kLmN2qP4s
```

---

## Testing a Proxy

After creating a proxy, test it with curl:

```bash
curl -x http://USERNAME:PASSWORD@YOUR_IP:PORT https://ifconfig.me
```

If it returns your server's public IP, the proxy is working.

---

## How It Works

| Component | Detail |
|-----------|--------|
| Proxy daemon | Squid |
| Auth method | HTTP Basic Auth via `htpasswd` |
| Config file | `/etc/squid/squid.conf` (auto-regenerated) |
| Credentials | `/etc/proxybuilder/squid.passwd` |
| Database | `/etc/proxybuilder/proxies.db` |
| Install dir | `/opt/proxybuilder/` |
| Binary | `/usr/local/bin/proxybuilder` |

Every time a proxy is added or removed, Squid config is rebuilt and the service is restarted automatically.

---

## Privacy

ProxyBuilder strips identifying headers from all outgoing requests:

```
forwarded_for off
via off
X-Forwarded-For → removed
Via → removed
```

Your origin server will not see the client's real IP.

---

## Uninstall

```bash
sudo systemctl stop squid
sudo apt-get remove --purge -y squid apache2-utils
sudo rm -rf /opt/proxybuilder /etc/proxybuilder
sudo rm -f /usr/local/bin/proxybuilder
```

---

## Author

**Harindu Jayakody**
GitHub: [harindujayakody](https://github.com/harindujayakody)

---

## License

MIT License. Free to use, modify, and distribute.
