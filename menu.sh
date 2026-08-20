#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

MYIP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
HOST_DOMAIN=$(cat /etc/vps-domain.txt 2>/dev/null || echo "$MYIP")
TOTAL_ACCOUNTS=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | wc -l)
ONLINE_USERS=$(lsof -i:109 -i:80 -i:143 | grep ESTABLISHED | awk '{print $3}' | sort -u | wc -l)
SLOWDNS_PUB=$(cat /etc/slowdns/server.pub 2>/dev/null)
SAVED_NS=$(cat /etc/slowdns/nsdomain.txt 2>/dev/null || echo "Not Configured")
RAM_USAGE=$(free -m | awk '/Mem:/ { printf "%d/%d MB", $3, $2 }')

check_status() {
    if systemctl is-active --quiet $1; then echo -e "${GREEN}● ONLINE${NC}"; else echo -e "${RED}○ OFFLINE${NC}"; fi
}

STATUS_WS=$(check_status ws-dropbear)
STATUS_DNS=$(check_status slowdns)

clear
echo -e "${CYAN}╭══════════════════════════════════════════════════════════╮${NC}"
echo -e "${CYAN}│${WHITE}                 ★ N4 VPN CONTROL CENTER ★                ${CYAN}│${NC}"
echo -e "${CYAN}╰══════════════════════════════════════════════════════════╯${NC}"
echo -e " ${WHITE}Host / Domain :${NC} ${YELLOW}$HOST_DOMAIN${NC}"
echo -e " ${WHITE}Server IP     :${NC} ${WHITE}$MYIP${NC}         ${WHITE}RAM Usage:${NC} ${GREEN}$RAM_USAGE${NC}"
echo -e " ${WHITE}Total Users   :${NC} ${GREEN}$TOTAL_ACCOUNTS Accounts${NC}   ${WHITE}Online   :${NC} ${CYAN}$ONLINE_USERS Users${NC}"
echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
echo -e " ${WHITE}SSH & WS Engine (80, 143, 442, 8080)${NC}   : $STATUS_WS"
echo -e " ${WHITE}SlowDNS Tunnel  (Port 53)${NC}             : $STATUS_DNS ${YELLOW}($SAVED_NS)${NC}"
echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
echo -e " ${BLUE}► [ USER MANAGEMENT ]${NC}"
echo -e "   ${GREEN}[1]${NC} Create Account (Standard / 24-Hour Free Trial)"
echo -e "   ${GREEN}[2]${NC} Manage User (Extend Expiry / Password / Delete)"
echo -e "   ${GREEN}[3]${NC} Registered Member List & Status"
echo -e "   ${GREEN}[4]${NC} Live Active Connections Monitor"
echo -e "   ${GREEN}[5]${NC} Multi-Login Device Limiter (Auto-Kill Excess)"
echo -e ""
echo -e " ${BLUE}► [ PROTOCOLS & NETWORK ]${NC}"
echo -e "   ${GREEN}[6]${NC} SlowDNS Control Center (Setup NS / Logs)"
echo -e "   ${GREEN}[7]${NC} Change Server Domain / Hostname"
echo -e "   ${GREEN}[8]${NC} TCP BBR Optimizer & Restart All Services"
echo -e ""
echo -e "   ${RED}[0]${NC} Exit Panel"
echo -e "${CYAN}╰══════════════════════════════════════════════════════════╯${NC}"
read -p " Select Option [0-8]: " opt

