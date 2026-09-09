#!/bin/bash
# ==========================================================
#  ★ N4 VPS SSCRIPT SUITE - MULTI-CLOUD BULLETPROOF ★
#  Tested & Fully Compatible: Vultr, Linode, AWS, Oracle
# ==========================================================

export DEBIAN_FRONTEND=noninteractive

# ==========================================================
# 0. PREVENT UBUNTU NEEDRESTART INTERRUPTIONS & SSH DROPS
# ==========================================================
if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null
    sed -i "s/\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null
fi
export UCF_FORCE_CONFFOLD=1

# ==========================================================
# 1. FIREWALL UNLOCK (PORTS 1-65535 & SSH GUARD)
# ==========================================================
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

iptables -F
iptables -X
iptables -t nat -F 2>/dev/null
iptables -t nat -X 2>/dev/null

iptables -A INPUT -p tcp --dport 1:65535 -j ACCEPT
iptables -A INPUT -p udp --dport 1:65535 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 1:65535 -j ACCEPT
iptables -A OUTPUT -p udp --dport 1:65535 -j ACCEPT

if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1
    ufw allow 1:65535/tcp >/dev/null 2>&1
    ufw allow 1:65535/udp >/dev/null 2>&1
    ufw disable >/dev/null 2>&1
fi

REPO_RAW="https://raw.githubusercontent.com/Nanda-N4/installer/main"

# Color Palette
C_PURPLE='\033[38;5;141m'
C_CYAN='\033[38;5;51m'
C_GREEN='\033[38;5;48m'
C_RED='\033[38;5;196m'
C_GOLD='\033[38;5;220m'
C_WHITE='\033[38;5;231m'
C_GRAY='\033[38;5;244m'
BOLD='\033[1m'
NC='\033[0m'

MYIP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
[ -z "$MYIP" ] && MYIP=$(hostname -I | awk '{print $1}')

clear
echo -e "${C_CYAN}  ___   _ _  _     __   ______  _  _    "
echo -e " | \ \ | | || |    \ \ / /  _ \| \| |   "
echo -e " | |\ \| | || |_    \ V /| |_) | .\ |   "
echo -e " |_| \___|__   _|    \_/ |  __/|_|\_|   ${C_GOLD}${BOLD}★ Auto INSTALLER ★${NC}"
echo -e "            |_|          |_|            ${C_GRAY}Zero Edition${NC}"
echo -e "${C_PURPLE}─────────────────────────────────────────────────────────────${NC}"
echo -e "${C_GREEN}[✔] Firewall Ports 1-65535 Unlocked (SSH Port 22 Guarded)${NC}"

# 2. System File Limits Optimization
echo -e "\n${C_GOLD}[1/6] Tuning Kernel File Descriptors (Anti-Crash)...${NC}"
cat << 'EOF' >> /etc/security/limits.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
sysctl -w fs.file-max=65535 >/dev/null 2>&1

# 3. Host / Domain Prompt
echo -e "\n${C_GOLD}--- [2/6] SSH WS / CDN DOMAIN CONFIGURATION ---${NC}"
echo -e " VPS တွင် အသုံးပြုမည့် Domain (သို့မဟုတ်) Cloudflare Subdomain ထည့်ပါ။"
echo -e " မရှိပါက Enter နှိပ်ပါ (Server IP: ${C_GREEN}$MYIP${NC} ကို အလိုအလျောက် သုံးပါမည်)။"
read -p " Enter Domain / IP [Default: $MYIP]: " input_domain

if [ -z "$input_domain" ]; then
    HOST_DOMAIN="$MYIP"
else
    HOST_DOMAIN="$input_domain"
fi
echo "$HOST_DOMAIN" > /etc/vps-domain.txt
echo "$MYIP" > /tmp/vps-cached-ip
echo -e "${C_GREEN}[✔] Host Domain Set:${NC} $HOST_DOMAIN"

# 4. SlowDNS NS Setup Prompt
echo -e "\n${C_GOLD}--- [3/6] SLOWDNS PROTOCOL SETUP ---${NC}"
read -p " SlowDNS ကို Server တွင် အသုံးပြုလိုပါသလား? [y/N]: " enable_dns
ENABLE_SLOWDNS=0

mkdir -p /etc/slowdns

if [[ "$enable_dns" =~ ^[Yy]$ ]]; then
    read -p " Enter NS Subdomain (e.g., ns2.n4vpn.xyz): " ns_input
    if [ -n "$ns_input" ]; then
        echo "$ns_input" > /etc/slowdns/nsdomain.txt
        ENABLE_SLOWDNS=1
        echo -e "${C_GREEN}[✔] SlowDNS NS Set:${NC} $ns_input"
    else
        echo -e "${C_GOLD}[*] No NS entered. SlowDNS skipped.${NC}"
        rm -f /etc/slowdns/nsdomain.txt
    fi
