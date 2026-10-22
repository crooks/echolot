# Running an Echolot pinger for yamn remailers

A pinger regularly mails test messages ("pings") through every remailer and
measures whether and how fast they come back. It publishes two files that
yamn clients download to choose their routes:

- `pubring.mix`: every remailer's current public key
- `mlist2.txt`: latency and reliability stats

This branch is Peter Palfrader's Echolot 2.1.9 with the small changes yamn
needs. The files in this directory turn it into a working yamn pinger on a
current Debian system.

## What's changed compared to stock Echolot

- **`Echolot/Conf.pm`:** yamn's key block (keyid plus a 64-hex-digit public
  key) is accepted in `remailer-key` replies.
  - Patch by Steve Crook (Zax), dated 2016-02-10.
  - Posted to alt.privacy.anon-server on 2019-06-02:
    `<slrnqf7417.u39.admin@fleegle.mixmin.net>`.
  - Without it, Echolot never learns any yamn key.
- **`contrib/yamn/yamn-ping`:** Echolot runs a "mixmaster" program to send a
  ping. This wrapper runs yamn instead, with the right directory and options:
  one copy, no dummy messages, and the From line kept.
- **`contrib/yamn/templates/`:** yamn versions of the `echolot.html`,
  `mlist.html` and `mlist2.html` pages, with the empty Type I (Cypherpunk)
  parts commented out.
  - SEC3's YAMN `echolot.html` is lost. These are rebuilt from the pages
    of Frell's yamn pinger (http://echolot.theremailer.net/yamn/), and
    render the same.
  - The example `pingd.conf` selects them; the stock templates stay as
    they are.
- **Example configuration** for Echolot, the yamn client, mail delivery and
  systemd, a monitoring check, and a self-test that needs no mail server.

Everything else is unchanged Echolot. `pingd(1)` and `pingd.conf(5)` in
`doc/` still apply.

This replaces the "echolot4yamn" bundle and the YAMN Help pages that SEC3
used to publish on sec3.net (now offline).

To run it in Docker or Podman instead, either with Postfix inside or with
the host's mail server, see [docker/README.md](docker/README.md).

## How the pieces fit together

```
pinger+<token>@pinger.example.org  <-- replies, returning pings --+
        |                                                           |
   Postfix (recipient_delimiter = +)                                |
        |  ~/.forward -> procmail                                   |
        v                                                           |
   ~/echolot/mail/  (Maildir)                                       |
        |                                                           |
   pingd (Echolot) --- remailer-key / remailer-conf requests ----> remailers
        |                         (via /usr/sbin/sendmail)          ^
        |  writes ~/yamn/pubring.mix (one key), then runs           |
        +--> contrib/yamn/yamn-ping -m -S -l <nick>                 |
                 |                                                  |
              yamn client (~/yamn/yamn.yml) ---- encrypted ping ----+
        |
   ~/echolot/results/  pubring.mix, mlist2.txt, *.html  --> web server
```

## Requirements

- **System:** a Debian 13 server (other systems work the same way with
  their own package names).
- **A mail domain for the pinger.** Remailers must be able to deliver to
  it, and it must be allowed to send mail: correct MX, SPF and reverse DNS,
  as for any mail server.
- **Packages:**
  ```
  apt install perl libgnupg-interface-perl libhtml-template-perl gnupg \
              procmail postfix
  ```
  You also need a web server to publish the results.
- **The yamn binary** in `/usr/local/bin/yamn`, built from
  https://github.com/crooks/yamn, the yamn the remailers run. Forks such as
  https://github.com/go-while/yamn work too: the self-test passes with both,
  and `yamn-ping` adapts to the version it finds.
  ```
  git clone https://github.com/crooks/yamn && cd yamn && go build
  install -m 755 yamn /usr/local/bin/yamn
  ```

## 1. The pinger account

```
adduser --disabled-password --gecos "Echolot pinger" pinger
```

Everything below runs as this user, except for the Postfix, systemd and web
server steps. `pingd` refuses to run as root.

## 2. Get Echolot

As user `pinger`:
```
git clone -b yamn https://github.com/go-while/echolot ~/echolot
```

## 3. Mail delivery

Echolot sends every request from its own address `pinger+<token>@<domain>`
and reads the replies from a Maildir.

1. **Postfix: plus addresses.** In `/etc/postfix/main.cf`, make sure
   `recipient_delimiter = +` is set (Debian usually has it already). Then run
   `systemctl reload postfix`. Other MTAs need their equivalent of
   user-defined mailboxes.

