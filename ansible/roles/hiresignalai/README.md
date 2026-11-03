# hiresignalai

Not part of the house; see
[docs/decisions.md](../../../docs/decisions.md#hiresignal-ai-outside-the-house).

Runs the private HireSignal AI job-search assistant as the `hiresignalai` user, with a Claude
Code subscription token: `jobsearch daily` every day at 08:00 Europe/Madrid
(`hiresignalai-daily.timer`) and the Telegram bot `jobsearch bot` as a long-running service
(`hiresignalai-bot.service`, long polling, nothing exposed), and the web dashboard
`jobsearch web --allow-writes` (`hiresignalai-web.service`).

- Dashboard: listens on `hiresignalai_web_host:hiresignalai_web_port` (the guest address,
  `192.168.1.85:8080`), so it is also reachable directly on the home LAN, never from the internet.
  The caddy guest publishes it as `https://hiresignalai.homeserver.lan` (entries in
  `group_vars/caddy.yml` and `pihole.yml`); tailnet clients resolve that name through Caddy's own
  DNS to Caddy's tailnet address, and Caddy forwards the `Host` header unchanged.
  `hiresignalai_web_allowed_hosts` feeds `--allowed-host` (quoted). `hiresignalai_web_extra_args`
  is appended as raw text (systemd splits it on whitespace and expands `%` and `$`).
- Dashboard secrets: `HIRESIGNALAI_DASHBOARD_TOKEN` (role variable `hiresignalai_web_token`) and
  the extension origin (`hiresignalai_web_extension_origin`) go to `/etc/hiresignalai/web.env`
  (root, 0600), loaded only by the web unit. The unit also loads the shared `env`: it runs
  tailoring (Claude) and publishes (git), and notifies by Telegram.
- Dashboard protections: pages have no login (see the accepted risk in docs/decisions.md). Writes
  outside `/api` need the `HX-Request` header and, when the browser sends an `Origin`, one that
  matches the `Host` (the app's CSRF guard), so a page in your browser cannot change statuses
  from another site. `/api` needs the token and the extension origin.
- The token check (16 or more characters of `A-Z a-z 0-9 + / = _ -`) is skipped in check mode,
  like the other secret checks.
- Repository: checked out over SSH with a deploy key that has write access, tracking `main`
  (`hiresignalai_repo_ref`). The service commits and pushes `data/jobs.db`, so this guest is its
  only writer.
- Self-update: `hiresignalai-update.timer` runs `hiresignalai-update.service` every day at 07:45
  Europe/Madrid (`Persistent=true`), before the 08:00 daily run, so pushes to `main` reach
  production without running Ansible. It runs `/usr/local/sbin/hiresignalai-update` as root,
  which runs git and uv as the service user:
  - Refuses to run (non-zero exit, failure alert) if `hiresignalai-daily.service` is running.
  - `git fetch` and a fast-forward merge (or a plain merge when the service has pushed data
    commits in the meantime) under the app's lock (`flock` on `data/.jobs.lock`). It fails if the
    tree is dirty or the merge conflicts (the merge is aborted); it never rebases, resets or
    forces.
  - Then `uv sync --locked --no-dev`, and `hiresignalai-bot` and `hiresignalai-web` are restarted
    if HEAD changed (every unit is tried; a failed restart makes the script exit non-zero, and a
    unit that is not installed is skipped). It
    prints the old and new HEAD.
  - It runs whatever is on `main` (accepted risk, see docs/decisions.md). Ansible is only needed
    for infrastructure changes: units, environment, tool versions.
- Deploy flow (re-run the play): fails if `hiresignalai-daily.service` is running (wait and
  re-run), then runs the same script; the bot and the dashboard are restarted when HEAD changed or
  when their unit or environment changes.
- Tools at pinned versions with checksums: uv, Claude Code, typst; Python is pinned to a full
  3.12 patch version. The units mount the user's `~/.ssh` and `~/.gitconfig` read-only.
- The bot and the dashboard restart on failure after 30 s, at most 5 times in 10 minutes, so a crash loop
  raises the failure alert.
- Configuration in `/etc/hiresignalai/` (`env`, `alerts.env`). The git identity and the SSH
  command for pushing are in the user's `~/.gitconfig`.
- The HireSignal AI bot (`HIRESIGNALAI_TELEGRAM_*`) is distinct from the house alerts bot. A failed
  unit sends a Telegram message through the house bot with
  `OnFailure=hiresignalai-alert@%n.service`; `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`
  must both be in `.env`; run the `alerts` role first, which writes the chat id there.
- Variables and defaults: `defaults/main.yml`. Secrets come from `.env`; see `.env.example`.

Run: `ansible-playbook site.yml --limit hiresignalai`.

## Yearly renewal

The Claude Code token (`claude setup-token`) lasts one year. Update `CLAUDE_CODE_OAUTH_TOKEN`
in `.env` (shared with the extractor) and re-run the play.
