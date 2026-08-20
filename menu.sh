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
ONLINE_USERS=$(lsof -i:109 -i:80 -i:143 | grep ESTABLISHED | awk '{print $3}' | sort -u | wc -l)
SLOWDNS_PUB=$(cat /etc/slowdns/server.pub 2>/dev/null)
SAVED_NS=$(cat /etc/slowdns/nsdomain.txt 2>/dev/null || echo "ns1.n4vpn.xyz")
RAM_USAGE=$(free -m | awk '/Mem:/ { printf "%d/%d MB", $3, $2 }')

check_status() {
    if systemctl is-active --quiet $1; then echo -e "${GREEN}● RUNNING${NC}"; else echo -e "${RED}○ STOPPED${NC}"; fi
}

STATUS_WS=$(check_status ws-dropbear)
STATUS_DNS=$(check_status slowdns)

clear
echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${NC}"
echo -e "${CYAN}│${WHITE}                 ★ N4 VPN SERVER MANAGER ★                ${CYAN}│${NC}"
echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
echo -e " ${WHITE}Host IP   :${NC} ${YELLOW}$MYIP${NC}          ${WHITE}System RAM :${NC} ${GREEN}$RAM_USAGE${NC}"
echo -e " ${WHITE}Members   :${NC} ${GREEN}$TOTAL_ACCOUNTS Users${NC} (${CYAN}$ONLINE_USERS Online${NC})  ${WHITE}SlowDNS NS :${NC} ${YELLOW}$SAVED_NS${NC}"
echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
echo -e " ${WHITE}SSH & Payload (80, 143, 442, 8080)${NC} : $STATUS_WS"
echo -e " ${WHITE}SlowDNS Tunnel (UDP Port 53)      ${NC} : $STATUS_DNS"
echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
echo -e " ${GREEN}[1]${NC} Create Account (Standard / 24H Trial)"
echo -e " ${GREEN}[2]${NC} Manage User (Renew Expiry / Change Password / Delete)"
echo -e " ${GREEN}[3]${NC} Member List & Expiry Status"
echo -e " ${GREEN}[4]${NC} Live Online Users Monitor"
echo -e " ${GREEN}[5]${NC} Device Limit (Auto Multi-Login Limiter)"
echo -e " ${GREEN}[6]${NC} SlowDNS Configuration & Live Logs"
echo -e " ${GREEN}[7]${NC} System Maintenance (BBR Booster & Service Restart)"
echo -e " ${RED}[0]${NC} Exit Panel"
echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
read -p " Select Option [0-7]: " opt

case $opt in
1)
    echo -e "\n${YELLOW}--- CREATE ACCOUNT ---${NC}"
    echo -e " [1] Standard User Account"
    echo -e " [2] 24-Hour Free Trial"
    read -p " Choice [1-2]: " type_choice
    
    if [ "$type_choice" -eq 2 ]; then
        uname="trial$(tr -dc 0-9 </dev/urandom | head -c 4)"
        pass="1234"
        days=1
    else
        read -p " Username : " uname
        if id "$uname" &>/dev/null; then echo -e "${RED}[!] User already exists!${NC}"; exit 1; fi
        read -p " Password : " pass
        read -p " Duration (Days) : " days
    fi
    
    exp=$(date -d "+$days days" +"%Y-%m-%d")
    useradd -e $exp -s /bin/false -M $uname
    echo "$uname:$pass" | chpasswd

    clear
    echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${WHITE}                 VPN ACCOUNT CREDENTIALS                  ${CYAN}│${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    echo -e " ${WHITE}Host / IP Address :${NC} ${YELLOW}$MYIP${NC}"
    echo -e " ${WHITE}Username          :${NC} ${GREEN}$uname${NC}"
    echo -e " ${WHITE}Password          :${NC} ${GREEN}$pass${NC}"
    echo -e " ${WHITE}Expiry Date       :${NC} ${PURPLE}$exp ($days Days)${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo -e " ${WHITE}SSH / Payload Port:${NC} 80, 143, 442, 8080"
    echo -e " ${WHITE}SlowDNS Port      :${NC} 53"
    echo -e " ${WHITE}SlowDNS NS Domain :${NC} ${YELLOW}$SAVED_NS${NC}"
    echo -e " ${WHITE}SlowDNS Public Key:${NC} ${CYAN}$SLOWDNS_PUB${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo -e " ${YELLOW}Payload WS:${NC} GET / HTTP/1.1[crlf]Host: $MYIP[crlf]Upgrade: websocket[crlf][crlf]"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    ;;
2)
    echo -e "\n${YELLOW}--- MANAGE ACCOUNT ---${NC}"
    echo -e " [1] Extend User Expiry"
    echo -e " [2] Change User Password"
    echo -e " [3] Delete User Account"
    read -p " Choice [1-3]: " manage_opt
    
    read -p " Enter Username: " target_user
    if ! id "$target_user" &>/dev/null; then echo -e "${RED}[!] User not found!${NC}"; exit 1; fi
    
    case $manage_opt in
    1)
        read -p " Additional Days: " add_days
        new_exp=$(date -d "+$add_days days" +"%Y-%m-%d")
        chage -E "$new_exp" "$target_user"
        echo -e "${GREEN}[✔] Account extended until $new_exp.${NC}"
        ;;
    2)
        read -p " Enter New Password: " new_pass
        echo "$target_user:$new_pass" | chpasswd
        echo -e "${GREEN}[✔] Password changed successfully.${NC}"
        ;;
    3)
        userdel -f "$target_user"
        echo -e "${GREEN}[✔] User '$target_user' deleted.${NC}"
        ;;
    *) echo -e "${RED}[!] Invalid choice.${NC}" ;;
    esac
    ;;