case $opt in
1)
    echo -e "\n${YELLOW}╭─── CREATE VPN ACCOUNT ───╮${NC}"
    echo -e " [1] Standard Paid Account"
    echo -e " [2] 24-Hour Free Trial Account"
    read -p " Select Type [1-2]: " type_choice
    
    if [ "$type_choice" -eq 2 ]; then
        uname="trial$(tr -dc 0-9 </dev/urandom | head -c 4)"
        pass="1234"
        days=1
    else
        read -p " Enter Username : " uname
        if id "$uname" &>/dev/null; then echo -e "${RED}[!] User already exists!${NC}"; exit 1; fi
        read -p " Enter Password : " pass
        read -p " Active Days    : " days
    fi
    
    exp=$(date -d "+$days days" +"%Y-%m-%d")
    useradd -e $exp -s /bin/false -M $uname
    echo "$uname:$pass" | chpasswd

    clear
    echo -e "${CYAN}╭══════════════════════════════════════════════════════════╮${NC}"
    echo -e "${CYAN}│${WHITE}                 VPN ACCOUNT CREDENTIALS                  ${CYAN}│${NC}"
    echo -e "${CYAN}╰══════════════════════════════════════════════════════════╯${NC}"
    echo -e " ${WHITE}Host / Domain     :${NC} ${YELLOW}$HOST_DOMAIN${NC}"
    echo -e " ${WHITE}Server IP         :${NC} ${WHITE}$MYIP${NC}"
    echo -e " ${WHITE}Username          :${NC} ${GREEN}$uname${NC}"
    echo -e " ${WHITE}Password          :${NC} ${GREEN}$pass${NC}"
    echo -e " ${WHITE}Expiry Date       :${NC} ${PURPLE}$exp ($days Days)${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e " ${WHITE}SSH & Payload Port:${NC} 80, 143, 442, 8080"
    echo -e " ${WHITE}SlowDNS Port      :${NC} 53"
    echo -e " ${WHITE}SlowDNS NS Subname:${NC} ${YELLOW}$SAVED_NS${NC}"
    echo -e " ${WHITE}SlowDNS Public Key:${NC} ${CYAN}$SLOWDNS_PUB${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e " ${YELLOW}Payload WS (HTTP):${NC}"
    echo -e " GET / HTTP/1.1[crlf]Host: $HOST_DOMAIN[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${CYAN}╰══════════════════════════════════════════════════════════╯${NC}"
    ;;
2)
    echo -e "\n${YELLOW}╭─── USER MANAGEMENT ───╮${NC}"
    echo -e " [1] Extend User Expiry Date"
    echo -e " [2] Change Account Password"
    echo -e " [3] Delete Account Permanently"
    read -p " Select Option [1-3]: " manage_opt
    
    read -p " Enter Username: " target_user
    if ! id "$target_user" &>/dev/null; then echo -e "${RED}[!] User '$target_user' not found!${NC}"; exit 1; fi
    
    case $manage_opt in
    1)
        read -p " Enter Additional Days: " add_days
        new_exp=$(date -d "+$add_days days" +"%Y-%m-%d")
        chage -E "$new_exp" "$target_user"
        echo -e "${GREEN}[✔] Account successfully extended until $new_exp.${NC}"
        ;;
    2)
        read -p " Enter New Password: " new_pass
        echo "$target_user:$new_pass" | chpasswd
        echo -e "${GREEN}[✔] Password updated successfully.${NC}"
        ;;
    3)
        userdel -f "$target_user"
        echo -e "${GREEN}[✔] Account '$target_user' deleted.${NC}"
        ;;
    *) echo -e "${RED}[!] Invalid choice.${NC}" ;;
    esac
    ;;
3)
    clear
    echo -e "${CYAN}╭══════════════════════════════════════════════════════════╮${NC}"
    echo -e "${CYAN}│${WHITE}                 REGISTERED MEMBER LIST                   ${CYAN}│${NC}"
    echo -e "${CYAN}╰══════════════════════════════════════════════════════════╯${NC}"
    printf "${WHITE}%-20s %-20s %-15s${NC}\n" "USERNAME" "EXPIRY DATE" "STATUS"
    echo -e "────────────────────────────────────────────────────────────"
    current_epoch=$(date +%s)
    while IFS=: read -u 3 u _ uid _ _ _ _ exp; do
        if [ "$uid" -ge 1000 ] && [ "$u" != "nobody" ]; then
            if [ -n "$exp" ]; then
                exp_epoch=$((exp * 86400))
                exp_date=$(date -d "@$exp_epoch" +"%Y-%m-%d" 2>/dev/null || echo "Never")
                if [ $current_epoch -gt $exp_epoch ]; then status="${RED}EXPIRED${NC}"; else status="${GREEN}ACTIVE${NC}"; fi
            else
                exp_date="Unlimited"; status="${GREEN}ACTIVE${NC}"
            fi
            printf "%-20s %-20s " "$u" "$exp_date"; echo -e "$status"
        fi
    done 3< /etc/passwd
    echo -e "────────────────────────────────────────────────────────────"
    ;;
