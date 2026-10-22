# Echolot yamn pinger in Docker or Podman

Two images, built from the same `Dockerfile`:

| Image (target) | Mail | For |
|---|---|---|
| `standalone` | Postfix inside, port 25 | a bare machine with only Docker or Podman |
| `hostmail` | no MTA; the host's mail server delivers into the volume, and the container sends through it (msmtp) | a host that already runs a mail server |

Both images contain:
- **Echolot** with the yamn patch;
- **yamn**, built from https://github.com/crooks/yamn. Choose another version or fork with `--build-arg YAMN_REPO=… --build-arg YAMN_REF=…`;
- **the files from `contrib/yamn/`**.

`pingd` runs as user `pinger` (UID 10000). All state lives in the volume
`/var/lib/echolot`:
- `pingd.conf`;
- `data/` (12 days of ping history);
- `results/` (`pubring.mix`, `mlist2.txt`, HTML);
- `mail/` (the Maildir);
- `mixhome/` (the yamn client).

Build from the root of this repository:
```
docker build -f contrib/yamn/docker/Dockerfile --target standalone -t echolot-yamn:standalone .
docker build -f contrib/yamn/docker/Dockerfile --target hostmail   -t echolot-yamn:hostmail .
```
Or use the compose files in this directory, which build the image themselves.

## Check an image

```
docker run --rm echolot-yamn:standalone selftest
```
This runs `contrib/yamn/test/selftest.sh` inside the image. A local yamn
remailer and a fake sendmail run the whole cycle without network access:
1. key and conf requests;
2. `pubring.mix`;
3. a ping and its return;
4. `mlist2.txt`;
5. the yamn HTML pages.

It ends with `PASS`.

## Settings

On its first start the container writes `pingd.conf` and
`mixhome/yamn.yml` into the volume from these variables. Later starts keep
those files, so edit them or delete them to change the settings.

A `pingd.conf` written by an older image uses Echolot's stock HTML pages,
with empty Cypherpunk sections. To get the yamn pages, add the
`templates` block from `entrypoint.sh` to it, or delete it so the next
start writes a new one.

| Variable | Default | Meaning |
|---|---|---|
| `PINGER_DOMAIN` | (required) | The pinger receives mail as `pinger+<token>@PINGER_DOMAIN`. |
| `PINGER_LOCALPART` | `pinger` | The local part of that address. |
| `PINGER_SITENAME` | the domain | Shown on the stats pages. |
| `PINGER_OPERATOR` | `postmaster@<domain>` | A human, named in every request mail. Use an address outside the pinger's domain. |
| `PINGER_REMAILERS` | | Remailer addresses added on the first start. |
| `PINGER_LOGLEVEL` | `info` | Echolot's log level. |
| `PINGER_LOG` | `stdout` | `stdout` copies `pingd.log` to the container log. |
| `PINGER_UID`, `PINGER_GID` | 10000 | The pinger's IDs. For `hostmail`, set them to the owner of the mounted directory. |

Only for `standalone` (Postfix):

| Variable | Default | Meaning |
|---|---|---|
| `PINGER_HOSTNAME` | the domain | Postfix's `myhostname`. |
| `TLS_CERT`, `TLS_KEY` | self-signed in the volume | The certificate for incoming STARTTLS, e.g. from certbot. Postfix is reloaded when the file changes. |
| `INET_PROTOCOLS` | `all` | `ipv4` if the host's IPv6 address has no reverse DNS. |
| `RELAYHOST`, `RELAY_USER`, `RELAY_PASSWORD` | | Send everything through a relay (e.g. `[smtp.example.net]:587`) instead of directly. |
| `TRANSPORT_MAPS` | | Per-domain routes, separated by `;`, e.g. `mixmin.net smtp:[fleegle.mixmin.net]:2525`. `smtps:` uses TLS from the start (port 465). |
| `POSTMASTER_TO` | the operator | Where mail for root, postmaster and abuse goes; `pinger` discards it. |

Only for `hostmail` (msmtp):

| Variable | Default | Meaning |
|---|---|---|
| `SMTP_HOST` | (required) | The mail server to send through. |
| `SMTP_PORT` | `25` | |
| `SMTP_TLS` | `starttls` | `off`, `starttls` or `on` (TLS from the start). |
| `SMTP_TLS_VERIFY` | `on` | `off` to accept any certificate. |
| `SMTP_USER`, `SMTP_PASSWORD` | | Login, if the server needs one. |

