# hiresignalai

Not part of the house; see
[docs/decisions.md](../../../docs/decisions.md#hiresignal-ai-outside-the-house).

Runs the private HireSignal AI job-search assistant as the `hiresignalai` user, with a Claude
Code subscription token: `jobsearch daily` every day at 08:00 Europe/Madrid
(`hiresignalai-daily.timer`) and the Telegram bot `jobsearch bot` as a long-running service
(`hiresignalai-bot.service`, long polling, nothing exposed).

- Repository: checked out over SSH with a deploy key that has write access, tracking `main`
  (`hiresignalai_repo_ref`). The service commits and pushes `data/jobs.db`, so this guest is its
  only writer.
- Deploy flow (re-run the play to deploy the latest pushed `main`):
  - Fails if `hiresignalai-daily.service` is running; wait and re-run.
  - The bot is stopped for the deploy and started again afterwards, even if the deploy fails.
  - `git fetch` and a fast-forward merge (or a plain merge when the service has pushed data
    commits in the meantime) run as the service user under the app's lock (`flock` on
    `data/.jobs.lock`). It fails if the tree is dirty or the merge conflicts (the merge is
    aborted); it never rebases, resets or forces.
  - Then `uv sync --locked`; the bot is also restarted when its unit or environment changes.
- Tools at pinned versions with checksums: uv, Claude Code, typst; Python is pinned to a full
  3.12 patch version. The units mount the user's `~/.ssh` and `~/.gitconfig` read-only.
- The bot restarts on failure after 30 s, at most 5 times in 10 minutes, so a crash loop
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
