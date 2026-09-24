#!/usr/bin/env bash
set -u
N4=/etc/n4vpn; CONF=$N4/n4.conf; DEV=$N4/device-limits; SHARES=$N4/shares; WGDIR=$N4/wireguard
C1='\033[38;5;51m'; C2='\033[38;5;48m'; C3='\033[38;5;220m'; C4='\033[38;5;231m'; C5='\033[38;5;244m'; CR='\033[38;5;196m'; CB='\033[38;5;75m'; CP='\033[38;5;141m'; B='\033[1m'; N='\033[0m'
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }; mkdir -p "$DEV" "$SHARES" "$WGDIR/clients"
load(){ VPN_SSH_PORT=109; WS_PORTS="80,143,442,8080"; DROPBEAR_PORTS="443"; DEVICE_LIMIT_DEFAULT=1; WS_MAX_CLIENTS=2048; WS_IDLE_TIMEOUT=180; HOST_DOMAIN="$(hostname -I|awk '{print $1}')"; SLOWDNS_ENABLED=0; NS_DOMAIN=""; WG_PORT=51820; SHARE_PORT=8880; [[ -f $CONF ]] && source "$CONF" || true; }
save(){ cat >"$CONF" <<EOF
VPN_SSH_PORT=$VPN_SSH_PORT
WS_PORTS="$WS_PORTS"
DROPBEAR_PORTS="$DROPBEAR_PORTS"
DEVICE_LIMIT_DEFAULT=$DEVICE_LIMIT_DEFAULT
WS_MAX_CLIENTS=$WS_MAX_CLIENTS
WS_IDLE_TIMEOUT=$WS_IDLE_TIMEOUT
HOST_DOMAIN="$HOST_DOMAIN"
SLOWDNS_ENABLED=$SLOWDNS_ENABLED
NS_DOMAIN="$NS_DOMAIN"
WG_PORT=$WG_PORT
SHARE_PORT=$SHARE_PORT
EOF
chmod 600 "$CONF"; echo "$HOST_DOMAIN">/etc/vps-domain.txt; }
svc(){ timeout 2 systemctl is-active --quiet "$1" 2>/dev/null && echo ONLINE || echo OFFLINE; }
badge(){ [[ $1 == ONLINE ]] && echo -e "${C2}● ONLINE${N}" || echo -e "${CR}○ OFFLINE${N}"; }
pause(){ echo; read -r -p "Press Enter... " _; }
valid(){ [[ $1 =~ ^[0-9]+$ ]] && ((1<=10#$1 && 10#$1<=65535)); }
has(){ [[ ",$1," == *",$2,"* ]]; }
allow(){ iptables -C INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null || true; command -v ufw >/dev/null 2>&1 && ufw allow "$1/tcp" >/dev/null 2>&1 || true; }
header(){ load; ip=$(hostname -I|awk '{print $1}'); ram=$(free -m|awk '/Mem:/{printf "%d/%d MB",$3,$2}'); up=$(uptime -p|sed 's/^up //'); users=$(awk -F: '$3>=1000&&$1!="nobody"{n++}END{print n+0}' /etc/passwd); clear; echo -e "${C1}╭────────────────────────────────────────────────────────────╮${N}"; echo -e "${C1}│${N} ${B}${C4}N4 VPN CONTROL CENTER${N} ${C5}• Core 2026${N}                         ${C1}│${N}"; echo -e "${C1}╰────────────────────────────────────────────────────────────╯${N}"; printf " %-12s ${C3}%-20s${N} %-8s ${C1}%s${N}\n" Host "$HOST_DOMAIN" IPv4 "$ip"; printf " %-12s ${C2}%-20s${N} %-8s %s\n" RAM "$ram" Users "$users"; printf " %-12s ${C5}%-20s${N}\n" Uptime "$up"; echo -e "${CP}──────────────────────────────────────────────────────────────${N}"; printf " %-20s %-17b %s\n" "Admin SSH :22" "$(badge "$(svc ssh)")" Protected; printf " %-20s %-17b %s\n" "VPN SSH :$VPN_SSH_PORT" "$(badge "$(svc vpn-ssh)")" Direct; printf " %-20s %-17b %s\n" WebSocket "$(badge "$(svc ws-proxy)")" "$WS_PORTS"; printf " %-20s %-17b %s\n" Dropbear "$(badge "$(svc dropbear)")" "$DROPBEAR_PORTS"; printf " %-20s %-17b %s\n" "SlowDNS :53/udp" "$(badge "$(svc slowdns)")" "${NS_DOMAIN:-disabled}"; printf " %-20s %-17b %s\n" "WireGuard :$WG_PORT/udp" "$(badge "$(svc wg-quick@wg0)")" "$(wg show wg0 peers 2>/dev/null | wc -l) peer(s)"; echo -e "${CP}──────────────────────────────────────────────────────────────${N}"; }
checkport(){
 p=$1; t=$2
 valid "$p" || { echo Invalid; return 1; }
 [[ $p != 22 ]] || { echo "22 is reserved"; return 1; }
 case "$t" in
  vpn) has "$WS_PORTS" "$p" && { echo "Conflict WS"; return 1; }; has "$DROPBEAR_PORTS" "$p" && { echo "Conflict Dropbear"; return 1; } ;;
  ws) [[ $p != "$VPN_SSH_PORT" ]] || { echo "Conflict VPN SSH"; return 1; }; has "$DROPBEAR_PORTS" "$p" && { echo "Conflict Dropbear"; return 1; } ;;
  drop) [[ $p != "$VPN_SSH_PORT" ]] || { echo "Conflict VPN SSH"; return 1; }; has "$WS_PORTS" "$p" && { echo "Conflict WS"; return 1; } ;;
 esac
 return 0
}
apply_vpn(){ sed -i "s/^Port .*/Port $VPN_SSH_PORT/" /etc/ssh/sshd_vpn_config; /usr/sbin/sshd -t -f /etc/ssh/sshd_vpn_config||return; [[ $SLOWDNS_ENABLED -eq 1 && -f /etc/systemd/system/slowdns.service ]]&&sed -i -E "s#127\.0\.0\.1:[0-9]+#127.0.0.1:$VPN_SSH_PORT#" /etc/systemd/system/slowdns.service; allow "$VPN_SSH_PORT"; systemctl daemon-reload; systemctl restart vpn-ssh; [[ $SLOWDNS_ENABLED -eq 1 ]]&&systemctl restart slowdns||true; }
apply_ws(){ save; IFS=, read -ra a<<<"$WS_PORTS";for p in "${a[@]}";do allow "$p";done;systemctl restart ws-proxy; }
apply_drop(){ args="";IFS=, read -ra a<<<"$DROPBEAR_PORTS";for p in "${a[@]}";do args+=" -p $p";allow "$p";done;cat >/etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=0
DROPBEAR_EXTRA_ARGS="$args -w -g"
DROPBEAR_BANNER="/etc/issue.net"
EOF
systemctl restart dropbear; }
sync_limits(){
 local f=/etc/security/limits.d/99-n4vpn-users.conf
 : > "$f"
 for q in "$DEV"/*; do
  [[ -f "$q" ]] || continue
  u=$(basename "$q"); l=$(cat "$q" 2>/dev/null || echo 0)
  [[ "$l" =~ ^[0-9]+$ ]] || continue
  (( l > 0 )) && echo "$u hard maxlogins $l" >> "$f"
 done
 chmod 644 "$f"
}
wg_next_ip(){ local n=2; while grep -Rqs "10.66.66.$n/32" "$WGDIR/clients" 2>/dev/null; do ((n++)); ((n<255))||return 1; done; echo "10.66.66.$n"; }
wg_rebuild(){
 [[ -s /etc/wireguard/server_private.key ]] || return 0
 local priv; priv=$(cat /etc/wireguard/server_private.key)
 cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = $WG_PORT
PrivateKey = $priv
PostUp = iptables -C FORWARD -i %i -j ACCEPT 2>/dev/null || iptables -A FORWARD -i %i -j ACCEPT; iptables -C FORWARD -o %i -j ACCEPT 2>/dev/null || iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -C POSTROUTING -s 10.66.66.0/24 -o $(ip route show default | awk '/default/{print $5;exit}') -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o $(ip route show default | awk '/default/{print $5;exit}') -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o %i -j ACCEPT 2>/dev/null || true; iptables -t nat -D POSTROUTING -s 10.66.66.0/24 -o $(ip route show default | awk '/default/{print $5;exit}') -j MASQUERADE 2>/dev/null || true
EOF
 for m in "$WGDIR/clients"/*.meta; do [[ -f $m ]]||continue; . "$m"; cat >>/etc/wireguard/wg0.conf <<EOF

# n4-peer:$PEER_NAME
[Peer]
PublicKey = $PEER_PUBLIC
AllowedIPs = $PEER_IP/32
EOF
 done
 chmod 600 /etc/wireguard/wg0.conf
 systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
 systemctl restart wg-quick@wg0 >/dev/null 2>&1 || true
}
wg_create(){
 local u=$1 host=$2 ip priv pub spub cfg
 [[ -f "$WGDIR/clients/$u.meta" ]] && { cat "$WGDIR/clients/$u.conf"; return 0; }
 ip=$(wg_next_ip)||return 1; priv=$(wg genkey); pub=$(printf '%s' "$priv"|wg pubkey); spub=$(cat /etc/wireguard/server_public.key)
 cfg="$WGDIR/clients/$u.conf"
 cat >"$cfg" <<EOF
[Interface]
PrivateKey = $priv
Address = $ip/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $spub
Endpoint = $host:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
 cat >"$WGDIR/clients/$u.meta" <<EOF
PEER_NAME=$u
PEER_PUBLIC=$pub
PEER_IP=$ip
EOF
 chmod 600 "$cfg" "$WGDIR/clients/$u.meta"; wg_rebuild; cat "$cfg"
}
share_make(){
 local u=$1 pass=$2 exp=$3 token epoch wgcfg urlhost
 token=$(openssl rand -hex 24); epoch=$(date -d "$exp 23:59:59" +%s); wgcfg=$(cat "$WGDIR/clients/$u.conf" 2>/dev/null||true)
 python3 - "$SHARES/$token.json" "$u" "$pass" "$exp" "$epoch" "$HOST_DOMAIN" "$VPN_SSH_PORT" "$WS_PORTS" "$DROPBEAR_PORTS" "${NS_DOMAIN:-}" "$WG_PORT" "$wgcfg" <<'PYJSON'
import json,sys
p,u,pw,ed,ee,h,ssh,ws,db,ns,wgp,wgc=sys.argv[1:]
d={'username':u,'password':pw,'expires_date':ed,'expires_epoch':int(ee),'host':h,'ssh_port':ssh,'ws_ports':ws,'dropbear_ports':db,'slowdns_ns':ns,'wg_endpoint':h+':'+wgp,'wireguard_config':wgc}
with open(p,'w') as f: json.dump(d,f)
PYJSON
 chmod 600 "$SHARES/$token.json"
 echo "http://$HOST_DOMAIN:$SHARE_PORT/s/$token"
}
create(){
 header; echo -e "${CB}${B}CREATE ACCOUNT${N}"; read -r -p "Username: " u
 [[ $u =~ ^[a-z_][a-z0-9_-]{1,31}$ ]]||{ echo "Invalid username. Use 2-32 chars: a-z, 0-9, _ or -.";pause;return;}
 id "$u"&>/dev/null&&{ echo Exists;pause;return;}; read -r -s -p "Password: " p;echo; [[ -n $p ]]||{ echo "Password required";pause;return;}
 read -r -p "Days [30]: " d;d=${d:-30}; read -r -p "Session limit [$DEVICE_LIMIT_DEFAULT]: " l;l=${l:-$DEVICE_LIMIT_DEFAULT}; [[ $d =~ ^[0-9]+$ && $l =~ ^[0-9]+$ ]]||{ echo Invalid;pause;return;}
 exp=$(date -d "+$d days" +%F); useradd -M -s /bin/false -e "$exp" -p "$(openssl passwd -6 "$p")" "$u" || { echo "Create failed";pause;return;}; echo "$l">"$DEV/$u";sync_limits
 wg_create "$u" "$HOST_DOMAIN" >/dev/null || true; link=$(share_make "$u" "$p" "$exp")
 echo; echo -e "${C2}${B}✓ ACCOUNT CREATED${N}"; echo "User       : $u"; echo "Expires    : $exp"; echo "SSH        : $HOST_DOMAIN:$VPN_SSH_PORT"; [[ $SLOWDNS_ENABLED -eq 1 ]]&&echo "SlowDNS    : $NS_DOMAIN"; echo "WireGuard  : $HOST_DOMAIN:$WG_PORT"; echo; echo -e "${C1}Private share link:${N}"; echo "$link"; echo -e "${C5}Link expires automatically with this account.${N}"; pause
}
renew(){ header;read -r -p "Username: " u;id "$u"&>/dev/null||{ echo Not found;pause;return;};read -r -p "Add days: " d;[[ $d =~ ^[0-9]+$ ]]||return;cur=$(chage -l "$u"|awk -F': ' '/Account expires/{print $2}');base=$(date +%F);[[ $cur != never && -n $cur ]]&&base=$(date -d "$cur" +%F 2>/dev/null||date +%F);[[ $(date -d "$base" +%s) -lt $(date +%s) ]]&&base=$(date +%F);new=$(date -d "$base +$d days" +%F);chage -E "$new" "$u";echo "Expiry $new";pause; }
passwd_user(){ header;read -r -p "Username: " u;id "$u"&>/dev/null||{ echo Not found;pause;return;};read -r -s -p "New password: " p;echo;usermod -p "$(openssl passwd -6 "$p")" "$u";echo Updated;pause; }
deluser_n4(){ header;read -r -p "Username: " u;id "$u"&>/dev/null||{ echo Not found;pause;return;};read -r -p "Delete $u? [y/N]: " x;[[ $x =~ ^[Yy]$ ]]||return;pkill -KILL -u "$u" 2>/dev/null||true;userdel -f "$u";rm -f "$DEV/$u" "$WGDIR/clients/$u.conf" "$WGDIR/clients/$u.meta"; /usr/local/sbin/n4-cleanup "$u" >/dev/null 2>&1||true; wg_rebuild; sync_limits;echo Deleted;pause; }
listusers(){ header;printf "${B}%-18s %-15s %-8s${N}\n" USER EXPIRY LIMIT;echo "---------------------------------------------";while IFS=: read -r u _ uid _ _ _ _;do ((uid>=1000))||continue;[[ $u == nobody ]]&&continue;exp=$(chage -l "$u" 2>/dev/null|awk -F': ' '/Account expires/{print $2}');l=$(cat "$DEV/$u" 2>/dev/null||echo "$DEVICE_LIMIT_DEFAULT");printf "%-18s %-15s %-8s\n" "$u" "${exp:0:15}" "$l";done</etc/passwd;pause; }
limit(){ header;read -r -p "Username: " u;id "$u"&>/dev/null||{ echo Not found;pause;return;};read -r -p "Device/IP limit (0=unlimited): " l;[[ $l =~ ^[0-9]+$ ]]||return;echo "$l">"$DEV/$u";sync_limits;echo "Saved as a PAM maxlogins session limit. This is a concurrent SSH-session limit, not a hardware-phone ID. A client that opens multiple SSH sessions can consume more than one slot.";pause; }
connections(){ header;echo "Established TCP connections (first 80):";timeout 4 ss -H -tn state established 2>/dev/null|head -n80||true;pause; }
ports_menu(){ while true;do header;echo "[1] Change VPN SSH ($VPN_SSH_PORT)";echo "[2] Replace WS ports ($WS_PORTS)";echo "[3] Add WS port";echo "[4] Remove WS port";echo "[5] Replace Dropbear ports ($DROPBEAR_PORTS)";echo "[6] Add Dropbear port";echo "[7] Remove Dropbear port";echo "[0] Back";read -r -p "Select: " x;case $x in 1)read -r -p "New port: " p;checkport "$p" vpn||{ pause;continue;};VPN_SSH_PORT=$p;save;apply_vpn;pause;;2)read -r -p "CSV: " v;ok=1;IFS=, read -ra a<<<"$v";for p in "${a[@]}";do checkport "$p" ws||ok=0;done;((ok))&&{ WS_PORTS=$v;apply_ws;};pause;;3)read -r -p "Port: " p;checkport "$p" ws||{ pause;continue;};has "$WS_PORTS" "$p"||WS_PORTS="$WS_PORTS,$p";apply_ws;pause;;4)read -r -p "Port: " p;WS_PORTS=$(tr ',' '\n'<<<"$WS_PORTS"|grep -vx "$p"|paste -sd, -);[[ -n $WS_PORTS ]]||WS_PORTS=80;apply_ws;pause;;5)read -r -p "CSV: " v;ok=1;IFS=, read -ra a<<<"$v";for p in "${a[@]}";do checkport "$p" drop||ok=0;done;((ok))&&{ DROPBEAR_PORTS=$v;save;apply_drop;};pause;;6)read -r -p "Port: " p;checkport "$p" drop||{ pause;continue;};has "$DROPBEAR_PORTS" "$p"||DROPBEAR_PORTS="$DROPBEAR_PORTS,$p";save;apply_drop;pause;;7)read -r -p "Port: " p;DROPBEAR_PORTS=$(tr ',' '\n'<<<"$DROPBEAR_PORTS"|grep -vx "$p"|paste -sd, -);[[ -n $DROPBEAR_PORTS ]]||DROPBEAR_PORTS=443;save;apply_drop;pause;;0)return;;esac;done; }
slowdns(){ header;echo "SlowDNS: $SLOWDNS_ENABLED • ${NS_DOMAIN:-none}";echo "[1] Change NS";echo "[2] Restart";echo "[3] Logs";echo "[0] Back";read -r -p "Select: " x;case $x in 1)read -r -p "NS: " n;[[ -n $n ]]||return;NS_DOMAIN=$n;SLOWDNS_ENABLED=1;save;echo "$n">/etc/slowdns/nsdomain.txt;sed -i -E "s#ExecStart=.*#ExecStart=/etc/slowdns/dnstt-server -udp 0.0.0.0:53 -privkey-file /etc/slowdns/server.key $NS_DOMAIN 127.0.0.1:$VPN_SSH_PORT#" /etc/systemd/system/slowdns.service;systemctl daemon-reload;systemctl enable --now slowdns;pause;;2)systemctl restart slowdns;pause;;3)journalctl -u slowdns -n30 --no-pager;pause;;0)return;;esac; }
services(){ header;echo "[1] Restart VPN SSH";echo "[2] Restart WS";echo "[3] Restart Dropbear";echo "[4] Restart SlowDNS";echo "[5] Restart all";echo "[6] Health check";echo "[7] Recent warnings";echo "[0] Back";read -r -p "Select: " x;case $x in 1)systemctl restart vpn-ssh;;2)systemctl restart ws-proxy;;3)systemctl restart dropbear;;4)systemctl restart slowdns;;5)systemctl restart vpn-ssh ws-proxy dropbear;[[ $SLOWDNS_ENABLED -eq 1 ]]&&systemctl restart slowdns||true;;6)/usr/local/sbin/n4-healthcheck;;7)journalctl -u vpn-ssh -u ws-proxy -u dropbear -u slowdns -p warning -n60 --no-pager;;0)return;;esac;pause; }
doaccount_menu(){ while true;do header;echo -e " ${CB}${B}ACCOUNT MANAGER${N}";echo "  [1] Create account      [2] Renew account";echo "  [3] Change password     [4] Delete account";echo "  [5] Account list        [6] Session limit";echo "  [0] Back";read -r -p " Select › " x;case $x in 1)create;;2)renew;;3)passwd_user;;4)deluser_n4;;5)listusers;;6)limit;;0)return;;esac;done; }
wireguard_menu(){ while true;do header;echo -e " ${CB}${B}WIREGUARD MANAGER${N}";echo "  [1] Peer list           [2] Show peer config";echo "  [3] Show QR code        [4] Restart WireGuard";echo "  [0] Back";read -r -p " Select › " x;case $x in 1) wg show wg0 2>/dev/null||true;pause;;2)read -r -p "Peer/account: " u;cat "$WGDIR/clients/$u.conf" 2>/dev/null||echo "Not found";pause;;3)read -r -p "Peer/account: " u;[[ -f $WGDIR/clients/$u.conf ]]&&qrencode -t ansiutf8 <"$WGDIR/clients/$u.conf"||echo "Not found";pause;;4)wg_rebuild;pause;;0)return;;esac;done; }
main(){ while true;do header;echo -e " ${CB}${B}MANAGEMENT${N}";echo "  [1] Account Manager";echo "  [2] Online Connections";echo "  [3] Port Manager";echo "  [4] WireGuard Manager";echo "  [5] Service Manager";echo "  [6] SlowDNS";echo "  [7] Change Domain";echo;echo "  [0] Exit";echo -e "${CP}──────────────────────────────────────────────────────────────${N}";read -r -p " Select › " x;case $x in 1)doaccount_menu;;2)connections;;3)ports_menu;;4)wireguard_menu;;5)services;;6)slowdns;;7)domain;;0)clear;return;;*)sleep .2;;esac;done; }
if [[ ${1:-} == --rebuild-wg ]]; then load; wg_rebuild; exit $?; fi
main "$@"