## Standalone: a bare machine with Docker or Podman

1. **DNS for `PINGER_DOMAIN`:**
   - A (and MX) records pointing to the host;
   - a PTR record for its IP;
   - SPF, e.g. `v=spf1 mx a -all`.
   Remailers must be able to deliver to port 25, and their mail servers
   must accept the pinger's mail.
2. **Configure:** edit `compose.standalone.yml` (domain, operator,
   certificate), then:
   ```
   docker compose -f compose.standalone.yml up -d --build
   docker compose -f compose.standalone.yml logs -f
   ```
   The `web` service publishes the results at `http://<host>:8080/yamn/`.
   `nginx-yamn.conf` is mounted as a single file, so after editing it,
   restart the service (`docker compose … restart web`). A reload alone
   keeps reading the old file.
   To use a web server on the host instead, remove the service and serve
   the volume's `results/` directory read-only. Or keep the service on
   `127.0.0.1:8080` and proxy `/yamn/` to it from the host's TLS server.
3. **No open relay:** Postfix accepts mail only for `PINGER_DOMAIN` and
   relays only for localhost. Never add the Docker network to
   `mynetworks`. With Docker's port forwarding, outside clients can appear
   to come from the Docker gateway, and the pinger would become an open
   relay.

### Port 25 blocked outbound

Many VPS providers block outgoing connections to port 25. Then:
- **Ask the provider to unblock it.** That's the best option for a
  permanent pinger.
- **Or use a relay:** `RELAYHOST` with `RELAY_USER`/`RELAY_PASSWORD`, on
  port 587. Add the relay to the domain's SPF record.
- **Or route the remailers' domains to ports they also accept** with
  `TRANSPORT_MAPS`. All the pinger's outgoing mail goes to remailers. On
  2026-10-21 these worked without a login:
  ```
  mixmin.net             smtp:[fleegle.mixmin.net]:2525
  remailer.frell.eu.org  smtp:[mail2.frell.eu.org]:2525
  virebent.art           smtps:[mail.virebent.art]:465
  ```
  A new remailer, or a remailer moving to another mail server, needs a
  new entry.

### Podman

The same commands work with `podman` and `podman-compose`. Rootless
Podman can't bind port 25 unless the host allows it:
`sysctl net.ipv4.ip_unprivileged_port_start=25`.

## Hostmail: a host with a mail server

The host's MTA receives the pinger's mail and delivers it into the
mounted directory; the container only runs Echolot.

1. **Create a host account** that owns the directory. Its UID and GID go
   into `PINGER_UID`/`PINGER_GID`:
   ```
   adduser --disabled-password --gecos "Echolot pinger" pinger
   mkdir -p /srv/echolot && chown pinger: /srv/echolot
   ```
2. **Deliver its mail into the volume's Maildir.** With Postfix:
   - set `recipient_delimiter = +`;
   - give the account a `~pinger/.forward` with `"|/usr/bin/procmail"`;
   - give it a `~pinger/.procmailrc` that delivers to `/srv/echolot/mail/`
     (as in `contrib/yamn/dot-procmailrc`).
3. **Let the container send through the host's MTA.** With the default
   bridge network, add `172.17.0.0/16` to Postfix's `mynetworks`, or set up a
   login.
4. **Start it:** in `compose.hostmail.yml`, mount `/srv/echolot` instead of
   `./echolot`, adjust the environment, then:
   ```
   docker compose -f compose.hostmail.yml up -d --build
   ```
5. **Publish** `/srv/echolot/results/` read-only with the host's web server.

## Operating

Commands go to the running pingd through `docker exec`. The `pingd`
wrapper runs them as the pinger user:
```
docker exec <container> pingd add yamn5@example.org
docker exec <container> pingd getkeyconf
docker exec <container> pingd buildkeys
```

- **Health:** the container reports `unhealthy` (`docker ps`) when
  `check-pinger` finds a problem: no rebuilt stats for 30 minutes, no
  rebuilt keyring for 3 hours, or no returned ping for 6 hours.
- **Restarts:** a restart can't leave a stale pid file behind, because
  `/run` is new in every container.
- **If a service dies:** when pingd or Postfix stops, the container exits
  with an error and the restart policy starts it again.

For how the pinger works, the reasons behind the settings, and
troubleshooting, see `../README.md`.
