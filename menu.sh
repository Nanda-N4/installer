#!/usr/bin/env bash
set -u
N4=/etc/n4vpn
CONF=$N4/n4.conf
DEV=$N4/device-limits
SHARES=$N4/shares
WGDIR=$N4/wireguard
C1='\033[38;5;51m'; C2='\033[38;5;48m'; C3='\033[38;5;220m'; C4='\033[38;5;231m'; C5='\033[38;5;244m'; CR='\033[38;5;196m'; CB='\033[38;5;75m'; CP='\033[38;5;141m'; B='\033[1m'; N='\033[0m'
[[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
mkdir -p "$DEV" "$SHARES" "$WGDIR/clients"

load(){
  VPN_SSH_PORT=109
  WS_PORTS='80,143,442,8080'
  DROPBEAR_PORTS='443'
  DEVICE_LIMIT_DEFAULT=1
  WS_MAX_CLIENTS=2048
  WS_IDLE_TIMEOUT=180
  HOST_DOMAIN="$(hostname -I 2>/dev/null | awk '{print $1}')"
  PUBLIC_IPV4=""
  SLOWDNS_ENABLED=0
  NS_DOMAIN=''
  WG_PORT=550
  WG_MTU=1280
  SHARE_PORT=8880
  [[ -f $CONF ]] && source "$CONF" || true
  if [[ -z ${PUBLIC_IPV4:-} ]]; then
    PUBLIC_IPV4=$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
  fi
}

save(){
  cat >"$CONF" <<EOF2
VPN_SSH_PORT=$VPN_SSH_PORT
WS_PORTS="$WS_PORTS"
DROPBEAR_PORTS="$DROPBEAR_PORTS"
DEVICE_LIMIT_DEFAULT=$DEVICE_LIMIT_DEFAULT
WS_MAX_CLIENTS=$WS_MAX_CLIENTS
WS_IDLE_TIMEOUT=$WS_IDLE_TIMEOUT
HOST_DOMAIN="$HOST_DOMAIN"
PUBLIC_IPV4="$PUBLIC_IPV4"
SLOWDNS_ENABLED=$SLOWDNS_ENABLED
NS_DOMAIN="$NS_DOMAIN"
WG_PORT=$WG_PORT
WG_MTU=$WG_MTU
SHARE_PORT=$SHARE_PORT
EOF2
  chmod 600 "$CONF"
  printf '%s\n' "$HOST_DOMAIN" >/etc/vps-domain.txt
}

svc(){ timeout 2 systemctl is-active --quiet "$1" 2>/dev/null && echo ONLINE || echo OFFLINE; }
badge(){ [[ $1 == ONLINE ]] && echo -e "${C2}● ONLINE${N}" || echo -e "${CR}○ OFFLINE${N}"; }
pause(){ echo; read -r -p ' Press Enter... ' _; }
valid(){ [[ ${1:-} =~ ^[0-9]+$ ]] && ((1<=10#$1 && 10#$1<=65535)); }
has(){ case ",$1," in *",$2,"*) return 0;; *) return 1;; esac; }
allow_tcp(){ iptables -C INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null || true; command -v ufw >/dev/null 2>&1 && ufw allow "$1/tcp" >/dev/null 2>&1 || true; }
allow_udp(){ iptables -C INPUT -p udp --dport "$1" -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport "$1" -j ACCEPT 2>/dev/null || true; command -v ufw >/dev/null 2>&1 && ufw allow "$1/udp" >/dev/null 2>&1 || true; }

header(){
  load
  local ip ram up users peers
  ip=${PUBLIC_IPV4:-$(hostname -I 2>/dev/null|awk '{print $1}')}
  ram=$(free -m|awk '/Mem:/{printf "%d/%d MB",$3,$2}')
  up=$(uptime -p|sed 's/^up //')
  users=$(awk -F: '$3>=1000&&$1!="nobody"{n++}END{print n+0}' /etc/passwd)
  peers=$(wg show wg0 peers 2>/dev/null | wc -l)
  clear
  echo -e "${C1}╭────────────────────────────────────────────────────────────╮${N}"
  echo -e "${C1}│${N} ${B}${C4}N4 VPN CONTROL CENTER${N} ${C5}• Core 2026 r7${N}                      ${C1}│${N}"
  echo -e "${C1}╰────────────────────────────────────────────────────────────╯${N}"
  printf ' %-10s ${C3}%-22s${N} %-8s ${C1}%s${N}\n' Host "$HOST_DOMAIN" IPv4 "$ip"
  printf ' %-10s ${C2}%-22s${N} %-8s %s\n' RAM "$ram" Users "$users"
  printf ' %-10s ${C5}%-22s${N}\n' Uptime "$up"
  echo -e "${CP}──────────────────────────────────────────────────────────────${N}"
  printf ' %-20s %-17b %s\n' 'Admin SSH :22' "$(badge "$(svc ssh)")" Protected
  printf ' %-20s %-17b %s\n' "VPN SSH :$VPN_SSH_PORT" "$(badge "$(svc vpn-ssh)")" Direct
  printf ' %-20s %-17b %s\n' WebSocket "$(badge "$(svc ws-proxy)")" "$WS_PORTS"
  printf ' %-20s %-17b %s\n' Dropbear "$(badge "$(svc dropbear)")" "$DROPBEAR_PORTS"
  printf ' %-20s %-17b %s\n' 'SlowDNS :53/udp' "$(badge "$(svc slowdns)")" "${NS_DOMAIN:-disabled}"
  printf ' %-20s %-17b %s\n' "WireGuard :$WG_PORT/udp" "$(badge "$(svc wg-quick@wg0)")" "$peers peer(s) • MTU $WG_MTU"
  echo -e "${CP}──────────────────────────────────────────────────────────────${N}"
}

checkport(){
  local p=$1 t=$2
  valid "$p" || { echo 'Invalid port.'; return 1; }
  [[ $p != 22 ]] || { echo 'TCP/22 is reserved for Admin SSH.'; return 1; }
  case "$t" in
    vpn) has "$WS_PORTS" "$p" && { echo 'Conflict with WebSocket.'; return 1; }; has "$DROPBEAR_PORTS" "$p" && { echo 'Conflict with Dropbear.'; return 1; } ;;
    ws) [[ $p != "$VPN_SSH_PORT" ]] || { echo 'Conflict with VPN SSH.'; return 1; }; has "$DROPBEAR_PORTS" "$p" && { echo 'Conflict with Dropbear.'; return 1; } ;;
    drop) [[ $p != "$VPN_SSH_PORT" ]] || { echo 'Conflict with VPN SSH.'; return 1; }; has "$WS_PORTS" "$p" && { echo 'Conflict with WebSocket.'; return 1; } ;;
  esac
  return 0
}

