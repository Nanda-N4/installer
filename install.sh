#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

REPO_RAW="https://raw.githubusercontent.com/Nanda-N4/installer/main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${WHITE}        ONE-CLICK VPN & SLOWDNS MASTER INSTALLER          ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"

# 1. Total Cleanup
echo -e "\n${YELLOW}[1/5] Cleaning up old services...${NC}"
systemctl stop slowdns ws-dropbear dropbear 2>/dev/null
rm -rf /etc/slowdns
mkdir -p /etc/slowdns

# 2. Freeing Port 53
echo -e "${YELLOW}[2/5] Liberating UDP/TCP Port 53...${NC}"
systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null
systemctl mask systemd-resolved 2>/dev/null
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fuser -k 53/udp 2>/dev/null
fuser -k 53/tcp 2>/dev/null

# 3. Base Packages
echo -e "${YELLOW}[3/5] Installing Required Packages...${NC}"
apt-get update -y && apt-get upgrade -y
apt-get install -y dropbear python3 screen curl wget net-tools lsof jq iptables bc dnsutils psmisc ca-certificates
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells

# 4. Configure Dropbear
echo -e "${YELLOW}[4/5] Configuring Dropbear SSH Server...${NC}"
cat << 'DBCONF' > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 143 -p 109"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DBCONF

echo "=== VIP VPN SERVER ===" > /etc/issue.net
systemctl enable dropbear
systemctl restart dropbear

# 5. Fetch all verified components directly from your GitHub repo
echo -e "${YELLOW}[5/5] Downloading all components from Nanda-N4/installer...${NC}"
curl -sSL "${REPO_RAW}/ws-proxy.py" -o /usr/local/bin/ws-proxy.py
chmod +x /usr/local/bin/ws-proxy.py

curl -sSL "${REPO_RAW}/dnstt-server" -o /etc/slowdns/dnstt-server
chmod 755 /etc/slowdns/dnstt-server

curl -sSL "${REPO_RAW}/server.key" -o /etc/slowdns/server.key
curl -sSL "${REPO_RAW}/server.pub" -o /etc/slowdns/server.pub
chmod 600 /etc/slowdns/server.key

curl -sSL "${REPO_RAW}/menu.sh" -o /usr/local/bin/menu
chmod +x /usr/local/bin/menu
echo "alias menu='/usr/local/bin/menu'" >> ~/.bashrc

# Setup WebSocket systemd service
cat << 'SERVICE' > /etc/systemd/system/ws-dropbear.service
[Unit]
Description=SSH WebSocket Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable ws-dropbear
systemctl restart ws-dropbear

clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${WHITE}            VPN SUITE INSTALLATION COMPLETE!             ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e " Open panel by typing: ${YELLOW}menu${NC}"
