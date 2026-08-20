#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

REPO_RAW="https://raw.githubusercontent.com/Nanda-N4/installer/main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m'

MYIP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)

clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${WHITE}          ★ N4 VPN SERVER INTERACTIVE INSTALLER ★        ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"

# 1. Interactive Host / Domain Prompt
echo -e "\n${YELLOW}--- [1/2] SSH WS / CDN DOMAIN CONFIGURATION ---${NC}"
echo -e " VPS တွင် အသုံးပြုမည့် Domain (သို့မဟုတ်) Cloudflare Subdomain ထည့်ပါ။"
echo -e " မရှိပါက Enter နှိပ်ပါ (Server IP: ${GREEN}$MYIP${NC} ကို အလိုအလျောက် သုံးပါမည်)။"
read -p " Enter Domain / IP [Default: $MYIP]: " input_domain

if [ -z "$input_domain" ]; then
    HOST_DOMAIN="$MYIP"
else
    HOST_DOMAIN="$input_domain"
fi
echo "$HOST_DOMAIN" > /etc/vps-domain.txt
echo -e "${GREEN}[✔] Host Domain Configured:${NC} $HOST_DOMAIN"

# 2. Interactive SlowDNS NS Prompt & Live Validator
echo -e "\n${YELLOW}--- [2/2] SLOWDNS PROTOCOL SETUP ---${NC}"
read -p " SlowDNS ကို Server တွင် အသုံးပြုလိုပါသလား? [y/N]: " enable_dns
ENABLE_SLOWDNS=0

mkdir -p /etc/slowdns

if [[ "$enable_dns" =~ ^[Yy]$ ]]; then
    echo -e "\n Cloudflare တွင် ချိတ်ဆက်ထားသော NS Subdomain (e.g., ns1.yourdomain.com) ကို ထည့်ပါ။"
    read -p " Enter NS Subdomain: " ns_input
    
    if [ -n "$ns_input" ]; then
        echo -e " [*] Verifying NS Subdomain resolution..."
        # DNS Resolution Check
        RESOLVED_IP=$(dig +short "$ns_input" 2>/dev/null | tail -n1)
        if [ -z "$RESOLVED_IP" ]; then
            RESOLVED_IP=$(getent hosts "$ns_input" | awk '{print $1}')
        fi

        if [ -n "$RESOLVED_IP" ]; then
            echo -e "${GREEN}[✔] NS Subdomain is VALID & ACTIVE! (Points to: $RESOLVED_IP)${NC}"
            echo "$ns_input" > /etc/slowdns/nsdomain.txt
            ENABLE_SLOWDNS=1
        else
            echo -e "${RED}[!] WARNING: '$ns_input' is INVALID or Not Resolving yet!${NC}"
            echo -e "${YELLOW}[!] SlowDNS will stay DISABLED for now. You can start it later via Menu.${NC}"
            rm -f /etc/slowdns/nsdomain.txt
        fi
    else
        echo -e "${YELLOW}[*] No NS Subdomain entered. SlowDNS skipped.${NC}"
        rm -f /etc/slowdns/nsdomain.txt
    fi
else
    echo -e "${YELLOW}[*] SlowDNS skipped. Server will run SSH WS & Dropbear only.${NC}"
    rm -f /etc/slowdns/nsdomain.txt
fi

# 3. Base Cleanup & Free Port 53
echo -e "\n${YELLOW}[*] Cleaning previous services & liberating Port 53...${NC}"
systemctl stop slowdns ws-dropbear dropbear 2>/dev/null
systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null
systemctl mask systemd-resolved 2>/dev/null

rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

fuser -k 53/udp 2>/dev/null
fuser -k 53/tcp 2>/dev/null

# 4. Dependencies
echo -e "${YELLOW}[*] Installing Core System Packages...${NC}"
apt-get update -y && apt-get upgrade -y
apt-get install -y dropbear python3 screen curl wget net-tools lsof jq iptables bc dnsutils psmisc ca-certificates
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells

# 5. Dropbear Internal Configuration
echo -e "${YELLOW}[*] Configuring Dropbear SSH Engine...${NC}"
mkdir -p /etc/dropbear
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null

cat << 'DBCONF' > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-R -W 65536"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DBCONF

echo "=== VIP VPN SERVER ===" > /etc/issue.net
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable dropbear
systemctl restart dropbear

# 6. Fetch Components from GitHub
echo -e "${YELLOW}[*] Downloading Verified Components from GitHub...${NC}"
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

# Configure WebSocket Service
cat << 'SERVICE' > /etc/systemd/system/ws-dropbear.service
[Unit]
Description=SSH & Payload WebSocket Proxy Engine
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Configure SlowDNS Service if Verified
if [ $ENABLE_SLOWDNS -eq 1 ]; then
    cat << DNSSERVICE > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS DNSTT Server Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/slowdns
ExecStart=/etc/slowdns/dnstt-server -udp 0.0.0.0:53 -privkey-file /etc/slowdns/server.key $ns_input 127.0.0.1:109
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
DNSSERVICE
    systemctl daemon-reload
    systemctl enable slowdns
    systemctl restart slowdns
fi

# 7. Start Services & Open Firewall
systemctl daemon-reload
systemctl enable ws-dropbear
systemctl restart ws-dropbear

iptables -F
iptables -I INPUT -p tcp --dport 143 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 442 -j ACCEPT
iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
iptables -I INPUT -p udp --dport 53 -j ACCEPT

clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${WHITE}            VPN SUITE INSTALLATION COMPLETE!             ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e " ${WHITE}Configured Host Domain :${NC} ${YELLOW}$HOST_DOMAIN${NC}"
if [ $ENABLE_SLOWDNS -eq 1 ]; then
    echo -e " ${WHITE}SlowDNS Status         :${NC} ${GREEN}● ACTIVE (${ns_input})${NC}"
else
    echo -e " ${WHITE}SlowDNS Status         :${NC} ${RED}○ DISABLED (Configure later via menu)${NC}"
fi
echo -e " Open panel anytime by typing: ${YELLOW}menu${NC}"