apply_vpn(){
  sed -i "s/^Port .*/Port $VPN_SSH_PORT/" /etc/ssh/sshd_vpn_config
  /usr/sbin/sshd -t -f /etc/ssh/sshd_vpn_config || return 1
  if [[ $SLOWDNS_ENABLED -eq 1 && -f /etc/systemd/system/slowdns.service ]]; then
    sed -i -E "s#127\\.0\\.0\\.1:[0-9]+#127.0.0.1:$VPN_SSH_PORT#" /etc/systemd/system/slowdns.service
  fi
  allow_tcp "$VPN_SSH_PORT"
  save
  systemctl daemon-reload
  systemctl restart vpn-ssh
  [[ $SLOWDNS_ENABLED -eq 1 ]] && systemctl restart slowdns || true
  refresh_all_shares
}

apply_ws(){
  save
  local p
  IFS=, read -ra a <<<"$WS_PORTS"
  for p in "${a[@]}"; do allow_tcp "$p"; done
  systemctl restart ws-proxy
  refresh_all_shares
}

apply_drop(){
  local args='' p
  IFS=, read -ra a <<<"$DROPBEAR_PORTS"
  for p in "${a[@]}"; do args+=" -p $p"; allow_tcp "$p"; done
  cat >/etc/default/dropbear <<EOF2
NO_START=0
DROPBEAR_PORT=0
DROPBEAR_EXTRA_ARGS="$args -w -g"
DROPBEAR_BANNER="/etc/issue.net"
EOF2
  save
  systemctl restart dropbear
  refresh_all_shares
}

