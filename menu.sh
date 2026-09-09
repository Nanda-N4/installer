#!/bin/bash
# ==========================================================
#  ★ N4 VPN CONTROL Panel - FAST EDITION ★
# ==========================================================

# 1. Ultra-Fast Data Fetching (Zero Delay / No External Curl Lag)
if [ ! -f /tmp/vps-cached-ip ]; then
    hostname -I | awk '{print $1}' > /tmp/vps-cached-ip
fi
MYIP=$(cat /tmp/vps-cached-ip 2>/dev/null)
[ -z "$MYIP" ] && MYIP="127.0.0.1"

HOST_DOMAIN=$(cat /etc/vps-domain.txt 2>/dev/null || echo "$MYIP")
TOTAL_ACCOUNTS=$(grep -cE ':/bin/false$' /etc/passwd 2>/dev/null || echo "0")
ONLINE_USERS=$(ss -tn '( sport = :80 or sport = :109 or sport = :143 )' 2>/dev/null | grep -c ESTAB || echo "0")
SLOWDNS_PUB=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "d4edeacb4704be514959de44ff1bc7f875d3403c406e728cb9ee948d5725997d")
SAVED_NS=$(cat /etc/slowdns/nsdomain.txt 2>/dev/null || echo "OFFLINE")

# Lightning Service State Checker
WS_STATE=$(pgrep -f "ws-proxy.py" >/dev/null && echo "ONLINE" || echo "OFFLINE")
DNS_STATE=$(pgrep -f "dnstt-server" >/dev/null && echo "ONLINE" || echo "OFFLINE")
DOG_STATE=$(pgrep -f "vpn-watchdog" >/dev/null && echo "ACTIVE" || echo "INACTIVE")

# RAM & Uptime Stats
RAM_USE=$(free -m | awk '/Mem:/ { printf "%s/%s MB", $3, $2 }')
UPTIME_SYS=$(uptime -p | sed 's/up //')

# High-Tech Cyber Theme Palette
C_PURPLE='\033[38;5;141m'
C_CYAN='\033[38;5;51m'
C_GREEN='\033[38;5;48m'
C_RED='\033[38;5;196m'
C_GOLD='\033[38;5;220m'
C_WHITE='\033[38;5;231m'
C_GRAY='\033[38;5;244m'
C_BLUE='\033[38;5;75m'
BOLD='\033[1m'
NC='\033[0m'

# Dynamic LED Badge
badge() {
    if [ "$1" == "ONLINE" ] || [ "$1" == "ACTIVE" ]; then
        echo -e "${C_GREEN}${BOLD}● $1${NC}"
    else
        echo -e "${C_RED}${BOLD}○ $1${NC}"
    fi
}

