#!/bin/bash
# ==========================================================
#  ★ N4 VPS AUTO INSTALLER ★
#  Full Compatibility: Ubuntu 22.04 / 24.04 / 26.04
# ==========================================================

export DEBIAN_FRONTEND=noninteractive
export UCF_FORCE_CONFFOLD=1

# 0. DISABLE NEEDRESTART COMPLETELY (CRITICAL FOR VULTR)
mkdir -p /etc/needrestart/conf.d
echo '$nrconf{restart} = "l";' > /etc/needrestart/conf.d/disable-restart.conf 2>/dev/null
if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null
    sed -i "s/\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>/dev/null
fi

# 1. BULLETPROOF FIREWALL & OPENSSH PRESERVATION
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Preserve Active SSH Port 22 Before Flush
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

iptables -F
iptables -X
iptables -t nat -F 2>/dev/null
iptables -t nat -X 2>/dev/null

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
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
echo -e " |_| \___|__   _|    \_/ |  __/|_|\_|   ${C_GOLD}${BOLD}★ AUTO INSTALLER ★${NC}"
echo -e "            |_|          |_|            ${C_GRAY}Zero-Error${NC}"
echo -e "${C_CYAN}─────────────────────────────────────────────────────────────${NC}"
echo -e "${C_GREEN}[✔] Firewall Opened 1-65535 (OpenSSH 22 Protected)${NC}"

# 2. TUNING KERNEL FILE LIMITS & DISABLING PAM QUALITY RESTRICTIONS
echo -e "\n${C_GOLD}[1/6] Tuning Kernel Limits & Disabling PAM Password Restrictions...${NC}"
cat << 'EOF' > /etc/security/limits.d/99-vpn.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
sysctl -w fs.file-max=65535 >/dev/null 2>&1

# PAM password restriction ဖြုတ်ချခြင်း (Password အတိုများ အမှားမပြစေရန်)
sed -i '/pam_pwquality.so/d' /etc/pam.d/common-password 2>/dev/null

# 3. DOMAIN
echo -e "\n${C_GOLD}--- [2/6] DOMAIN CONFIGURATION ---${NC}"
read -p " Enter Domain / IP [Default: $MYIP]: " input_domain
[ -z "$input_domain" ] && HOST_DOMAIN="$MYIP" || HOST_DOMAIN="$input_domain"
echo "$HOST_DOMAIN" > /etc/vps-domain.txt
echo "$MYIP" > /tmp/vps-cached-ip

# 4. SLOWDNS
echo -e "\n${C_GOLD}--- [3/6] SLOWDNS SETUP ---${NC}"
read -p " SlowDNS ကို သုံးမည်လား? [y/N]: " enable_dns
ENABLE_SLOWDNS=0
mkdir -p /etc/slowdns
if [[ "$enable_dns" =~ ^[Yy]$ ]]; then
    read -p " Enter NS Subdomain (e.g., nssg.nandavip.bond): " ns_input
    if [ -n "$ns_input" ]; then
        echo "$ns_input" > /etc/slowdns/nsdomain.txt
        ENABLE_SLOWDNS=1
    fi
fi

# 5. RELEASING UDP PORT 53 SAFELY
echo -e "\n${C_GOLD}[4/6] Liberating Port 53 Safely...${NC}"
systemctl stop slowdns ws-dropbear vpn-watchdog 2>/dev/null
fuser -k 53/udp 2>/dev/null
fuser -k 53/tcp 2>/dev/null

if [ -f "/etc/systemd/resolved.conf" ]; then
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null
    sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null
    systemctl restart systemd-resolved 2>/dev/null
fi
grep -q "1.1.1.1" /etc/resolv.conf 2>/dev/null || echo "nameserver 1.1.1.1" >> /etc/resolv.conf

# 6. ESSENTIAL PACKAGES & OPENSSH MULTI-PORT SETUP
echo -e "\n${C_GOLD}[5/6] Configuring Multi-Port SSH Engine with Legacy KEX...${NC}"
touch /etc/shells
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells
grep -qxF '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

