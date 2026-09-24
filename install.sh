#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_VERSION="2026.09.24-r5"
export DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1
REPO_RAW="https://raw.githubusercontent.com/Nanda-N4/installer/main"
fetch_repo(){
  local file="$1" dest="$2"
  curl -fL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 90 \
    -H "Cache-Control: no-cache" \
    "${REPO_RAW}/${file}?cb=$(date +%s%N)" -o "$dest"
}
N4_DIR=/etc/n4vpn; CONF=$N4_DIR/n4.conf
C1='\033[38;5;51m'; C2='\033[38;5;48m'; C3='\033[38;5;220m'; C4='\033[38;5;231m'; C5='\033[38;5;244m'; CR='\033[38;5;196m'; B='\033[1m'; N='\033[0m'
trap 'rc=$?; echo -e "${CR}[!] Failed at line $LINENO (exit $rc): ${BASH_COMMAND}${N}"' ERR
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

logo(){ clear; echo -e "${C1}╭────────────────────────────────────────────────────────────╮${N}"; echo -e "${C1}│${N} ${B}${C4}N4 VPN • MODERN INSTALLER 2026 • r5${N}                          ${C1}│${N}"; echo -e "${C1}│${N} ${C5}SSH • WebSocket • Dropbear • SlowDNS • Auto Recovery${N}        ${C1}│${N}"; echo -e "${C1}╰────────────────────────────────────────────────────────────╯${N}"; }
step(){ echo -e "\n${C3}${B}[$1]${N} ${C4}$2${N}"; }
valid_port(){ [[ "$1" =~ ^[0-9]+$ ]] && ((1<=10#$1 && 10#$1<=65535)); }

load_conf(){
  VPN_SSH_PORT=109; WS_PORTS="80,143,442,8080"; DROPBEAR_PORTS="443"; DEVICE_LIMIT_DEFAULT=1
  WS_MAX_CLIENTS=2048; WS_IDLE_TIMEOUT=180; HOST_DOMAIN=""; SLOWDNS_ENABLED=0; NS_DOMAIN=""
  [[ -f $CONF ]] && source "$CONF" || true
  if [[ -z "$HOST_DOMAIN" && -f /etc/vps-domain.txt ]]; then
    HOST_DOMAIN=$(cat /etc/vps-domain.txt)
  fi
  return 0
}
save_conf(){
  mkdir -p "$N4_DIR/device-limits" /var/log/n4vpn
  cat > "$CONF" <<CONF_EOF
VPN_SSH_PORT=$VPN_SSH_PORT
WS_PORTS="$WS_PORTS"
DROPBEAR_PORTS="$DROPBEAR_PORTS"
DEVICE_LIMIT_DEFAULT=$DEVICE_LIMIT_DEFAULT
WS_MAX_CLIENTS=$WS_MAX_CLIENTS
WS_IDLE_TIMEOUT=$WS_IDLE_TIMEOUT
HOST_DOMAIN="$HOST_DOMAIN"
SLOWDNS_ENABLED=$SLOWDNS_ENABLED
NS_DOMAIN="$NS_DOMAIN"
CONF_EOF
  chmod 600 "$CONF"; echo "$HOST_DOMAIN" > /etc/vps-domain.txt
}
protect_22(){
  iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
  command -v ufw >/dev/null 2>&1 && ufw allow 22/tcp >/dev/null 2>&1 || true
}
allow_port(){
  local p=$1 proto=${2:-tcp}; valid_port "$p" || return 0
  iptables -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null || iptables -A INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null || true
  command -v ufw >/dev/null 2>&1 && ufw allow "$p/$proto" >/dev/null 2>&1 || true
}
validate_ports(){
  [[ $VPN_SSH_PORT != 22 ]] || { echo "Port 22 is reserved for Admin SSH"; exit 1; }
  valid_port "$VPN_SSH_PORT" || exit 1
  IFS=, read -ra a <<< "$WS_PORTS"; for p in "${a[@]}"; do valid_port "$p" || exit 1; [[ $p != 22 && $p != "$VPN_SSH_PORT" ]] || exit 1; done
  IFS=, read -ra d <<< "$DROPBEAR_PORTS"
  for p in "${d[@]}"; do
    valid_port "$p" || { echo "Invalid Dropbear port: $p"; exit 1; }
    [[ $p != 22 && $p != "$VPN_SSH_PORT" ]] || { echo "Reserved/conflicting Dropbear port: $p"; exit 1; }
    case ",$WS_PORTS," in
      *",$p,"*) echo "Port conflict: Dropbear $p is already used by WebSocket"; exit 1 ;;
    esac
  done
}

write_vpn_ssh(){
cat > /etc/issue.net <<'BANNER_EOF'
══════════════════════════════════════
       ★ N4 VPN PREMIUM SERVER ★
══════════════════════════════════════
● STATUS : CONNECTED & ENCRYPTED
● POLICY : NO SPAM / FRAUD / ABUSE
══════════════════════════════════════
Telegram : https://t.me/n4vpn
Support  : https://t.me/n4nd404
══════════════════════════════════════
BANNER_EOF
cat > /etc/ssh/sshd_vpn_config <<SSH_EOF
Port $VPN_SSH_PORT
ListenAddress 0.0.0.0
ListenAddress ::
PidFile /run/sshd_vpn.pid
Protocol 2
UsePAM yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin no
AllowTcpForwarding yes
GatewayPorts yes
PermitTunnel yes
X11Forwarding no
PrintMotd no
ClientAliveInterval 60
ClientAliveCountMax 3
LoginGraceTime 30
MaxStartups 100:30:500
MaxSessions 32
Banner /etc/issue.net
SSH_EOF
cat > /etc/systemd/system/vpn-ssh.service <<'UNIT_EOF'
[Unit]
Description=N4 VPN Dedicated SSH Engine
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStartPre=/usr/sbin/sshd -t -f /etc/ssh/sshd_vpn_config
ExecStart=/usr/sbin/sshd -D -e -f /etc/ssh/sshd_vpn_config
Restart=on-failure
RestartSec=2
LimitNOFILE=262144
TasksMax=8192
OOMScoreAdjust=-250
Nice=-2
[Install]
WantedBy=multi-user.target
UNIT_EOF
}

write_dropbear(){
  local args=""; IFS=, read -ra a <<< "$DROPBEAR_PORTS"; for p in "${a[@]}"; do args+=" -p $p"; done
  cat > /etc/default/dropbear <<DROP_EOF
NO_START=0
DROPBEAR_PORT=0
DROPBEAR_EXTRA_ARGS="$args -w -g"
DROPBEAR_BANNER="/etc/issue.net"
DROP_EOF
}

write_ws_unit(){
cat > /etc/systemd/system/ws-proxy.service <<'UNIT_EOF'
[Unit]
Description=N4 Async WebSocket SSH Proxy
After=network-online.target vpn-ssh.service
Wants=network-online.target
Requires=vpn-ssh.service
[Service]
Type=simple
User=root
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=on-failure
RestartSec=2
LimitNOFILE=262144
TasksMax=8192
OOMScoreAdjust=-100
[Install]
WantedBy=multi-user.target
UNIT_EOF
}

write_slowdns(){
  if [[ $SLOWDNS_ENABLED -eq 1 ]]; then
    mkdir -p /etc/slowdns
    [[ -x /etc/slowdns/dnstt-server ]] || fetch_repo dnstt-server /etc/slowdns/dnstt-server
    [[ -s /etc/slowdns/server.key ]] || fetch_repo server.key /etc/slowdns/server.key
    [[ -s /etc/slowdns/server.pub ]] || fetch_repo server.pub /etc/slowdns/server.pub
    chmod 755 /etc/slowdns/dnstt-server; chmod 600 /etc/slowdns/server.key; echo "$NS_DOMAIN" >/etc/slowdns/nsdomain.txt
    if [[ -f /etc/systemd/resolved.conf ]]; then grep -q '^DNSStubListener=' /etc/systemd/resolved.conf && sed -i 's/^DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf || echo 'DNSStubListener=no' >> /etc/systemd/resolved.conf; systemctl restart systemd-resolved 2>/dev/null || true; fi
    cat > /etc/systemd/system/slowdns.service <<DNS_EOF
[Unit]
Description=N4 SlowDNS DNSTT Server
After=network-online.target vpn-ssh.service
Requires=vpn-ssh.service
[Service]
Type=simple
WorkingDirectory=/etc/slowdns
ExecStart=/etc/slowdns/dnstt-server -udp 0.0.0.0:53 -privkey-file /etc/slowdns/server.key $NS_DOMAIN 127.0.0.1:$VPN_SSH_PORT
Restart=on-failure
RestartSec=2
LimitNOFILE=262144
TasksMax=8192
OOMScoreAdjust=-150
Nice=-1
[Install]
WantedBy=multi-user.target
DNS_EOF
  else systemctl disable --now slowdns 2>/dev/null || true; rm -f /etc/systemd/system/slowdns.service; fi
}

write_health(){
cat > /usr/local/sbin/n4-healthcheck <<'HEALTH_EOF'
#!/usr/bin/env bash
set -u
source /etc/n4vpn/n4.conf 2>/dev/null || exit 0
check(){ timeout 2 bash -c "</dev/tcp/127.0.0.1/$2" >/dev/null 2>&1 || systemctl restart "$1" >/dev/null 2>&1 || true; }
systemctl is-active --quiet vpn-ssh || systemctl restart vpn-ssh >/dev/null 2>&1 || true
check vpn-ssh "${VPN_SSH_PORT:-109}"
[[ -n ${WS_PORTS:-} ]] && check ws-proxy "${WS_PORTS%%,*}"
[[ -n ${DROPBEAR_PORTS:-} ]] && check dropbear "${DROPBEAR_PORTS%%,*}"
[[ ${SLOWDNS_ENABLED:-0} == 1 ]] && systemctl is-active --quiet slowdns || { [[ ${SLOWDNS_ENABLED:-0} == 1 ]] && systemctl restart slowdns >/dev/null 2>&1 || true; }
HEALTH_EOF
chmod 755 /usr/local/sbin/n4-healthcheck
cat > /etc/systemd/system/n4-healthcheck.service <<'UNIT_EOF'
[Unit]
Description=N4 VPN health check
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/n4-healthcheck
Nice=10
IOSchedulingClass=idle
UNIT_EOF
cat > /etc/systemd/system/n4-healthcheck.timer <<'UNIT_EOF'
[Unit]
Description=N4 VPN health check timer
[Timer]
OnBootSec=45s
OnUnitActiveSec=60s
AccuracySec=10s
Persistent=true
[Install]
WantedBy=timers.target
UNIT_EOF
systemctl disable --now vpn-watchdog.service 2>/dev/null || true
rm -f /etc/systemd/system/vpn-watchdog.service /usr/local/bin/vpn-watchdog.sh
}

write_auto_menu(){
cat > /etc/profile.d/n4-menu.sh <<'PROFILE_EOF'
if [ "$(id -u 2>/dev/null)" = "0" ] && [ -t 0 ] && [ -t 1 ] && [ -z "${N4_MENU_ACTIVE:-}" ] && [ -x /usr/local/bin/menu ]; then
  case "${TERM:-}" in dumb|'') ;; *) export N4_MENU_ACTIVE=1; /usr/local/bin/menu || true ;; esac
fi
PROFILE_EOF
chmod 644 /etc/profile.d/n4-menu.sh
}