clear
echo -e "${C_CYAN}  ___   _ _  _     __   ______  _  _    "
echo -e " | \ \ | | || |    \ \ / /  _ \| \| |   "
echo -e " | |\ \| | || |_    \ V /| |_) | .\ |   "
echo -e " |_| \___|__   _|    \_/ |  __/|_|\_|   ${C_GOLD}${BOLD}★ ENTERPRISE ★${NC}"
echo -e "            |_|          |_|            ${C_GRAY}Core Engine 2026${NC}"
echo -e "${C_PURPLE}─────────────────────────────────────────────────────────────${NC}"
echo -e " ${BOLD}${C_WHITE}Domain / Host${NC} : ${C_GOLD}${HOST_DOMAIN}${NC}"
echo -e " ${BOLD}${C_WHITE}IPv4 Address${NC}  : ${C_CYAN}${MYIP}${NC}        ${BOLD}${C_WHITE}RAM Usage${NC} : ${C_GREEN}${RAM_USE}${NC}"
echo -e " ${BOLD}${C_WHITE}Subscribed${NC}    : ${C_GREEN}${TOTAL_ACCOUNTS} Users${NC}      ${BOLD}${C_WHITE}Active UI${NC} : ${C_CYAN}${ONLINE_USERS} Sessions${NC}"
echo -e " ${BOLD}${C_WHITE}Uptime${NC}        : ${C_GRAY}${UPTIME_SYS}${NC}"
echo -e "${C_PURPLE}─────────────────────────────────────────────────────────────${NC}"
echo -e " ${BOLD}${C_WHITE}SSH Multi-Proxy (80, 143, 442, 8080)${NC} : $(badge $WS_STATE)"
echo -e " ${BOLD}${C_WHITE}SlowDNS Core Engine (UDP 53)       ${NC} : $(badge $DNS_STATE) ${C_GOLD}[$SAVED_NS]${NC}"
echo -e " ${BOLD}${C_WHITE}Background Watchdog Auto-Healer    ${NC} : $(badge $DOG_STATE)"
echo -e "${C_PURPLE}─────────────────────────────────────────────────────────────${NC}"
echo -e " ${C_BLUE}${BOLD}〔 ACCOUNT MANAGEMENT 〕${NC}"
echo -e "  ${C_CYAN}${BOLD}[01]${NC} ${C_WHITE}Create VPN Account${NC}     ${C_GRAY}→ Standard / 24H Quick Trial${NC}"
echo -e "  ${C_CYAN}${BOLD}[02]${NC} ${C_WHITE}Renew Account Expiry${NC}   ${C_GRAY}→ Extend user active duration${NC}"
echo -e "  ${C_CYAN}${BOLD}[03]${NC} ${C_WHITE}Change User Password${NC}   ${C_GRAY}→ Reset credentials instantly${NC}"
echo -e "  ${C_CYAN}${BOLD}[04]${NC} ${C_WHITE}Delete User Account${NC}    ${C_GRAY}→ Disconnect & remove account${NC}"
echo -e "  ${C_CYAN}${BOLD}[05]${NC} ${C_WHITE}Registered User List${NC}   ${C_GRAY}→ View database & expiration${NC}"
echo -e "  ${C_CYAN}${BOLD}[06]${NC} ${C_WHITE}Active Sessions Monitor${NC}${C_GRAY}→ View live connected IP ports${NC}"
echo -e "  ${C_CYAN}${BOLD}[07]${NC} ${C_WHITE}Anti Multi-Login Limiter${NC}${C_GRAY}→ Enforce max devices/user${NC}"
echo -e ""
echo -e " ${C_BLUE}${BOLD}〔 PROTOCOL & MAINTENANCE 〕${NC}"
echo -e "  ${C_CYAN}${BOLD}[08]${NC} ${C_WHITE}SlowDNS Configuration${NC}  ${C_GRAY}→ Setup NS / Live Log Monitor${NC}"
echo -e "  ${C_CYAN}${BOLD}[09]${NC} ${C_WHITE}Server Domain Setting${NC}  ${C_GRAY}→ Update domain or CDN host${NC}"
echo -e "  ${C_CYAN}${BOLD}[10]${NC} ${C_WHITE}Emergency Server Reboot${NC}${C_GRAY}→ Flush firewall & restart all${NC}"
echo -e ""
echo -e "  ${C_RED}${BOLD}[00]${NC} ${C_WHITE}Exit Control Center${NC}"
echo -e "${C_PURPLE}─────────────────────────────────────────────────────────────${NC}"
read -p " Select Option [00-10]: " opt

case $opt in
1|01)
    echo -e "\n${C_GOLD}╭─── CREATE NEW VPN ACCOUNT ───╮${NC}"
    echo -e " [1] Standard Paid Account"
    echo -e " [2] 24-Hour Instant Trial"
    read -p " Choose Account Type [1-2]: " type_choice
    
    if [ "$type_choice" -eq 2 ]; then
        uname="trial$(tr -dc 0-9 </dev/urandom | head -c 4)"
        pass="1234"
        days=1
    else
        read -p " Enter Username : " uname
        if id "$uname" &>/dev/null; then echo -e "${C_RED}[!] Error: Username exists!${NC}"; exit 1; fi
        read -p " Enter Password : " pass
        read -p " Active Days    : " days
    fi
    
    exp=$(date -d "+$days days" +"%Y-%m-%d")
    useradd -e $exp -s /bin/false -M $uname
    echo "$uname:$pass" | chpasswd

    clear
    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C_CYAN}║${C_WHITE}${BOLD}              ★ N4 VPS PANEL ★               ${NC}${C_CYAN}║${NC}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo -e " ${BOLD}${C_WHITE}Host / Domain    :${NC} ${C_GOLD}$HOST_DOMAIN${NC}"
    echo -e " ${BOLD}${C_WHITE}Server IP        :${NC} ${C_WHITE}$MYIP${NC}"
    echo -e " ${BOLD}${C_WHITE}Username         :${NC} ${C_GREEN}$uname${NC}"
    echo -e " ${BOLD}${C_WHITE}Password         :${NC} ${C_GREEN}$pass${NC}"
    echo -e " ${BOLD}${C_WHITE}Active Expiry    :${NC} ${C_PURPLE}$exp ($days Days)${NC}"
    echo -e "${C_PURPLE}────────────────────────────────────────────────────────────${NC}"
    echo -e " ${BOLD}${C_WHITE}SSH / WS Ports   :${NC} 80, 143, 442, 8080"
    echo -e " ${BOLD}${C_WHITE}SlowDNS Port     :${NC} 53"
    echo -e " ${BOLD}${C_WHITE}SlowDNS NS Domain:${NC} ${C_GOLD}$SAVED_NS${NC}"
    echo -e " ${BOLD}${C_WHITE}SlowDNS Key      :${NC} ${C_CYAN}$SLOWDNS_PUB${NC}"
    echo -e "${C_PURPLE}────────────────────────────────────────────────────────────${NC}"
    echo -e " ${C_GOLD}${BOLD}Payload WebSocket (HTTP):${NC}"
    echo -e " GET / HTTP/1.1[crlf]Host: $HOST_DOMAIN[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    ;;
