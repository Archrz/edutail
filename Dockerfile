# EduTail: EduVPN + Tailscale subnet router. K8s pod: set LOCAL_ROUTES and NM_MANAGE_LAN=1.
FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive SYSTEMD_OFFLINE=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates curl gnupg dbus network-manager udev iproute2 iptables \
  && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
       | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main" \
       > /etc/apt/sources.list.d/tailscale.list \
  && curl -fsSL https://app.eduvpn.org/linux/v4/deb/app+linux@eduvpn.org.asc \
       | gpg --dearmor -o /usr/share/keyrings/eduvpn-v4.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/eduvpn-v4.gpg] https://app.eduvpn.org/linux/v4/deb/ noble main" \
       > /etc/apt/sources.list.d/eduvpn-v4.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends tailscale eduvpn-client \
  && rm -f /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf \
          /usr/lib/NetworkManager/conf.d/10-dns-resolved.conf \
  && apt-get clean && rm -rf /var/lib/apt/lists/* \
  && printf '%s\n' \
       '[main]' 'plugins=keyfile' 'dhcp=internal' 'dns=default' '' \
       '[keyfile]' 'unmanaged-devices=interface-name:tailscale0;interface-name:lo' '' \
       '[device-tailscale0]' 'match-device=interface-name:tailscale0' 'managed=false' '' \
       '[device-eth0]' 'match-device=interface-name:eth0' 'managed=true' \
       > /etc/NetworkManager/conf.d/99-edutail.conf \
  && printf '%s\n' \
       'SUBSYSTEM=="net", ACTION=="add|change", KERNEL=="eth0", ATTR{type}=="1", ENV{ID_NET_DRIVER}="veth", ENV{NM_UNMANAGED}="0"' \
       > /etc/udev/rules.d/99-nm-pod-eth0-managed.rules

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
