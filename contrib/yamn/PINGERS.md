# Known yamn pingers

Collected from alt.privacy.anon-server and alt.privacy.anon-server.stats,
with the Message-IDs of the posts. The status was checked on 2026-10-21.

Each pinger publishes `pubring.mix` and `mlist2.txt` under its base URL.

## Running

| Pinger | Base URL | Notes |
|---|---|---|
| Frell | http://echolot.theremailer.net/yamn/ | Since 2016. Posts "Frelled Yamn Stats" to alt.privacy.anon-server.stats; the first was on 2016-02-23, `<echoyamn1_1456222800_mlist2.txt@msgid.frell.theremailer.net>`. Its pages are the model for `templates/` here. |
| mixmin | https://www.mixmin.net/yamn/ | Zax's pinger. SEC3 reported it gone on 2025-06-02 (`<18454e0a85364fa0$10920$3915$802601b3@news.usenetexpress.com>`), but it is listed again on 2025-11-25 (`<20251125.121320.a222a964@mixmin.net>`) and was current on 2026-10-21. |
| Victor | https://echolot.virebent.art/ | Its own index page: the Type I parts are removed rather than commented out, and there is no From header section. |

## Gone

| Pinger | Base URL | What happened |
|---|---|---|
| Tincture | https://www.tincture.ws/pinger/yamn/ | Closed on 2024-10-26, `<2ae0a71b41c76d1ba12de30a4314795e@msgid.frell.theremailer.net>`. |
| Haph | https://www.haph.org/yamn/ | New in 2021 (`<20211026.213816.f17d2c44@remailer.frell.eu.org>`), closed on 2025-06-05 (`<20250605.155641.d35b5765@msgid.frell.theremailer.net>`). The domain now serves a parking page, so remove it from `urls.pingers`. |
| Barnish | https://www.barnish.org/yamn/ | SEC3's pinger, listed in 2025 (`<18454e0a85364fa0$10920$3915$802601b3@news.usenetexpress.com>`). Not reachable on 2026-10-21. |
| Dirge | https://www.harmsk.com/yamn/ | Listed on 2025-06-02 and 2025-11-25. Not reachable on 2026-10-21. |
| austria | https://www.tahina.priv.at/pinger/yamn/ | In a list of yamn pingers posted on 2021-10-26 (`<20211026.213816.f17d2c44@remailer.frell.eu.org>`). 404 on 2026-10-21. |

## History

- **2014-10-05:** Zax (Steve Crook) announces yamn, "Yet another Mix Net",
  `<slrnm32lsf.veq.admin@snorky.mixmin.net>`.
- **2016-02-10:** Zax's patch that lets Echolot read yamn keys. He posted
  it on 2019-06-02, `<slrnqf7417.u39.admin@fleegle.mixmin.net>`; it is
  in `Echolot/Conf.pm` on this branch.
- **2016-02:** Frell's Echolot starts pinging yamn remailers.
- **2019:** SEC3 runs the "Cloaked Yamn Pinger".
- **2020:** SEC3's YAMN Help tutorial "Install Echolot For YAMN Pinger on a
  VPS" (sec3.net): stock Echolot, Zax's `Conf.pm`, a YAMN
  `templates/echolot.html`, his `pingd.conf` and `yamn.cfg`. From 2021
  they came as one bundle, `echolot4yamn.zip`.
- **2026:** sec3.net is gone, and none of those files were archived. This
  branch replaces them; `templates/` is rebuilt from Frell's pages.

Before yamn, the Mixmaster pingers (SEC3, allpingers.net, austria, deuxpi,
apricot and others) ran the same Echolot.