main(){
  logo; load_conf
  step 1/8 "Protecting Admin SSH TCP/22"; protect_22; echo -e "${C2}[✓] Existing firewall rules are preserved; TCP/22 is explicitly allowed.${N}"
  step 2/8 "Server identity"
  ip=$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
  [[ -n ${ip:-} ]] || ip="127.0.0.1"

  echo -e "${C5}Default host: ${C4}$ip${N}"
  read -r -p " Use a domain? [y/N]: " x
  case "${x:-N}" in
    y|Y|yes|YES|Yes)
      while :; do
        read -r -p " Domain: " x
        x=${x#http://}; x=${x#https://}; x=${x%%/*}
        if [[ -n $x && $x != *" "* ]]; then
          HOST_DOMAIN=$x
          break
        fi
        echo -e "${CR}[!] Please enter a valid domain, e.g. vpn.example.com${N}"
      done
      ;;
    *) HOST_DOMAIN=$ip ;;
  esac

  step 3/8 "Default ports"
  echo -e "${C2}[✓] VPN SSH   : ${VPN_SSH_PORT}${N}"
  echo -e "${C2}[✓] WebSocket : ${WS_PORTS}${N}"
  echo -e "${C2}[✓] Dropbear  : ${DROPBEAR_PORTS}${N}"
  echo -e "${C5}    Ports can be changed later from the N4 menu.${N}"
  validate_ports

  step 4/8 "SlowDNS"
  read -r -p " Install SlowDNS? [y/N]: " x
  case "${x:-N}" in
    y|Y|yes|YES|Yes)
      SLOWDNS_ENABLED=1
      while :; do
        read -r -p " NS domain: " x
        x=${x#http://}; x=${x#https://}; x=${x%%/*}
        if [[ -n $x && $x != *" "* ]]; then
          NS_DOMAIN=$x
          break
        fi
        echo -e "${CR}[!] NS domain is required, e.g. ns.example.com${N}"
      done
      ;;
    *)
      SLOWDNS_ENABLED=0
      NS_DOMAIN=""
      ;;
  esac
  save_conf
  step 5/8 "Installing packages and tuning"; apt-get update -y; apt-get install -y openssh-server dropbear python3 curl wget ca-certificates jq bc iproute2 net-tools lsof psmisc dnsutils procps openssl iptables iptables-persistent util-linux
  cat >/etc/security/limits.d/99-n4vpn.conf <<'LIM_EOF'