sync_limits(){
  local f=/etc/security/limits.d/99-n4vpn-users.conf q u l
  : >"$f"
  for q in "$DEV"/*; do
    [[ -f $q ]] || continue
    u=$(basename "$q")
    l=$(cat "$q" 2>/dev/null || echo 0)
    [[ $l =~ ^[0-9]+$ ]] || continue
    (( l > 0 )) && echo "$u hard maxlogins $l" >>"$f"
  done
}

wg_next_ip(){
  local n=2
  while grep -Rqs "10.66.66.$n/32" "$WGDIR/clients" 2>/dev/null; do
    ((n++))
    ((n<255)) || return 1
  done
  echo "10.66.66.$n"
}

wg_rebuild(){
  load
  [[ -s /etc/wireguard/server_private.key ]] || return 1
  local priv iface m
  priv=$(cat /etc/wireguard/server_private.key)
  iface=$(ip route show default | awk '/default/{print $5;exit}')
  [[ -n $iface ]] || return 1
  cat >/etc/wireguard/wg0.conf <<EOF2
[Interface]
Address = 10.66.66.1/24
ListenPort = $WG_PORT
PrivateKey = $priv
MTU = $WG_MTU
PostUp = iptables -C FORWARD -i %i -j ACCEPT 2>/dev/null || iptables -A FORWARD -i %i -j ACCEPT; iptables -C FORWARD -o %i -j ACCEPT 2>/dev/null || iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -C POSTROUTING -s 10.66.66.0/24 -o $iface -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o $iface -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT 2>/dev/null || true; iptables -D FORWARD -o %i -j ACCEPT 2>/dev/null || true; iptables -t nat -D POSTROUTING -s 10.66.66.0/24 -o $iface -j MASQUERADE 2>/dev/null || true
EOF2
  for m in "$WGDIR/clients"/*.meta; do
    [[ -f $m ]] || continue
    unset PEER_NAME PEER_PUBLIC PEER_IP
    . "$m"
    [[ -n ${PEER_PUBLIC:-} && -n ${PEER_IP:-} ]] || continue
    cat >>/etc/wireguard/wg0.conf <<EOF2

# n4-peer:${PEER_NAME:-peer}
[Peer]
PublicKey = $PEER_PUBLIC
AllowedIPs = $PEER_IP/32
EOF2
  done
  chmod 600 /etc/wireguard/wg0.conf
  allow_udp "$WG_PORT"
  systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
  systemctl restart wg-quick@wg0 >/dev/null 2>&1 || true
}

wg_create(){
  local u=$1 ip priv pub spub cfg endpoint
  [[ -f "$WGDIR/clients/$u.meta" ]] && { cat "$WGDIR/clients/$u.conf"; return 0; }
  ip=$(wg_next_ip) || return 1
  priv=$(wg genkey)
  pub=$(printf '%s' "$priv" | wg pubkey)
  spub=$(cat /etc/wireguard/server_public.key)
  endpoint=${PUBLIC_IPV4:-$HOST_DOMAIN}
  cfg="$WGDIR/clients/$u.conf"
  cat >"$cfg" <<EOF2
[Interface]
PrivateKey = $priv
Address = $ip/32
DNS = 1.1.1.1, 8.8.8.8
MTU = $WG_MTU

[Peer]
PublicKey = $spub
Endpoint = $endpoint:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF2
  cat >"$WGDIR/clients/$u.meta" <<EOF2
PEER_NAME=$u
PEER_PUBLIC=$pub
PEER_IP=$ip
EOF2
  chmod 600 "$cfg" "$WGDIR/clients/$u.meta"
  wg_rebuild
  cat "$cfg"
}

update_peer_client_configs(){
  local cfg endpoint
  endpoint=${PUBLIC_IPV4:-$HOST_DOMAIN}
  for cfg in "$WGDIR/clients"/*.conf; do
    [[ -f $cfg ]] || continue
    sed -i -E "s#^Endpoint = .*#Endpoint = $endpoint:$WG_PORT#" "$cfg"
    if grep -q '^MTU = ' "$cfg"; then sed -i -E "s/^MTU = .*/MTU = $WG_MTU/" "$cfg"; else sed -i "/^DNS = /a MTU = $WG_MTU" "$cfg"; fi
    grep -q '^PersistentKeepalive = ' "$cfg" || echo 'PersistentKeepalive = 25' >>"$cfg"
  done
}

