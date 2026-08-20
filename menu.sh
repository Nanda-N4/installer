#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m'

MYIP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
TOTAL_ACCOUNTS=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | wc -l)
ONLINE_USERS=$(lsof -i:143 -i:80 | grep ESTABLISHED | awk '{print $3}' | sort -u | wc -l)
SLOWDNS_PUB=$(cat /etc/slowdns/server.pub 2>/dev/null)
SAVED_NS=$(cat /etc/slowdns/nsdomain.txt 2>/dev/null || echo "Not Configured")

check_status() {
    if systemctl is-active --quiet $1; then echo -e "${GREEN}● RUNNING${NC}"; else echo -e "${RED}○ STOPPED${NC}"; fi
}

STATUS_DB=$(check_status dropbear)
STATUS_WS=$(check_status ws-dropbear)
STATUS_DNS=$(check_status slowdns)

clear
echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${NC}"
echo -e "${CYAN}│${WHITE}             ★ VIP VPN SERVER MANAGEMENT PANEL ★          ${CYAN}│${NC}"
echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
echo -e " ${WHITE}Server Host IP :${NC} ${YELLOW}$MYIP${NC}"
echo -e " ${WHITE}Total Users    :${NC} ${GREEN}$TOTAL_ACCOUNTS Users${NC}  |  ${WHITE}Online :${NC} ${CYAN}$ONLINE_USERS Users${NC}"
echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
echo -e " ${WHITE}SSH Dropbear (143, 109)${NC} : $STATUS_DB"
echo -e " ${WHITE}SSH WS Engine (Port 80)${NC} : $STATUS_WS"
echo -e " ${WHITE}SlowDNS Tunnel (Port 53)${NC}: $STATUS_DNS"
echo -e " ${WHITE}Nameserver (NS Domain)${NC}  : ${YELLOW}$SAVED_NS${NC}"
echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
echo -e " ${GREEN}[01]${NC} Create VPN Account       ${GREEN}[07]${NC} Active Online Connections"
echo -e " ${GREEN}[02]${NC} Create 24-Hour Trial     ${GREEN}[08]${NC} Multi-Login Device Limiter"
echo -e " ${GREEN}[03]${NC} Extend Account Expiry    ${GREEN}[09]${NC} SlowDNS NS Setup & Start"
echo -e " ${GREEN}[04]${NC} Change User Password     ${GREEN}[10]${NC} SlowDNS Live Logs & Status"
echo -e " ${GREEN}[05]${NC} Delete VPN Account       ${GREEN}[11]${NC} TCP BBR Network Booster"
echo -e " ${GREEN}[06]${NC} List All Registered      ${GREEN}[12]${NC} Restart All VPN Services"
echo -e " ${RED}[00]${NC} Exit Panel"
echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
read -p " Select Menu Option [0-12]: " opt

case $opt in
1|2)
    if [ "$opt" -eq 1 ]; then
        echo -e "\n${YELLOW}╭─── CREATE STANDARD USER ───╮${NC}"
        read -p " Enter Username : " uname
        if id "$uname" &>/dev/null; then echo -e "${RED}[!] Error: Username exists!${NC}"; exit 1; fi
        read -p " Enter Password : " pass
        read -p " Active Duration (Days) : " days
    else
        echo -e "\n${YELLOW}╭─── CREATE 24-HOUR TRIAL ───╮${NC}"
        uname="trial$(tr -dc 0-9 </dev/urandom | head -c 4)"; pass="1234"; days=1
    fi
    exp=$(date -d "+$days days" +"%Y-%m-%d")
    useradd -e $exp -s /bin/false -M $uname
    echo "$uname:$pass" | chpasswd
    clear
    echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${WHITE}                 VPN ACCOUNT CREDENTIALS                  ${CYAN}│${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    echo -e " ${WHITE}Host / IP Address${NC}: ${YELLOW}$MYIP${NC}"
    echo -e " ${WHITE}Username         ${NC}: ${GREEN}$uname${NC}"
    echo -e " ${WHITE}Password         ${NC}: ${GREEN}$pass${NC}"
    echo -e " ${WHITE}Expiry Date      ${NC}: ${PURPLE}$exp ($days Days)${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e " ${WHITE}SSH Dropbear Port${NC}: 143, 109"
    echo -e " ${WHITE}SSH WS Port      ${NC}: 80"
    echo -e " ${WHITE}SlowDNS Port     ${NC}: 53"
    echo -e " ${WHITE}Nameserver (NS)  ${NC}: ${YELLOW}$SAVED_NS${NC}"
    echo -e " ${WHITE}SlowDNS PubKey   ${NC}: ${CYAN}$SLOWDNS_PUB${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e " ${YELLOW}Payload WS:${NC} GET / HTTP/1.1[crlf]Host: $MYIP[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    ;;
3)
    read -p " Enter Username to extend: " renew_user
    if ! id "$renew_user" &>/dev/null; then echo -e "${RED}[!] User not found!${NC}"; exit 1; fi
    read -p " Additional Days: " add_days
    new_exp=$(date -d "+$add_days days" +"%Y-%m-%d"); chage -E "$new_exp" "$renew_user"
    echo -e "${GREEN}[✔] User '$renew_user' extended until $new_exp.${NC}"
    ;;
4)
    read -p " Enter Username: " ch_user
    if ! id "$ch_user" &>/dev/null; then echo -e "${RED}[!] User not found!${NC}"; exit 1; fi
    read -p " Enter New Password: " new_pass
    echo "$ch_user:$new_pass" | chpasswd
    echo -e "${GREEN}[✔] Password updated successfully.${NC}"
    ;;