* soft nofile 262144
* hard nofile 262144
root soft nofile 262144
root hard nofile 262144
LIM_EOF
  cat >/etc/sysctl.d/99-n4vpn.conf <<'SYS_EOF'
fs.file-max = 1048576
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
SYS_EOF
  sysctl --system >/dev/null 2>&1 || true; ssh-keygen -A >/dev/null 2>&1 || true; /usr/sbin/sshd -t && { systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true; }
  step 6/8 "Installing services"; systemctl disable --now ws-dropbear.service 2>/dev/null || true; rm -f /etc/systemd/system/ws-dropbear.service; touch /etc/shells; grep -qxF /bin/false /etc/shells || echo /bin/false >>/etc/shells; write_vpn_ssh; write_dropbear; write_slowdns; fetch_repo ws-proxy.py /usr/local/bin/ws-proxy.py; fetch_repo menu.sh /usr/local/bin/menu; chmod 755 /usr/local/bin/ws-proxy.py /usr/local/bin/menu; write_ws_unit; write_health; write_auto_menu
  step 7/8 "Opening required local ports"
  protect_22
  allow_port "$VPN_SSH_PORT" tcp
  IFS=, read -ra a <<< "$WS_PORTS"; for p in "${a[@]}"; do allow_port "$p" tcp; done
  IFS=, read -ra a <<< "$DROPBEAR_PORTS"; for p in "${a[@]}"; do allow_port "$p" tcp; done
  if [[ $SLOWDNS_ENABLED -eq 1 ]]; then allow_port 53 udp; fi
  iptables-save >/etc/iptables/rules.v4 2>/dev/null || true

  step 8/8 "Starting engines"
  systemctl daemon-reload
  systemctl enable --now vpn-ssh ws-proxy dropbear n4-healthcheck.timer
  if [[ $SLOWDNS_ENABLED -eq 1 ]]; then systemctl enable --now slowdns || true; fi
  systemctl restart vpn-ssh ws-proxy dropbear
  if [[ $SLOWDNS_ENABLED -eq 1 ]]; then systemctl restart slowdns || true; fi

  echo
  echo -e "${C2}${B}INSTALLATION COMPLETE${N}"
  echo "Host: $HOST_DOMAIN"
  echo "Admin SSH: 22 (protected)"
  echo "VPN SSH: $VPN_SSH_PORT"
  echo "WebSocket: $WS_PORTS"
  echo "Dropbear: $DROPBEAR_PORTS"
  if [[ $SLOWDNS_ENABLED -eq 1 ]]; then echo "SlowDNS: UDP/53 • $NS_DOMAIN"; else echo "SlowDNS: disabled"; fi
  echo
  echo "Vultr Cloud Firewall must allow the same ports. Menu auto-opens on the next interactive root login."
}
main "$@"
