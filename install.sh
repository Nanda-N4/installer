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

# 1. System File Limits Tuning (Anti-Crash)
echo -e "\n${YELLOW}[*] Tuning System Limits for Heavy Load...${NC}"
cat << 'EOF' >> /etc/security/limits.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
sysctl -w fs.file-max=65535 >/dev/null 2>&1

# 2. Host / Domain Prompt
echo -e "\n${YELLOW}--- [1/2] SSH WS / CDN DOMAIN CONFIGURATION ---${NC}"
echo -e " VPS တွင် အသုံးပြုမည့် Domain (သို့မဟုတ်) Subdomain ထည့်ပါ။"
echo -e " မရှိပါက Enter နှိပ်ပါ (Server IP: ${GREEN}$MYIP${NC} ကို အလိုအလျောက် သုံးပါမည်)။"
read -p " Enter Domain / IP [Default: $MYIP]: " input_domain

if [ -z "$input_domain" ]; then
    HOST_DOMAIN="$MYIP"
else
    HOST_DOMAIN="$input_domain"
fi
echo "$HOST_DOMAIN" > /etc/vps-domain.txt
echo -e "${GREEN}[✔] Host Domain Configured:${NC} $HOST_DOMAIN"

# 3. SlowDNS NS Setup Prompt (Direct Run - No Restriction)
echo -e "\n${YELLOW}--- [2/2] SLOWDNS PROTOCOL SETUP ---${NC}"
read -p " SlowDNS ကို Server တွင် အသုံးပြုလိုပါသလား? [y/N]: " enable_dns
ENABLE_SLOWDNS=0

mkdir -p /etc/slowdns

if [[ "$enable_dns" =~ ^[Yy]$ ]]; then
    read -p " Enter NS Subdomain (e.g., ns2.n4vpn.xyz): " ns_input
    
    if [ -n "$ns_input" ]; then
        echo "$ns_input" > /etc/slowdns/nsdomain.txt
        ENABLE_SLOWDNS=1
        echo -e "${GREEN}[✔] SlowDNS NS Configured:${NC} $ns_input"
    else
        echo -e "${YELLOW}[*] No NS Subdomain entered. SlowDNS skipped.${NC}"
        rm -f /etc/slowdns/nsdomain.txt
    fi
else
    echo -e "${YELLOW}[*] SlowDNS skipped.${NC}"
    rm -f /etc/slowdns/nsdomain.txt
fi

# 4. Clean Up & Free Port 53
echo -e "\n${YELLOW}[*] Freeing Port 53 & Stopping Old Services...${NC}"
systemctl stop slowdns ws-dropbear dropbear vpn-watchdog 2>/dev/null
systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null
systemctl mask systemd-resolved 2>/dev/null

rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

fuser -k 53/udp 2>/dev/null
fuser -k 53/tcp 2>/dev/null

# 5. Core Packages
echo -e "${YELLOW}[*] Installing Core Packages & Tools...${NC}"
apt-get update -y && apt-get upgrade -y
apt-get install -y dropbear python3 screen curl wget net-tools lsof jq iptables iptables-persistent bc dnsutils psmisc ca-certificates
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells

# 6. Banner Setup (With Telegram Contact)
echo -e "${YELLOW}[*] Setting up VPN Banner...${NC}"
cat << 'EOF' > /etc/issue.net
<p style="text-align: center;">
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#ff007f"><b>★ WELCOME TO N4 VPN PREMIUM SERVER ★</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#00ff00"><b>● STATUS: CONNECTED & ENCRYPTED</b></font><br>
<font color="#ffaa00"><b>● SPEED: UNLIMITED HIGH SPEED</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#ffffff"><b>✖ NO DDOS / NO SPAM / NO FRAUD</b></font><br>
<font color="#ffffff"><b>✖ NO TORRENT / NO ILLEGAL ACTIVITIES</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#38b6ff"><b>✈ Telegram Channel : </b></font><font color="#ffff00"><b>https://t.me/n4vpn</b></font><br>
<font color="#38b6ff"><b>✈ Support Admin    : </b></font><font color="#ffff00"><b>https://t.me/n4nd404</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font>
</p>
EOF

# 7. Dropbear Internal Configuration (Port 109, Max CLI Increased)
echo -e "${YELLOW}[*] Configuring High-Load Dropbear SSH...${NC}"
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

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable dropbear
systemctl restart dropbear

# 8. Fetch Components from GitHub
echo -e "${YELLOW}[*] Downloading Components from GitHub...${NC}"
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

# 9. Setup WebSocket Service with Auto-Restart
cat << 'SERVICE' > /etc/systemd/system/ws-dropbear.service
[Unit]
Description=SSH & Payload WebSocket Proxy Engine
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

# 10. Setup SlowDNS Service with Auto-Restart
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
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
DNSSERVICE
    systemctl daemon-reload
    systemctl enable slowdns
    systemctl restart slowdns
fi

# 11. Auto-Recovery Watchdog Daemon Service
echo -e "${YELLOW}[*] Installing Auto-Recovery Watchdog...${NC}"
cat << 'EOF' > /usr/local/bin/vpn-watchdog.sh
#!/bin/bash
while true; do
    # Check Dropbear
    if ! pgrep -x "dropbear" > /dev/null; then
        systemctl restart dropbear 2>/dev/null
    fi

    # Check WS-Proxy
    if ! systemctl is-active --quiet ws-dropbear; then
        systemctl restart ws-dropbear 2>/dev/null
    fi

    # Check SlowDNS (if configured)
    if [ -f /etc/slowdns/nsdomain.txt ]; then
        if ! systemctl is-active --quiet slowdns; then
            fuser -k 53/udp 2>/dev/null
            systemctl restart slowdns 2>/dev/null
        fi
    fi
    sleep 5
done
EOF
chmod +x /usr/local/bin/vpn-watchdog.sh

cat << 'EOF' > /etc/systemd/system/vpn-watchdog.service
[Unit]
Description=N4 VPN Auto-Recovery Watchdog
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash /usr/local/bin/vpn-watchdog.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ws-dropbear vpn-watchdog
systemctl restart ws-dropbear vpn-watchdog

# 12. Full Firewall Clearance (Ports 1 - 65535 Opened)
echo -e "${YELLOW}[*] Opening All Firewall Ports (1-65535 TCP & UDP)...${NC}"
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X

# Allow Full Range
iptables -A INPUT -p tcp --dport 1:65535 -j ACCEPT
iptables -A INPUT -p udp --dport 1:65535 -j ACCEPT

# Save Iptables Rules permanently
netfilter-persistent save >/dev/null 2>&1 || true

clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${WHITE}           N4 VPS INSTALLATION COMPLETE!             ${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e " ${WHITE}Configured Host Domain :${NC} ${YELLOW}$HOST_DOMAIN${NC}"
if [ $ENABLE_SLOWDNS -eq 1 ]; then
    echo -e " ${WHITE}SlowDNS Status         :${NC} ${GREEN}● ONLINE (${ns_input})${NC}"
else
    echo -e " ${WHITE}SlowDNS Status         :${NC} ${RED}○ OFFLINE (Configure later via menu)${NC}"
fi
echo -e " ${WHITE}Firewall Status        :${NC} ${GREEN}● PORTS 1-65535 UNLOCKED${NC}"
echo -e " ${WHITE}Auto-Recovery Engine   :${NC} ${GREEN}● ACTIVE (Self-Healing Enabled)${NC}"
echo -e " Open panel anytime by typing: ${YELLOW}menu${NC}"