else
    echo -e "${C_GOLD}[*] SlowDNS skipped.${NC}"
    rm -f /etc/slowdns/nsdomain.txt
fi

# 5. Safely Free Port 53 (Without Breaking Vultr Network)
echo -e "\n${C_GOLD}[4/6] Safely Liberating UDP Port 53...${NC}"
systemctl stop slowdns ws-dropbear dropbear vpn-watchdog 2>/dev/null

if [ -f "/etc/systemd/resolved.conf" ]; then
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null
    sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null
    systemctl restart systemd-resolved 2>/dev/null
fi

if ! grep -q "1.1.1.1" /etc/resolv.conf 2>/dev/null; then
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
fi

fuser -k 53/udp 2>/dev/null
fuser -k 53/tcp 2>/dev/null

echo -e "\n${C_GOLD}[5/6] Installing Essential Packages & Preparing Dropbear...${NC}"

mkdir -p /etc/default
cat << 'DBCONF' > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=109
DROPBEAR_EXTRA_ARGS="-R -W 65536"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
DBCONF

apt-get update -y
apt-get install -y dropbear python3 screen curl wget net-tools lsof jq iptables iptables-persistent bc dnsutils psmisc ca-certificates
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells

# Setup Banner
cat << 'EOF' > /etc/issue.net
<p style="text-align: center;">
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#ff007f"><b>★ WELCOME TO N4 VPN PREMIUM SERVER ★</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#00ff00"><b>● STATUS: CONNECTED & ENCRYPTED</b></font><br>
<font color="#ffaa00"><b>● SPEED: UNLIMITED HIGH SPEED</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#ff00ff"><b>✖ NO DDOS / NO SPAM / NO FRAUD</b></font><br>
<font color="#ff00ff"><b>✖ NO TORRENT / NO ILLEGAL ACTIVITIES</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#38b6ff"><b>✈ Telegram Channel : </b></font><font color="#ffffff"><b>https://t.me/n4vpn</b></font><br>
<font color="#38b6ff"><b>✈ Support Admin    : </b></font><font color="#ffffff"><b>https://t.me/n4nd404</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font>
</p>
EOF

# Generate Dropbear Host Keys & Restart Cleanly
mkdir -p /etc/dropbear
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key 2>/dev/null
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key 2>/dev/null
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null
systemctl restart ssh sshd 2>/dev/null
systemctl enable dropbear
systemctl restart dropbear

# 7. Fetch Components from GitHub & Deploy Core Engines
echo -e "\n${C_GOLD}[6/6] Fetching Components & Initializing Services...${NC}"
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

# Systemd WebSocket
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

# Systemd SlowDNS
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

# Auto-Recovery Watchdog Daemon
cat << 'EOF' > /usr/local/bin/vpn-watchdog.sh
#!/bin/bash
while true; do
    if ! pgrep -x "dropbear" > /dev/null; then
        systemctl restart dropbear 2>/dev/null
    fi
    if ! systemctl is-active --quiet ws-dropbear; then
        systemctl restart ws-dropbear 2>/dev/null
    fi
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

# Save Firewall Rules Permanently
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
netfilter-persistent save >/dev/null 2>&1 || true

clear
echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${C_CYAN}║${C_WHITE}${BOLD}            N4 VPS Script INSTALLATION COMPLETE!          ${NC}${C_CYAN}║${NC}"
echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e " ${BOLD}${C_WHITE}Configured Host Domain :${NC} ${C_GOLD}$HOST_DOMAIN${NC}"
if [ $ENABLE_SLOWDNS -eq 1 ]; then
    echo -e " ${BOLD}${C_WHITE}SlowDNS Status         :${NC} ${C_GREEN}● ONLINE (${ns_input})${NC}"
else
    echo -e " ${BOLD}${C_WHITE}SlowDNS Status         :${NC} ${C_RED}○ OFFLINE (Configure later in menu)${NC}"
fi
echo -e " ${BOLD}${C_WHITE}Firewall Port Control  :${NC} ${C_GREEN}● PORTS 1-65535 UNLOCKED (SSH GUARDED)${NC}"
echo -e " ${BOLD}${C_WHITE}Auto-Recovery Engine   :${NC} ${C_GREEN}● ACTIVE (Background Watchdog Running)${NC}"
echo -e "${C_PURPLE}────────────────────────────────────────────────────────────${NC}"
echo -e " Open control panel anytime by typing: ${C_GOLD}${BOLD}menu${NC}"