2|02)
    echo -e "\n${C_GOLD}╭─── RENEW ACCOUNT EXPIRY ───╮${NC}"
    read -p " Enter Username to Extend: " target_user
    if ! id "$target_user" &>/dev/null; then echo -e "${C_RED}[!] User '$target_user' not found!${NC}"; exit 1; fi
    read -p " Additional Days: " add_days
    new_exp=$(date -d "+$add_days days" +"%Y-%m-%d")
    chage -E "$new_exp" "$target_user"
    echo -e "${C_GREEN}[✔] Account successfully extended until $new_exp.${NC}"
    ;;
3|03)
    echo -e "\n${C_GOLD}╭─── CHANGE USER PASSWORD ───╮${NC}"
    read -p " Enter Username: " target_user
    if ! id "$target_user" &>/dev/null; then echo -e "${C_RED}[!] User '$target_user' not found!${NC}"; exit 1; fi
    read -p " Enter New Password: " new_pass
    echo "$target_user:$new_pass" | chpasswd
    echo -e "${C_GREEN}[✔] Password updated successfully.${NC}"
    ;;
4|04)
    echo -e "\n${C_GOLD}╭─── DELETE USER ACCOUNT ───╮${NC}"
    read -p " Enter Username to Delete: " target_user
    if id "$target_user" &>/dev/null; then
        killall -u "$target_user" 2>/dev/null
        userdel -f "$target_user"
        echo -e "${C_GREEN}[✔] User '$target_user' terminated and deleted.${NC}"
    else
        echo -e "${C_RED}[!] User not found.${NC}"
    fi
    ;;
5|05)
    clear
    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C_CYAN}║${C_WHITE}${BOLD}                 USER SUBSCRIBER LIST                 ${NC}${C_CYAN}║${NC}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    printf "${BOLD}${C_WHITE}%-20s %-20s %-15s${NC}\n" "USERNAME" "EXPIRY DATE" "STATUS"
    echo -e "${C_PURPLE}────────────────────────────────────────────────────────────${NC}"
    curr_epoch=$(date +%s)
    while IFS=: read -u 3 u _ uid _ _ _ _ exp; do
        if [ "$uid" -ge 1000 ] && [ "$u" != "nobody" ]; then
            if [ -n "$exp" ]; then
                exp_epoch=$((exp * 86400))
                exp_date=$(date -d "@$exp_epoch" +"%Y-%m-%d" 2>/dev/null || echo "Never")
                if [ $curr_epoch -gt $exp_epoch ]; then status="${C_RED}EXPIRED${NC}"; else status="${C_GREEN}ACTIVE${NC}"; fi
            else
                exp_date="Unlimited"; status="${C_GREEN}ACTIVE${NC}"
            fi
            printf "%-20s %-20s " "$u" "$exp_date"; echo -e "$status"
        fi
    done 3< /etc/passwd
    echo -e "${C_PURPLE}────────────────────────────────────────────────────────────${NC}"
    ;;
6|06)
    clear
    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C_CYAN}║${C_WHITE}${BOLD}              LIVE CONCURRENT TCP CONNECTIONS             ${NC}${C_CYAN}║${NC}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    printf "${BOLD}${C_WHITE}%-10s %-18s %-25s${NC}\n" "PID" "USER" "REMOTE IP:PORT"
    echo -e "${C_PURPLE}────────────────────────────────────────────────────────────${NC}"
    lsof -i:109 -i:80 -i:143 2>/dev/null | grep ESTABLISHED | awk '{printf "%-10s %-18s %-25s\n", $2, $3, $9}'
    echo -e "${C_PURPLE}────────────────────────────────────────────────────────────${NC}"
    echo -e " Total Established Sessions: ${C_GREEN}${ONLINE_USERS}${NC}"
    ;;
