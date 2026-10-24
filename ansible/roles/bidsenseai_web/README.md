# bidsenseai_web

Not part of the house; see
[docs/decisions.md](../../../docs/decisions.md#bidsense-ai-web-in-its-own-container).

Serves the BidSense AI static site from `/srv/bidsenseai-web/current` with nginx on
`192.168.1.81:8080`, for the central Caddy only (`bidsenseai.homeserver.lan`). The guest has no
credentials and nothing else on it. nginx sends the headers that the page's meta CSP cannot
carry (`frame-ancestors`, `object-src`, `base-uri`, nosniff, referrer policy, noindex) and
long-lived caching for `/_astro/`.

## Deploy

The `bidsenseai_extractor` role builds the site and uploads it:

1. `rsync` to `releases/<UTC timestamp>/` as the `deploy` user.
2. `ssh deploy@... switch <timestamp>` repoints `current` and prunes to the last 3 releases
   (`bidsenseai_web_keep_releases`).

The `deploy` user's `authorized_keys` entry is `command="/usr/local/sbin/bidsenseai-web-deploy
...",restrict <key>`. The command accepts only `rsync --server` (executed through
`rrsync -wo /srv/bidsenseai-web/releases`, so write-only and confined) and `switch <name>`
(name must match `YYYYMMDDTHHMMSSZ`, the release must have `index.html` and no symlinks).
`authorized_keys` and `.ssh` are owned by root. The key pair is generated on the extractor;
this play reads its public half from there, so run the extractor play first or together:

`ansible-playbook site.yml --limit bidsenseai_extractor:bidsenseai_web`

Rollback: `ln -sfn releases/<older> /srv/bidsenseai-web/current` on the guest.

Variables and defaults: `defaults/main.yml`.
