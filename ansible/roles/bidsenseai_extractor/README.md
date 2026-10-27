# bidsenseai_extractor

Temporary: not part of the house and to be removed; see
[docs/decisions.md](../../../docs/decisions.md#a-temporary-bidsense-ai-extractor-outside-the-house).

Runs `doc-extractor run --pending` from the private BidSense AI repository every night at 02:30 Europe/Madrid, as the `extractor` user, with a Claude Code subscription token and AWS
credentials from IAM Roles Anywhere (`aws_signing_helper` as `credential_process`).

- Repository: checked out over SSH with a read-only deploy key, tracking `main`
  (`bidsenseai_extractor_repo_ref`). Before each run the service executes
  `/usr/local/sbin/bidsenseai-extractor-update` under the flock: `git fetch` with the deploy key and
  pinned host key, `git reset --hard origin/<ref>`, and `uv sync --frozen --package doc-extractor`
  only when `uv.lock` or a `pyproject.toml` changed since the last successful sync (commit kept in
  `~/.cache/bidsenseai-lock/synced.commit`). Any failure fails the unit and sends the alert, so stale
  code never runs silently. A push to `main` is enough.
- Tools at pinned versions with checksums: uv, Claude Code, `aws_signing_helper`.
- Configuration in `/etc/bidsenseai-extractor/` (`env`, `alerts.env`, certificate and key).
- Web: no longer built here. The public site is built daily by AWS CodeBuild
  (`bidsenseai-pro-site`). The play stops and removes `bidsenseai-extractor-web.timer`/`.service`,
  the build script, Node.js and the web work directory if present. `~/.ssh/web_deploy_key` is kept
  because the `bidsenseai_web` role still reads its public half.
- Removed on the previous layout: the site units, nginx and `/srv/bidsenseai` (the play deletes
  them if present).
- A failed extraction run sends a Telegram message through `OnFailure=bidsenseai-extractor-alert@%n.service` (template unit; the failed unit name is passed to the alert script). `TELEGRAM_BOT_TOKEN` and
  `TELEGRAM_CHAT_ID` must both be in `.env`; run the `alerts` role first, which writes the chat id there.
- Variables and defaults: `defaults/main.yml`. Secrets and ARNs come from `.env`; see
  `.env.example`.

Run: `ansible-playbook site.yml --limit bidsenseai_extractor`. This play no longer touches the web
guest.

## Yearly renewal

The Claude Code token (`claude setup-token`) and the end-entity certificate both last one
year. Create the new certificate with the openssl steps in the BidSense AI `infra/README.md`,
section "Homeserver extractor (IAM Roles Anywhere)", update `CLAUDE_CODE_OAUTH_TOKEN` and the
files referenced by `BIDSENSEAI_EXTRACTOR_CERT_FILE` and `BIDSENSEAI_EXTRACTOR_KEY_FILE` in `.env`, and re-run the play.