7|07)
    echo -e "\n${C_GOLD}╭─── MULTI-LOGIN DEVICE LIMITER ───╮${NC}"
    read -p " Enter Max Allowed Logins per User (1 or 2): " max_limit
    for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
        count=$(lsof -u "$u" -i:109 -i:80 -i:143 2>/dev/null | grep -c ESTABLISHED)
        if [ "$count" -gt "$max_limit" ]; then
            echo -e "${C_RED}[!] User '$u' exceeded limit ($count > $max_limit). Terminating...${NC}"
            killall -u "$u" 2>/dev/null
        fi
    done
    echo -e "${C_GREEN}[✔] Multi-login enforcement complete.${NC}"
    ;;
8|08)
    echo -e "\n${C_GOLD}╭─── SLOWDNS CONTROL CENTER ───╮${NC}"
    echo -e " Default Public Key : ${C_CYAN}$SLOWDNS_PUB${NC}"
    echo -e " Current NS Subdomain: ${C_GOLD}$SAVED_NS${NC}"
    echo -e " Current Engine State: $(badge $DNS_STATE)"
    echo -e "────────────────────────────────────────────────────────────"
    echo -e " [1] Set NS Subdomain & Start SlowDNS"
    echo -e " [2] Stop / Disable SlowDNS"
    echo -e " [3] Real-Time SlowDNS Core Traffic Logs"
    read -p " Select Action [1-3]: " dns_opt
    
    if [ "$dns_opt" -eq 1 ]; then
        read -p " Enter NS Subdomain (e.g., ns2.n4vpn.xyz): " new_ns
        if [ -n "$new_ns" ]; then
            echo "$new_ns" > /etc/slowdns/nsdomain.txt
            fuser -k 53/udp 2>/dev/null
            cat << DNSSERVICE > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS DNSTT Server Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/slowdns
ExecStart=/etc/slowdns/dnstt-server -udp 0.0.0.0:53 -privkey-file /etc/slowdns/server.key $new_ns 127.0.0.1:109
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
DNSSERVICE
            systemctl daemon-reload
            systemctl enable slowdns
            systemctl restart slowdns
            echo -e "${C_GREEN}[✔] SlowDNS Successfully Activated with NS: $new_ns${NC}"
        fi
    elif [ "$dns_opt" -eq 2 ]; then
        systemctl stop slowdns
        systemctl disable slowdns
        rm -f /etc/slowdns/nsdomain.txt
        echo -e "${C_GREEN}[✔] SlowDNS Stopped and Set to Offline.${NC}"
    elif [ "$dns_opt" -eq 3 ]; then
        journalctl -u slowdns -n 30 --no-pager
    fi
    ;;
9|09)
    echo -e "\n${C_GOLD}╭─── DOMAIN CONFIGURATION ───╮${NC}"
    echo -e " Current Configured Host: ${C_GREEN}$HOST_DOMAIN${NC}"
    read -p " Enter New Domain / CDN Host: " new_host
    if [ -n "$new_host" ]; then
        echo "$new_host" > /etc/vps-domain.txt
        echo -e "${C_GREEN}[✔] Domain configuration updated to: $new_host${NC}"
    fi
    ;;
10)
    echo -e "\n${C_GOLD}╭─── EMERGENCY HEALING & FLUSH ───╮${NC}"
    echo -e " [*] Refreshing all firewall policies (1-65535)..."
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    iptables -A INPUT -p tcp --dport 1:65535 -j ACCEPT
    iptables -A INPUT -p udp --dport 1:65535 -j ACCEPT
    netfilter-persistent save >/dev/null 2>&1 || true

    echo -e " [*] Restarting all core VPN engines..."
    systemctl restart dropbear ws-dropbear vpn-watchdog 2>/dev/null
    [ -f /etc/slowdns/nsdomain.txt ] && systemctl restart slowdns 2>/dev/null
    rm -f /tmp/vps-cached-ip
    
    echo -e "${C_GREEN}[✔] All Services Restored & Ports Refreshed Successfully!${NC}"
    ;;
0|00) exit 0 ;;
*) echo -e "${C_RED}[!] Invalid choice.${NC}" ;;
esac