share_set_permissions(){
  local f=${1:-}
  id -u n4share >/dev/null 2>&1 || return 0
  if [[ -n $f && -f $f ]]; then chown n4share:n4share "$f"; chmod 640 "$f"; fi
  chown n4share:n4share "$SHARES" 2>/dev/null || true
  chmod 750 "$SHARES" 2>/dev/null || true
}

share_make(){
  local u=$1 pass=$2 exp=$3 token epoch wgcfg endpoint file
  token=$(openssl rand -hex 24)
  epoch=$(date -d "$exp 23:59:59" +%s)
  wgcfg=$(cat "$WGDIR/clients/$u.conf" 2>/dev/null || true)
  endpoint=${PUBLIC_IPV4:-$HOST_DOMAIN}
  file="$SHARES/$token.json"
  python3 - "$file" "$u" "$pass" "$exp" "$epoch" "$HOST_DOMAIN" "$VPN_SSH_PORT" "$WS_PORTS" "$DROPBEAR_PORTS" "${NS_DOMAIN:-}" "$endpoint" "$WG_PORT" "$WG_MTU" "$wgcfg" <<'PYJSON'
import json,sys
p,u,pw,ed,ee,h,ssh,ws,db,ns,ep,wgp,mtu,wgc=sys.argv[1:]
d={'username':u,'password':pw,'expires_date':ed,'expires_epoch':int(ee),'host':h,'ssh_port':ssh,'ws_ports':ws,'dropbear_ports':db,'slowdns_ns':ns,'wg_endpoint':ep+':'+wgp,'wg_mtu':mtu,'wireguard_config':wgc}
with open(p,'w',encoding='utf-8') as f: json.dump(d,f,ensure_ascii=False)
PYJSON
  share_set_permissions "$file"
  echo "http://$HOST_DOMAIN:$SHARE_PORT/s/$token"
}

