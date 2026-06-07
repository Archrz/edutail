#!/bin/sh
# EduTail: EduVPN + Tailscale subnet router. K8s pod: set LOCAL_ROUTES and NM_MANAGE_LAN=1.
export SYSTEMD_OFFLINE=1

TS_SOCK=/var/run/tailscale/tailscaled.sock
LAN_IF=${LAN_IF:-eth0}

vpn_if() {
	ip link show eduVPN >/dev/null 2>&1 && { echo eduVPN; return; }
	ip link show tun0 >/dev/null 2>&1 && { echo tun0; return; }
	return 1
}

gw() { ip route show default dev "$1" 2>/dev/null | awk '/^default/{print $3;exit}'; }

vpn_routes() {
	dev=$(vpn_if) || return 0
	{
		ip -4 route show dev "$dev" 2>/dev/null \
			| awk '/^default/ { next } /proto kernel/ && /scope link/ { next } { print $1 }'
		[ -n "${ADVERTISE_ROUTES:-}" ] && printf '%s\n' "$ADVERTISE_ROUTES" | tr ',' '\n'
	} | sort -u | paste -sd, -
}

local_routes() {
	[ -n "${LOCAL_ROUTES:-}" ] || return 0
	g=$(gw "$LAN_IF") || return 0
	ip link show "$LAN_IF" >/dev/null 2>&1 || return 0
	IFS=,
	for c in $LOCAL_ROUTES; do
		c=$(echo "$c" | tr -d ' ')
		[ -n "$c" ] && ip route replace "$c" via "$g" dev "$LAN_IF" metric 1 2>/dev/null || true
	done
	IFS=$(printf '\n')
}

ts_routes() {
	[ -S "$TS_SOCK" ] && tailscale --socket="$TS_SOCK" set --advertise-routes="$1" 2>/dev/null || true
}

watch() {
	last=; n=0
	while true; do
		local_routes
		if vpn_if >/dev/null 2>&1; then
			r=$(vpn_routes)
			[ "$r" = "$last" ] || { ts_routes "$r"; last=$r; }
		else
			[ -z "$last" ] || { ts_routes ""; last=; }
			[ $((n % 4)) -eq 0 ] && eduvpn-cli connect -t -n 1 || true
		fi
		n=$((n + 1)); sleep 5
	done
}

nm_lan() {
	ip=$(ip -4 -o addr show dev "$LAN_IF" 2>/dev/null | awk '{print $4;exit}') || return 0
	[ -n "$ip" ] || return 0
	g=$(gw "$LAN_IF")
	nmcli con delete "pod-$LAN_IF" 2>/dev/null || true
	set -- ipv4.method manual ipv4.addresses "$ip" ipv6.method ignore ipv4.ignore-auto-dns yes ipv4.dns-priority 50
	[ -n "$g" ] && set -- "$@" ipv4.gateway "$g"
	nmcli con add type ethernet con-name "pod-$LAN_IF" ifname "$LAN_IF" autoconnect yes "$@"
	nmcli -w 45 con up "pod-$LAN_IF" ifname "$LAN_IF" || nmcli -w 45 device connect "$LAN_IF" || true
}

ts_start() {
	: "${TS_AUTHKEY:?}"
	tailscaled --state=/persist/ts/tailscaled.state --socket="$TS_SOCK" &
	i=0; while [ $i -lt 30 ]; do [ -S "$TS_SOCK" ] && break; i=$((i + 1)); sleep 1; done
	[ -S "$TS_SOCK" ] || exit 1
	tailscale --socket="$TS_SOCK" up \
		--auth-key="$(printf %s "$TS_AUTHKEY" | tr -d '\r\n')" \
		--hostname="${TS_HOSTNAME:-edutail}" --snat-subnet-routes=true --accept-dns=false
}

sysctl -w net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1 2>/dev/null || true
mkdir -p /persist/ts /persist/eduvpn /persist/keyrings /root/.config /root/.local/share /run/dbus /var/run/tailscale
ln -sfn /persist/eduvpn /root/.config/eduvpn
ln -sfn /persist/keyrings /root/.local/share/keyrings
for o in eduVPN tun+ wg+; do
	iptables -t nat -C POSTROUTING -o "$o" -j MASQUERADE 2>/dev/null \
		|| iptables -t nat -A POSTROUTING -o "$o" -j MASQUERADE 2>/dev/null || true
done
dbus-daemon --system --fork 2>/dev/null || true
if [ -x /usr/lib/systemd/systemd-udevd ]; then
	mkdir -p /run/udev/rules.d
	/usr/lib/systemd/systemd-udevd --daemon 2>/dev/null || true
	udevadm control --reload-rules 2>/dev/null || true
	udevadm trigger --action=add --subsystem-match=net 2>/dev/null || true
	udevadm settle --timeout=8 2>/dev/null || true
fi

watch &
ts_start
NetworkManager --no-daemon &
sleep 5
[ "${NM_MANAGE_LAN:-0}" = 1 ] && { nmcli dev set "$LAN_IF" managed yes 2>/dev/null || true; nm_lan; }
exec tail -f /dev/null
