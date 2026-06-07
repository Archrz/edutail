# edutail

**edutail** runs EduVPN and Tailscale in one container and acts as a subnet router between them. Connect to your university VPN, share those routes over Tailscale, and reach campus networks from anywhere through tailscale.

It's built to run in Kubernetes, but you can also run it with Docker.

## Usage

Pull the image:

```bash
docker pull ghcr.io/archrz/edutail:latest
```

Or build it yourself:

```bash
docker build -t edutail .
```

Run it locally (needs `--privileged` and a volume so VPN state survives restarts):

```bash
docker run -d --privileged \
  -e TS_AUTHKEY=tskey-auth-xxxxx \
  -v edutail-state:/persist \
  ghcr.io/archrz/edutail:latest
```

For Kubernetes, deploy it as a privileged pod with `NM_MANAGE_LAN=1`. See the [full pod example](#kubernetes-example) at the bottom.

## Environment variables

| Variable           | Default    | What it does                                                          |
|--------------------|:----------:|-----------------------------------------------------------------------|
| `TS_AUTHKEY`       | —          | Tailscale auth key. Required.                                         |
| `TS_HOSTNAME`      | `edutail`  | Name of this node in Tailscale                                        |
| `LOCAL_ROUTES`     | —          | Subnets behind the pod that edutail should route to.                  |
| `ADVERTISE_ROUTES` | —          | Extra subnets to share on Tailscale.                                  |
| `NM_MANAGE_LAN`    | `0`        | Set to `1` if using in Kubernetes so NM handles the interface         |
| `LAN_IF`           | `eth0`     | LAN interface to use                                                  |
| `HEALTHCHECK_URL`  | —          | Optional URL for the readiness probe                                  |

## Local routes

Use `LOCAL_ROUTES` when the pod needs to reach networks on its LAN side — like your cluster service network or a pod CIDR. Pass multiple subnets as a comma-separated list:

```yaml
env:
  - name: LOCAL_ROUTES
    value: "10.42.0.0/16,192.168.1.0/24"
```

edutail adds a route for each subnet via the pod gateway on `eth0`, and keeps them updated every 5 seconds.

## Advertise routes

Use `ADVERTISE_ROUTES` to share extra subnets over Tailscale on top of whatever EduVPN already provides. You can list several at once:

```yaml
env:
  - name: ADVERTISE_ROUTES
    value: "172.16.10.0/24,10.0.50.0/24,192.168.50.0/24"
```

edutail combines the EduVPN routes with your `ADVERTISE_ROUTES`, then pushes the full list to Tailscale. It checks for changes every 5 seconds — so if EduVPN reconnects or picks up new routes, Tailscale gets updated too.

You'll still need to approve the routes in the [Tailscale admin console](https://login.tailscale.com/admin/machines) before other devices can use them.

## DNS

edutail doesn't configure DNS on its own. In Kubernetes, set it on the pod so internal names still resolve while you're on VPN:

```yaml
dnsPolicy: None
dnsConfig:
  nameservers:
    - 203.0.113.1    # campus DNS
    - 203.0.113.2    # campus DNS backup
    - 10.96.0.10     # cluster DNS
  searches:
    - campus.example.edu
  options:
    - name: ndots
      value: "2"
```

Point `nameservers` at your campus resolvers and your cluster DNS IP. `searches` is the domain suffix DNS adds to short names — so `myserver` becomes `myserver.campus.example.edu`.

## Kubernetes example

```yaml
spec:
  dnsPolicy: None
  dnsConfig:
    nameservers: [203.0.113.1, 203.0.113.2, 10.96.0.10]
    searches: [campus.example.edu]
    options: [{name: ndots, value: "2"}]
  containers:
    - name: edutail
      image: ghcr.io/archrz/edutail:latest
      securityContext:
        privileged: true
      env:
        - {name: TS_HOSTNAME, value: edutail}
        - {name: NM_MANAGE_LAN, value: "1"}
        - {name: LOCAL_ROUTES, value: "10.42.0.0/16,10.244.0.0/16"}
        - name: TS_AUTHKEY
          valueFrom:
            secretKeyRef:
              name: edutail
              key: ts-authkey
        - {name: ADVERTISE_ROUTES, value: "172.16.10.0/24,10.0.50.0/24"}
        - {name: HEALTHCHECK_URL, value: "https://myserver.campus.example.edu/"}
      readinessProbe:
        exec:
          command:
            - sh
            - -ec
            - ip link show eduVPN >/dev/null 2>&1 || ip link show tun0 >/dev/null 2>&1; [ -z "$HEALTHCHECK_URL" ] || curl -fsSk --max-time 15 -o /dev/null "$HEALTHCHECK_URL"
        initialDelaySeconds: 45
        periodSeconds: 120
        timeoutSeconds: 20
```