share_update_user(){
  local u=$1 newpass=${2:-} newexp=${3:-} f endpoint wgcfg
  endpoint=${PUBLIC_IPV4:-$HOST_DOMAIN}
  wgcfg=$(cat "$WGDIR/clients/$u.conf" 2>/dev/null || true)
  for f in "$SHARES"/*.json; do
    [[ -f $f ]] || continue
    python3 - "$f" "$u" "$newpass" "$newexp" "$HOST_DOMAIN" "$VPN_SSH_PORT" "$WS_PORTS" "$DROPBEAR_PORTS" "${NS_DOMAIN:-}" "$endpoint" "$WG_PORT" "$WG_MTU" "$wgcfg" <<'PY'
import json,sys,datetime
p,u,pw,exp,h,ssh,ws,db,ns,ep,wgp,mtu,wgc=sys.argv[1:]
try:
    with open(p,encoding='utf-8') as f:d=json.load(f)
except Exception: sys.exit(0)
if d.get('username')!=u: sys.exit(0)
if pw: d['password']=pw
if exp:
    d['expires_date']=exp
    dt=datetime.datetime.strptime(exp+' 23:59:59','%Y-%m-%d %H:%M:%S')
    d['expires_epoch']=int(dt.timestamp())
d.update({'host':h,'ssh_port':ssh,'ws_ports':ws,'dropbear_ports':db,'slowdns_ns':ns,'wg_endpoint':ep+':'+wgp,'wg_mtu':mtu,'wireguard_config':wgc})
with open(p,'w',encoding='utf-8') as f: json.dump(d,f,ensure_ascii=False)
PY
    share_set_permissions "$f"
  done
}

refresh_all_shares(){
  local f u
  for f in "$SHARES"/*.json; do
    [[ -f $f ]] || continue
    u=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("username",""))' "$f" 2>/dev/null || true)
    [[ -n $u ]] && share_update_user "$u" '' ''
  done
}

create(){
  header
  echo -e " ${CB}${B}CREATE ACCOUNT${N}"
  read -r -p ' Username: ' u
  [[ $u =~ ^[a-z_][a-z0-9_-]{1,31}$ ]] || { echo ' Invalid username. Use 2-32 chars: a-z, 0-9, _ or -.'; pause; return; }
  id "$u" &>/dev/null && { echo ' Account already exists.'; pause; return; }
  read -r -s -p ' Password: ' p; echo
  [[ -n $p ]] || { echo ' Password required.'; pause; return; }
  read -r -p ' Days [30]: ' d; d=${d:-30}
  read -r -p " Session limit [$DEVICE_LIMIT_DEFAULT]: " l; l=${l:-$DEVICE_LIMIT_DEFAULT}
  [[ $d =~ ^[0-9]+$ && $l =~ ^[0-9]+$ ]] || { echo ' Invalid number.'; pause; return; }
  exp=$(date -d "+$d days" +%F)
  useradd -M -s /bin/false -e "$exp" -p "$(openssl passwd -6 "$p")" "$u" || { echo ' Create failed.'; pause; return; }
  echo "$l" >"$DEV/$u"
  sync_limits
  wg_create "$u" >/dev/null || true
  link=$(share_make "$u" "$p" "$exp")
  echo
  echo -e "${C2}${B} ✓ ACCOUNT CREATED${N}"
  echo " User       : $u"
  echo " Expires    : $exp"
  echo " SSH        : $HOST_DOMAIN:$VPN_SSH_PORT"
  [[ $SLOWDNS_ENABLED -eq 1 ]] && echo " SlowDNS    : $NS_DOMAIN"
  echo " WireGuard  : ${PUBLIC_IPV4:-$HOST_DOMAIN}:$WG_PORT/udp • MTU $WG_MTU"
  echo
  echo -e "${C1} Private share link:${N}"
  echo " $link"
  echo -e "${C5} Link expires automatically with this account.${N}"
  pause
}

renew(){
  header
  read -r -p ' Username: ' u
  id "$u" &>/dev/null || { echo ' Not found.'; pause; return; }
  read -r -p ' Add days: ' d
  [[ $d =~ ^[0-9]+$ ]] || { echo ' Invalid days.'; pause; return; }
  cur=$(chage -l "$u" | awk -F': ' '/Account expires/{print $2}')
  base=$(date +%F)
  [[ $cur != never && -n $cur ]] && base=$(date -d "$cur" +%F 2>/dev/null || date +%F)
  [[ $(date -d "$base" +%s) -lt $(date +%s) ]] && base=$(date +%F)
  new=$(date -d "$base +$d days" +%F)
  chage -E "$new" "$u"
  share_update_user "$u" '' "$new"
  echo " New expiry: $new"
  pause
}

passwd_user(){
  header
  read -r -p ' Username: ' u
  id "$u" &>/dev/null || { echo ' Not found.'; pause; return; }
  read -r -s -p ' New password: ' p; echo
  [[ -n $p ]] || { echo ' Password required.'; pause; return; }
  usermod -p "$(openssl passwd -6 "$p")" "$u"
  share_update_user "$u" "$p" ''
  echo ' Password updated.'
  pause
}

deluser_n4(){
  header
  read -r -p ' Username: ' u
  id "$u" &>/dev/null || { echo ' Not found.'; pause; return; }
  read -r -p " Delete $u? [y/N]: " x
  [[ $x =~ ^[Yy]$ ]] || return
  pkill -KILL -u "$u" 2>/dev/null || true
  userdel -f "$u"
  rm -f "$DEV/$u" "$WGDIR/clients/$u.conf" "$WGDIR/clients/$u.meta"
  /usr/local/sbin/n4-cleanup "$u" >/dev/null 2>&1 || true
  wg_rebuild
  sync_limits
  echo ' Account, WireGuard peer and share link removed.'
  pause
}

listusers(){
  header
  printf " ${B}%-18s %-15s %-8s${N}\n" USER EXPIRY LIMIT
  echo ' ------------------------------------------------'
  while IFS=: read -r u _ uid _ _ _ _; do
    ((uid>=1000)) || continue
    [[ $u == nobody ]] && continue
    exp=$(chage -l "$u" 2>/dev/null | awk -F': ' '/Account expires/{print $2}')
    l=$(cat "$DEV/$u" 2>/dev/null || echo "$DEVICE_LIMIT_DEFAULT")
    printf ' %-18s %-15s %-8s\n' "$u" "${exp:0:15}" "$l"
  done </etc/passwd
  pause
}

limit(){
  header
  read -r -p ' Username: ' u
  id "$u" &>/dev/null || { echo ' Not found.'; pause; return; }
  read -r -p ' Concurrent session limit (0=unlimited): ' l
  [[ $l =~ ^[0-9]+$ ]] || { echo ' Invalid.'; pause; return; }
  echo "$l" >"$DEV/$u"
  sync_limits
  echo ' Session limit saved.'
  pause
}

connections(){
  header
  echo -e " ${CB}${B}ONLINE CONNECTIONS${N}"
  echo
  echo ' SSH/WS established TCP connections (first 80):'
  timeout 4 ss -H -tn state established 2>/dev/null | head -n80 || true
  echo
  echo ' WireGuard handshakes:'
  wg show wg0 latest-handshakes 2>/dev/null || true
  pause
}

ports_menu(){
  while true; do
    header
    echo -e " ${CB}${B}PORT MANAGER${N}"
    echo "  [1] VPN SSH              $VPN_SSH_PORT"
    echo "  [2] Replace WS ports     $WS_PORTS"
    echo '  [3] Add WS port'
    echo '  [4] Remove WS port'
    echo "  [5] Replace Dropbear     $DROPBEAR_PORTS"
    echo '  [6] Add Dropbear port'
    echo '  [7] Remove Dropbear port'
    echo '  [0] Back'
    read -r -p ' Select › ' x
    case $x in
      1) read -r -p ' New VPN SSH port: ' p; checkport "$p" vpn || { pause; continue; }; VPN_SSH_PORT=$p; apply_vpn; pause ;;
      2) read -r -p ' WS ports CSV: ' v; ok=1; IFS=, read -ra a<<<"$v"; for p in "${a[@]}"; do checkport "$p" ws || ok=0; done; ((ok)) && { WS_PORTS=$v; apply_ws; }; pause ;;
      3) read -r -p ' WS port: ' p; checkport "$p" ws || { pause; continue; }; has "$WS_PORTS" "$p" || WS_PORTS="$WS_PORTS,$p"; apply_ws; pause ;;
      4) read -r -p ' WS port: ' p; WS_PORTS=$(tr ',' '\n'<<<"$WS_PORTS"|grep -vx "$p"|paste -sd, -); [[ -n $WS_PORTS ]] || WS_PORTS=80; apply_ws; pause ;;
      5) read -r -p ' Dropbear ports CSV: ' v; ok=1; IFS=, read -ra a<<<"$v"; for p in "${a[@]}"; do checkport "$p" drop || ok=0; done; ((ok)) && { DROPBEAR_PORTS=$v; apply_drop; }; pause ;;
      6) read -r -p ' Dropbear port: ' p; checkport "$p" drop || { pause; continue; }; has "$DROPBEAR_PORTS" "$p" || DROPBEAR_PORTS="$DROPBEAR_PORTS,$p"; apply_drop; pause ;;
      7) read -r -p ' Dropbear port: ' p; DROPBEAR_PORTS=$(tr ',' '\n'<<<"$DROPBEAR_PORTS"|grep -vx "$p"|paste -sd, -); [[ -n $DROPBEAR_PORTS ]] || DROPBEAR_PORTS=443; apply_drop; pause ;;
      0) return ;;
    esac
  done
}

slowdns(){
  while true; do
    header
    echo -e " ${CB}${B}SLOWDNS${N}"
    echo "  Status : $SLOWDNS_ENABLED"
    echo "  NS     : ${NS_DOMAIN:-none}"
    echo '  [1] Change NS'
    echo '  [2] Restart'
    echo '  [3] Logs'
    echo '  [0] Back'
    read -r -p ' Select › ' x
    case $x in
      1) read -r -p ' NS domain: ' n; [[ -n $n ]] || continue; NS_DOMAIN=$n; SLOWDNS_ENABLED=1; save; echo "$n">/etc/slowdns/nsdomain.txt; sed -i -E "s#ExecStart=.*#ExecStart=/etc/slowdns/dnstt-server -udp 0.0.0.0:53 -privkey-file /etc/slowdns/server.key $NS_DOMAIN 127.0.0.1:$VPN_SSH_PORT#" /etc/systemd/system/slowdns.service; systemctl daemon-reload; systemctl enable --now slowdns; refresh_all_shares; pause ;;
      2) systemctl restart slowdns; pause ;;
      3) journalctl -u slowdns -n40 --no-pager; pause ;;
      0) return ;;
    esac
  done
}

wg_diagnostics(){
  header
  echo -e " ${CB}${B}WIREGUARD DIAGNOSTICS${N}"
  echo
  printf ' Service            : '; systemctl is-active wg-quick@wg0 2>/dev/null || true
  printf ' UDP listener       : '; ss -lunp 2>/dev/null | grep -q ":$WG_PORT " && echo "OK :$WG_PORT/udp" || echo 'NOT LISTENING'
  printf ' IPv4 forwarding    : '; [[ $(sysctl -n net.ipv4.ip_forward 2>/dev/null) == 1 ]] && echo OK || echo OFF
  printf ' Default interface  : '; ip route show default | awk '/default/{print $5;exit}'
  printf ' Endpoint IPv4      : %s:%s\n' "${PUBLIC_IPV4:-unknown}" "$WG_PORT"
  printf ' Client MTU         : %s\n' "$WG_MTU"
  echo
  wg show wg0 2>/dev/null || true
  echo
  echo ' Tip: connect from mobile data, then run this screen again.'
  echo ' If latest handshake stays empty, UDP traffic is not reaching the VPS.'
  pause
}

wireguard_menu(){
  while true; do
    header
    echo -e " ${CB}${B}WIREGUARD MANAGER${N}"
    echo "  Endpoint : ${PUBLIC_IPV4:-$HOST_DOMAIN}:$WG_PORT/udp"
    echo "  MTU      : $WG_MTU"
    echo '  Keepalive: 25 seconds'
    echo
    echo '  [1] Peer list'
    echo '  [2] Show peer config'
    echo '  [3] Show QR code'
    echo '  [4] Restart / rebuild'
    echo '  [5] Change WireGuard UDP port'
    echo '  [6] Diagnostics'
    echo '  [0] Back'
    read -r -p ' Select › ' x
    case $x in
      1) wg show wg0 2>/dev/null || true; pause ;;
      2) read -r -p ' Peer/account: ' u; cat "$WGDIR/clients/$u.conf" 2>/dev/null || echo ' Not found'; pause ;;
      3) read -r -p ' Peer/account: ' u; [[ -f $WGDIR/clients/$u.conf ]] && qrencode -t ansiutf8 <"$WGDIR/clients/$u.conf" || echo ' Not found'; pause ;;
      4) update_peer_client_configs; wg_rebuild; refresh_all_shares; echo ' WireGuard rebuilt.'; pause ;;
      5) read -r -p " New UDP port [$WG_PORT]: " p; p=${p:-$WG_PORT}; valid "$p" || { echo ' Invalid port.'; pause; continue; }; WG_PORT=$p; save; allow_udp "$WG_PORT"; update_peer_client_configs; wg_rebuild; refresh_all_shares; echo " WireGuard moved to UDP/$WG_PORT."; pause ;;
      6) wg_diagnostics ;;
      0) return ;;
    esac
  done
}

services(){
  while true; do
    header
    echo -e " ${CB}${B}SERVICE MANAGER${N}"
    echo '  [1] Restart VPN SSH'
    echo '  [2] Restart WebSocket'
    echo '  [3] Restart Dropbear'
    echo '  [4] Restart SlowDNS'
    echo '  [5] Restart WireGuard'
    echo '  [6] Restart Share Server'
    echo '  [7] Restart all'
    echo '  [8] Health check'
    echo '  [9] Recent warnings'
    echo '  [0] Back'
    read -r -p ' Select › ' x
    case $x in
      1) systemctl restart vpn-ssh ;;
      2) systemctl restart ws-proxy ;;
      3) systemctl restart dropbear ;;
      4) systemctl restart slowdns ;;
      5) wg_rebuild ;;
      6) systemctl restart n4-share ;;
      7) systemctl restart vpn-ssh ws-proxy dropbear n4-share; [[ $SLOWDNS_ENABLED -eq 1 ]] && systemctl restart slowdns || true; wg_rebuild ;;
      8) /usr/local/sbin/n4-healthcheck; echo ' Health check completed.' ;;
      9) journalctl -u vpn-ssh -u ws-proxy -u dropbear -u slowdns -u wg-quick@wg0 -u n4-share -p warning -n80 --no-pager ;;
      0) return ;;
    esac
    pause
  done
}

domain(){
  header
  read -r -p " New domain/IP [$HOST_DOMAIN]: " h
  [[ -n $h ]] || return
  h=${h#http://}; h=${h#https://}; h=${h%%/*}
  HOST_DOMAIN=$h
  PUBLIC_IPV4=$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || echo "$PUBLIC_IPV4")
  save
  update_peer_client_configs
  refresh_all_shares
  echo ' Domain updated. WireGuard clients continue using the public IPv4 endpoint for mobile compatibility.'
  pause
}

doaccount_menu(){
  while true; do
    header
    echo -e " ${CB}${B}ACCOUNT MANAGER${N}"
    echo '  [1] Create account        [2] Renew account'
    echo '  [3] Change password       [4] Delete account'
    echo '  [5] Account list          [6] Session limit'
    echo '  [0] Back'
    read -r -p ' Select › ' x
    case $x in
      1) create ;;
      2) renew ;;
      3) passwd_user ;;
      4) deluser_n4 ;;
      5) listusers ;;
      6) limit ;;
      0) return ;;
    esac
  done
}

main(){
  while true; do
    header
    echo -e " ${CB}${B}MANAGEMENT${N}"
    echo '  [1] Account Manager'
    echo '  [2] Online Connections'
    echo '  [3] Port Manager'
    echo '  [4] WireGuard Manager'
    echo '  [5] Service Manager'
    echo '  [6] SlowDNS'
    echo '  [7] Change Domain'
    echo
    echo '  [0] Exit'
    echo -e "${CP}──────────────────────────────────────────────────────────────${N}"
    read -r -p ' Select › ' x
    case $x in
      1) doaccount_menu ;;
      2) connections ;;
      3) ports_menu ;;
      4) wireguard_menu ;;
      5) services ;;
      6) slowdns ;;
      7) domain ;;
      0) clear; return ;;
      *) sleep .15 ;;
    esac
  done
}

if [[ ${1:-} == --rebuild-wg ]]; then load; wg_rebuild; exit $?; fi
if [[ ${1:-} == --sync-wg ]]; then load; update_peer_client_configs; wg_rebuild; refresh_all_shares; exit $?; fi
main "$@"