3)
    clear
    echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${WHITE}                   REGISTERED USER LIST                   ${CYAN}│${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
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
    echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${WHITE}                LIVE ONLINE ACTIVE SESSIONS               ${CYAN}│${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${NC}"
    printf "${WHITE}%-10s %-18s %-25s${NC}\n" "PID" "USER" "REMOTE IP:PORT"
    echo -e "────────────────────────────────────────────────────────────"
    lsof -i:109 -i:80 -i:143 | grep ESTABLISHED | awk '{printf "%-10s %-18s %-25s\n", $2, $3, $9}'
    echo -e "────────────────────────────────────────────────────────────"
    echo -e " Total Online Sessions: ${GREEN}$ONLINE_USERS${NC}"
    ;;
5)
    echo -e "\n${YELLOW}--- DEVICE LIMITER ---${NC}"
    read -p " Max Allowed Devices per User (e.g. 1 or 2): " max_limit
    for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
        count=$(lsof -u "$user" -i:109 -i:80 -i:143 2>/dev/null | grep ESTABLISHED | wc -l)
        if [ "$count" -gt "$max_limit" ]; then
            echo -e "${RED}[!] User $user exceeded limit ($count > $max_limit). Terminating sessions...${NC}"
            killall -u "$user" 2>/dev/null
        fi
    done
    echo -e "${GREEN}[✔] Multi-login check finished.${NC}"
    ;;
6)
    echo -e "\n${YELLOW}--- SLOWDNS SETTINGS & LOGS ---${NC}"
    echo -e " Default Public Key: ${CYAN}$SLOWDNS_PUB${NC}"
    echo -e " Current NS Domain : ${YELLOW}$SAVED_NS${NC}"
    echo -e "----------------------------------------------------"
    echo -e " [1] Change NS Subdomain & Restart"
    echo -e " [2] View Real-Time SlowDNS Logs"
    read -p " Choice [1-2]: " dns_opt
    
    if [ "$dns_opt" -eq 1 ]; then
        read -p " Enter New NS Subdomain: " ns_input
        if [ -n "$ns_input" ]; then
            echo "$ns_input" > /etc/slowdns/nsdomain.txt
            fuser -k 53/udp 2>/dev/null
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
            systemctl restart slowdns
            echo -e "${GREEN}[✔] SlowDNS updated with NS: $ns_input${NC}"
        fi
    elif [ "$dns_opt" -eq 2 ]; then
        journalctl -u slowdns -n 25 --no-pager
    fi
    ;;
7)
    echo -e "\n${YELLOW}--- SYSTEM MAINTENANCE ---${NC}"
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        echo -e "${GREEN}[✔] TCP BBR Network Optimizer Activated.${NC}"
    else
        echo -e "${GREEN}[✔] TCP BBR is already Active.${NC}"
    fi
    systemctl restart dropbear ws-dropbear slowdns 2>/dev/null
    echo -e "${GREEN}[✔] All VPN core services restarted.${NC}"
    ;;
0) exit 0 ;;
*) echo -e "${RED}[!] Invalid option.${NC}" ;;
esac