2. **Deliver the pinger's mail into Echolot's Maildir.** As user `pinger`:
   ```
   mkdir -p ~/echolot/mail/new ~/echolot/mail/cur ~/echolot/mail/tmp
   cp ~/echolot/contrib/yamn/dot-forward    ~/.forward
   cp ~/echolot/contrib/yamn/dot-procmailrc ~/.procmailrc
   chmod 600 ~/.forward ~/.procmailrc
   ```
   This only affects the pinger account; no server-wide `mailbox_command`
   is needed.

3. **Test it:**
   ```
   echo test | mail -s test pinger+test@pinger.example.org
   ```
   The mail must show up in `~/echolot/mail/new/`. If not, look in
   `~/procmail.log` and `/var/log/mail.log`.

## 4. The yamn client for pings

```
mkdir ~/yamn
cp ~/echolot/contrib/yamn/yamn.yml ~/yamn/yamn.yml
```

In `~/yamn/yamn.yml`, change `pinger@pinger.example.org` (twice) to your
pinger's address. The file explains each setting.
- `urls.fetch: false`: Echolot writes the keyring.
- `num_copies: 1`.
- `use_expired: true`.

Leave the rest alone, and don't add a `files:` section. `yamn-ping` runs
yamn with `--dir ~/yamn`, so the keyring and pool stay in that directory.

## 5. Configure Echolot

```
cp ~/echolot/contrib/yamn/pingd.conf ~/echolot/pingd.conf
```

Edit `~/echolot/pingd.conf`.
- **Always change:** `sitename`, `my_localpart`, `my_domain` and
  `operator_address`.
- **Check:** the paths of `mixmaster` and `mixhome`, if your home directory
  isn't `/home/pinger`.

The example also changes some Echolot defaults:

| Setting | Echolot default | Example | Why |
|---|---|---|---|
| `do_pings`, `which_chainpings` | Type I and II | Type II (`mix`) only | yamn remailers have no Cypherpunk interface |
| `getkeyconf_every_nth_time` | 288 (daily) | 72 (every 6 h) | a new remailer key is picked up within hours, not after a day. The cost: each remailer gets 5 request mails every 6 hours |
| `buildkeys` | 8 h | 1 h | `pubring.mix` is rebuilt soon after a new key arrives |
| `addresses_default_ttl` | 5 | 20 | a remailer is still disabled after about 5 days without replies |
| `pidfile` | `pingd.pid` | `/run/echolot/pingd.pid` | see "Stale pid file" below |
| `templates` | `templates/*.html` | `contrib/yamn/templates/` for the index, `mlist` and `mlist2` | no empty Cypherpunk sections |

**Upgrading an existing pinger:** copy the `templates` block from
`contrib/yamn/pingd.conf` into your `pingd.conf` and restart pingd. The
pages change at the next `buildstats`.

## 6. Start pingd with systemd

As root:
```
cp /home/pinger/echolot/contrib/yamn/echolot.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now echolot
systemctl status echolot
```

- **Config changes:** after changing `pingd.conf`, run
  `systemctl restart echolot`.
- **Log:** `~/echolot/pingd.log`.
- **Binary location:** the unit sets `YAMN=/usr/local/bin/yamn`; change that
  line if the binary is elsewhere.

## 7. Add the remailers

As user `pinger`, with pingd running:
```
cd ~/echolot
for a in yamn@mixmin.net yamn2@mixmin.net yamn3@mixmin.net yamn4@mixmin.net \
         nyam@remailer.frell.eu.org yamn@virebent.art; do
    ./pingd add "$a"
done
./pingd getkeyconf
```

This list is from October 2026; compare it with the other pingers' stats
(see [PINGERS.md](PINGERS.md)).
- **Wait for replies:** they usually take a few minutes. Watch
  `tail -f pingd.log` for lines such as
  `Setting mix key for yamn@mixmin.net: …`.
- **First build:** afterwards, run once:
  ```
  ./pingd buildkeys
  ./pingd buildstats
  ./pingd buildthesaurus
  ```
  Later this happens automatically.
- **Stats need time:** pings go out to each remailer every 2 hours, and the
  stats cover 12 days. They are meaningful after a day and complete after
  12.

## 8. Publish the results

Serve only `~/echolot/results/`, read-only. Never serve the home directory,
`pingd.conf` or the Maildir.

1. Create the index page:
   ```
   ln -sf echolot.html ~/echolot/results/index.html
   ```
2. Configure the web server. For nginx:
   ```
   location /yamn/ {
       alias /home/pinger/echolot/results/;
   }
   ```
   The web server user needs read access to that directory (and execute
   access on its parent directories).

