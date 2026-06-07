# edutail

EduTail is a container that runs **EduVPN** and **Tailscale** together as a subnet router. It connects your university VPN routes to a Tailscale network, so you can reach on-campus resources from anywhere.

Built for Kubernetes pods. Configure routes with `LOCAL_ROUTES` and `ADVERTISE_ROUTES`.

## Route examples

**`LOCAL_ROUTES`** — comma-separated subnets reachable via the pod LAN interface (`eth0`). EduTail adds routes so traffic to these networks goes through the pod gateway.

```yaml
env:
  - name: LOCAL_ROUTES
    value: "10.42.0.0/16,192.168.1.0/24"
```

Example: `10.42.0.0/16` is your cluster pod network; `192.168.1.0/24` is a LAN behind the pod.

**`ADVERTISE_ROUTES`** — comma-separated subnets to advertise on Tailscale, in addition to routes automically learned from EduVPN.

```yaml
env:
  - name: ADVERTISE_ROUTES
    value: "172.16.10.0/24,10.0.50.0/24"
```

Example: `172.16.10.0/24` is a university lab network; `10.0.50.0/24` is an internal service subnet. Tailscale clients can then reach these via the EduTail node (after you approve the routes in the Tailscale admin console).

**Both together** in a pod:

```yaml
env:
  - name: LOCAL_ROUTES
    value: "10.42.0.0/16"
  - name: ADVERTISE_ROUTES
    value: "172.16.10.0/24"
  - name: NM_MANAGE_LAN
    value: "1"
  - name: TS_AUTHKEY
    valueFrom:
      secretKeyRef:
        name: tailscale-auth
        key: TS_AUTHKEY
```