apt-get update -y
apt-get install -y python3 curl wget net-tools lsof jq iptables iptables-persistent bc dnsutils psmisc ca-certificates

systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true
killall -9 dropbear 2>/dev/null || true

# Banner
cat << 'EOF' > /etc/issue.net
<p style="text-align: center;">
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#ff007f"><b>★ WELCOME TO N4 PREMIUM SERVER ★</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#00ff00"><b>● STATUS: CONNECTED & ENCRYPTED</b></font><br>
<font color="#ffaa00"><b>● SPEED: UNLIMITED HIGH SPEED</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#ff00ff"><b>✖ NO DDOS / NO SPAM / NO FRAUD</b></font><br>
<font color="#ff00ff"><b>✖ NO TORRENT / NO ILLEGAL ACTIVITIES</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font><br>
<font color="#38b6ff"><b>✈ Telegram Channel : </b></font><font color="#00ffff"><b>https://t.me/n4vpn</b></font><br>
<font color="#38b6ff"><b>✈ Support Admin    : </b></font><font color="#00ffff"><b>https://t.me/n4nd404</b></font><br>
<font color="#00ffff"><b>══════════════════════════════════════</b></font>
</p>
EOF

# Deploy OpenSSH Dual-Port (22 & 109) + Legacy KEX Configuration
rm -f /etc/ssh/sshd_config.d/* 2>/dev/null
mkdir -p /etc/ssh/sshd_config.d
cat << 'EOF' > /etc/ssh/sshd_config.d/n4vpn.conf
Port 22
Port 109
PasswordAuthentication yes
PermitRootLogin yes
AllowTcpForwarding yes
GatewayPorts yes
KexAlgorithms +diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1
Ciphers +aes128-cbc,3des-cbc,aes256-cbc,aes128-ctr,aes192-ctr,aes256-ctr
MACs +hmac-sha1,hmac-sha1-96,hmac-md5,hmac-md5-96
HostKeyAlgorithms +ssh-rsa,ssh-dss
PubkeyAcceptedAlgorithms +ssh-rsa
Banner /etc/issue.net
EOF

# Disable Ubuntu ssh.socket & Run ssh as standalone service
systemctl stop ssh.socket 2>/dev/null || true
systemctl disable ssh.socket 2>/dev/null || true
systemctl daemon-reload
systemctl enable --now ssh.service 2>/dev/null || systemctl enable --now sshd.service 2>/dev/null || true
systemctl restart ssh.service 2>/dev/null || systemctl restart sshd.service 2>/dev/null || true

# 7. DOWNLOAD GITHUB COMPONENTS & START SERVICES
echo -e "\n${C_GOLD}[6/6] Fetching Components & Starting VPN Engines...${NC}"
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

# WebSocket Proxy Systemd Unit
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

# SlowDNS Systemd Unit
if [ $ENABLE_SLOWDNS -eq 1 ]; then
    ns_val=$(cat /etc/slowdns/nsdomain.txt)
    cat << DNSSERVICE > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS DNSTT Server Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/slowdns
ExecStart=/etc/slowdns/dnstt-server -udp 0.0.0.0:53 -privkey-file /etc/slowdns/server.key $ns_val 127.0.0.1:109
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

# Multi-Cloud Auto-Recovery Watchdog
cat << 'EOF' > /usr/local/bin/vpn-watchdog.sh
#!/bin/bash
while true; do
    if ! pgrep -x "sshd" > /dev/null; then
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
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

mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

clear
echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${C_CYAN}║${C_WHITE}${BOLD}            N4 VPS INSTALLATION COMPLETE!          ${NC}${C_CYAN}║${NC}"
echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo -e " ${BOLD}${C_WHITE}Host Domain :${NC} ${C_GOLD}$HOST_DOMAIN${NC}"
echo -e " ${BOLD}${C_WHITE}Firewall    :${NC} ${C_GREEN}● SECURED (SSH Protected & Ports 1-65535 Open)${NC}"
echo -e " ${C_CYAN}────────────────────────────────────────────────────────────${NC}"
echo -e " Open control panel anytime by typing: ${C_GOLD}${BOLD}menu${NC}"