5)
    read -p " Enter Username to delete: " del_user
    if id "$del_user" &>/dev/null; then userdel -f "$del_user"; echo -e "${GREEN}[✔] User '$del_user' deleted.${NC}"; else echo -e "${RED}[!] User not found.${NC}"; fi
    ;;
6)
    clear
    printf "\n${WHITE}%-20s %-20s %-15s${NC}\n" "USERNAME" "EXPIRY DATE" "STATUS"
    echo -e "────────────────────────────────────────────────────────────"
    current_epoch=$(date +%s)
    while IFS=: read -u 3 u _ uid _ _ _ _ exp; do
        if [ "$uid" -ge 1000 ] && [ "$u" != "nobody" ]; then
            if [ -n "$exp" ]; then
                exp_epoch=$((exp * 86400)); exp_date=$(date -d "@$exp_epoch" +"%Y-%m-%d" 2>/dev/null || echo "Never")
                if [ $current_epoch -gt $exp_epoch ]; then status="${RED}EXPIRED${NC}"; else status="${GREEN}ACTIVE${NC}"; fi
            else
                exp_date="Unlimited"; status="${GREEN}ACTIVE${NC}"
            fi
            printf "%-20s %-20s " "$u" "$exp_date"; echo -e "$status"
        fi
    done 3< /etc/passwd
    echo -e "────────────────────────────────────────────────────────────"
    ;;
7)
    clear
    echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${WHITE}               LIVE ACTIVE ONLINE CONNECTIONS             ${CYAN}│${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    printf "${WHITE}%-10s %-18s %-25s${NC}\n" "PID" "USER" "REMOTE IP:PORT"
    echo -e "────────────────────────────────────────────────────────────"
    lsof -i:143 -i:80 | grep ESTABLISHED | awk '{printf "%-10s %-18s %-25s\n", $2, $3, $9}'
    echo -e "────────────────────────────────────────────────────────────"
    echo -e " Total Online Sessions: ${GREEN}$ONLINE_USERS${NC}"
    ;;
8)
    read -p " Max Allowed Connections per User (1 or 2): " max_limit
    for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
        count=$(lsof -u "$user" -i:143 -i:80 2>/dev/null | grep ESTABLISHED | wc -l)
        if [ "$count" -gt "$max_limit" ]; then killall -u "$user" 2>/dev/null; echo -e "${RED}[!] User $user exceeded limit ($count > $max_limit). Disconnecting excess...${NC}"; fi
    done
    echo -e "${GREEN}[✔] Multi-login limiter executed.${NC}"
    ;;
9)
    echo -e "\n${YELLOW}╭─── SLOWDNS SETUP WIZARD ───╮${NC}"
    read -p " Enter NS Subdomain (e.g., ns1.n4vpn.xyz): " ns_input
    if [ -z "$ns_input" ]; then echo -e "${RED}[!] NS Domain is required!${NC}"; exit 1; fi
    echo "$ns_input" > /etc/slowdns/nsdomain.txt
    
    fuser -k 53/udp 2>/dev/null; fuser -k 53/tcp 2>/dev/null
    
    cat << DNSSERVICE > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS DNSTT Server Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/slowdns
ExecStart=/etc/slowdns/dnstt-server -udp :53 -privkey-file /etc/slowdns/server.key $ns_input 127.0.0.1:143
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
DNSSERVICE

    systemctl daemon-reload
    systemctl enable slowdns
    systemctl restart slowdns
    sleep 2
    
    if systemctl is-active --quiet slowdns; then
        echo -e "\n${GREEN}[✔] SlowDNS Started Successfully! (● RUNNING)${NC}"
    else
        echo -e "\n${RED}[!] SlowDNS Service Issue. Displaying Logs:${NC}"
        journalctl -u slowdns -n 12 --no-pager
    fi
    ;;
10)
    echo -e "\n${YELLOW}╭─── REAL-TIME SLOWDNS LOGS ───╮${NC}"
    journalctl -u slowdns -n 30 --no-pager
    ;;
11)
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${GREEN}[✔] TCP BBR successfully activated!${NC}"
    else
        echo -e "${GREEN}[✔] TCP BBR is already ACTIVE.${NC}"
    fi
    ;;
12)
    systemctl restart dropbear ws-dropbear slowdns 2>/dev/null
    echo -e "${GREEN}[✔] All core VPN services restarted.${NC}"
    ;;
0) exit 0 ;;
*) echo -e "${RED}[!] Invalid selection.${NC}" ;;
esac