4)
    clear
    echo -e "${CYAN}╭══════════════════════════════════════════════════════════╮${NC}"
    echo -e "${CYAN}│${WHITE}                LIVE ACTIVE ONLINE SESSIONS               ${CYAN}│${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    printf "${WHITE}%-10s %-18s %-25s${NC}\n" "PID" "USER" "REMOTE IP:PORT"
    echo -e "────────────────────────────────────────────────────────────"
    lsof -i:109 -i:80 -i:143 | grep ESTABLISHED | awk '{printf "%-10s %-18s %-25s\n", $2, $3, $9}'
    echo -e "────────────────────────────────────────────────────────────"
    echo -e " Total Online Sessions: ${GREEN}$ONLINE_USERS${NC}"
    ;;
5)
    echo -e "\n${YELLOW}╭─── MULTI-LOGIN DEVICE LIMITER ───╮${NC}"
    read -p " Enter Max Allowed Connections per User (e.g. 1 or 2): " max_limit
    for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
        count=$(lsof -u "$user" -i:109 -i:80 -i:143 2>/dev/null | grep ESTABLISHED | wc -l)
        if [ "$count" -gt "$max_limit" ]; then
            echo -e "${RED}[!] User '$user' exceeded limit ($count > $max_limit). Terminating sessions...${NC}"
            killall -u "$user" 2>/dev/null
        fi
    done
    echo -e "${GREEN}[✔] Multi-login enforcement complete.${NC}"
    ;;
6)
    echo -e "\n${YELLOW}╭─── SLOWDNS CONTROL CENTER ───╮${NC}"
    echo -e " Default Public Key : ${CYAN}$SLOWDNS_PUB${NC}"
    echo -e " Current NS Subdomain: ${YELLOW}$SAVED_NS${NC}"
    echo -e " Current Status      : $STATUS_DNS"
    echo -e "────────────────────────────────────────────────────────────"
    echo -e " [1] Set NS Subdomain & Start SlowDNS"
    echo -e " [2] Stop / Disable SlowDNS"
    echo -e " [3] View Live Real-Time Logs"
    read -p " Select Option [1-3]: " dns_opt
    
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

[Install]
WantedBy=multi-user.target
DNSSERVICE
            systemctl daemon-reload
            systemctl enable slowdns
            systemctl restart slowdns
            echo -e "${GREEN}[✔] SlowDNS Successfully Started with NS: $new_ns (● ONLINE)${NC}"
        fi
    elif [ "$dns_opt" -eq 2 ]; then
        systemctl stop slowdns
        systemctl disable slowdns
        rm -f /etc/slowdns/nsdomain.txt
        echo -e "${GREEN}[✔] SlowDNS Stopped and Disabled.${NC}"
    elif [ "$dns_opt" -eq 3 ]; then
        journalctl -u slowdns -n 30 --no-pager
    fi
    ;;
7)
    echo -e "\n${YELLOW}╭─── DOMAIN CONFIGURATION ───╮${NC}"
    echo -e " Current Configured Host: ${GREEN}$HOST_DOMAIN${NC}"
    read -p " Enter New Domain / IP: " new_host
    if [ -n "$new_host" ]; then
        echo "$new_host" > /etc/vps-domain.txt
        echo -e "${GREEN}[✔] Host domain updated to: $new_host${NC}"
    fi
    ;;
8)
    echo -e "\n${YELLOW}╭─── SERVER MAINTENANCE & OPTIMIZATION ───╮${NC}"
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${GREEN}[✔] TCP BBR Network Optimizer Activated.${NC}"
    else
        echo -e "${GREEN}[✔] TCP BBR Optimizer is already ACTIVE.${NC}"
    fi
    systemctl restart dropbear ws-dropbear slowdns 2>/dev/null
    echo -e "${GREEN}[✔] Core VPN Services successfully restarted.${NC}"
    ;;
0) exit 0 ;;
*) echo -e "${RED}[!] Invalid selection.${NC}" ;;
esac