Clients then use `https://<your-host>/yamn/pubring.mix` and `…/mlist2.txt`.

- **With current yamn:** add your pinger to `urls.pingers` next to the
  others ([PINGERS.md](PINGERS.md) lists the known ones);
  `key_quorum` makes clients use only keys that several pingers agree on.
- **Announce it:** announce new pingers on alt.privacy.anon-server, as
  usual.

## 9. Monitoring

A pinger can stop without anyone noticing: in 2026 one was down for a
month. `check-pinger` reports an Echolot that has stopped rebuilding its
files or whose pings no longer come back. Run it from the pinger's crontab
(cron mails any output):
```
MAILTO=admin@example.org
*/30 * * * * /home/pinger/echolot/contrib/yamn/check-pinger
```

## 10. Self-test without a mail server

`contrib/yamn/test/selftest.sh` runs this Echolot tree against a local yamn
remailer. A small fake `sendmail` moves the mails between them, so no MTA or
network is needed. It checks the whole cycle:
1. key and conf requests;
2. `pubring.mix`;
3. a ping through yamn and back;
4. `mlist2.txt`;
5. the yamn HTML pages.

Run it as a normal user, before installing or after changing anything:
```
YAMN=/usr/local/bin/yamn contrib/yamn/test/selftest.sh
```
It ends with `PASS`, or shows where it failed together with the logs.

## Things to know

- **Expired keys:** Echolot keeps publishing and pinging a key until it
  hasn't seen it for 5 days (`expire_keys`), even after its expiry date.
  yamn clients skip expired keys. That's also why the ping client has
  `use_expired: true`.
- **Failed sends count as lost pings:** if yamn can't send a ping, Echolot
  still records it as sent. A local mail problem then looks like a bad
  remailer; `check-pinger` helps tell them apart.
- **Middle remailers:** a remailer with the `middle` capability can't deliver
  the ping itself. It forwards it through an exit of its own choice, so its
  stats include a second hop.
  - Mixmaster middlemen could deliver pings directly if the pinger's
    address was in their `dest.alw`, e.g. `/pinger.*\@/` (Zax, 2015-03-18,
    `<slrnmgk2su.h7m.admin@snorky.mixmin.net>`). yamn has no such list.
- **Key changes cost a few days of uptime:** when a remailer replaces its
  key, Echolot pings the old and the new key. Once the remailer has deleted
  the old key, the pings to it are lost, and they count against the
  remailer. Its uptime can drop to about 50% until Echolot drops the old
  key with its pings, 5 days after it last saw it (`expire_keys`). Zax saw
  this with yamn and Mixmaster 4096-bit keys (2015-04-15,
  `<slrnmis8at.m9.admin@snorky.mixmin.net>`).
- **`remailer-stats`:** yamn doesn't answer it; Echolot logs nothing about
  that, and it's harmless.
- **Commands:** `./pingd add`, `getkeyconf` etc. only queue a command and
  signal the running pingd. They must run as the pinger user while the
  service is running.

## Troubleshooting

- **`Pidfile '…' exists` at start.**
  - The cause: `pingd` only removes a stale pid file if no process with that
    pid exists. After a reboot the pid often belongs to another process, so
    pingd refuses to start. A pinger stayed down for a month this way.
  - The example setup keeps the pid file in `/run/echolot`, which systemd
    empties at every stop and boot.
  - With an older setup, delete the file by hand when pingd isn't running.
- **No `Setting mix key` lines in `pingd.log`, and an empty `pubring.mix`.**
  The `Conf.pm` patch is missing: stock Echolot can't read yamn keys. Check
  that you are on the `yamn` branch.
- **`Mixmaster said on stderr: …` in `pingd.log`.** yamn reported a problem
  sending a ping; the message says what.
  - `Pubring import failed`: `~/yamn/yamn.yml` has a `files:` section. Remove
    it.
  - Mail errors: check `mail.pipe` in `~/yamn/yamn.yml`.
- **Requests go out, but nothing comes back.** Mail delivery to the pinger is
  broken; see step 3. Also check that the remailers can reach your domain
  (MX, SPF).

## Credits

- Echolot © Peter Palfrader (GPL v2 or later); upstream at
  https://git.noreply.org/projects/echolot.git.
- yamn and the yamn patch for Echolot: Steve Crook (Zax); his copy of Echolot
  is at https://github.com/crooks/echolot.
- The original yamn pinger tutorials: SEC3 (YAMN Help, sec3.net).
- The yamn pages in `templates/`: rebuilt from the pages of Frell's yamn
  pinger.
