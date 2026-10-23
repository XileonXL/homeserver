# bidsenseai_extractor

Temporary: not part of the house and to be removed; see
[docs/decisions.md](../../../docs/decisions.md#a-temporary-bidsense-ai-extractor-outside-the-house).

Runs `doc-extractor run --pending` from the private BidSense AI repository every night at
02:30 Europe/Madrid, as the `extractor` user, with a Claude Code subscription token and AWS
credentials from IAM Roles Anywhere (`aws_signing_helper` as `credential_process`).

- Repository: checked out over SSH with a read-only deploy key, tracking `main`
  (`bidsenseai_extractor_repo_ref`). Re-run the play to deploy the latest pushed `main`.
- Tools at pinned versions with checksums: uv, Claude Code, `aws_signing_helper`.
- Configuration in `/etc/bidsenseai-extractor/` (`env`, `alerts.env`, certificate and key).
- A failed run sends a Telegram message through `OnFailure`. `TELEGRAM_BOT_TOKEN` and
  `TELEGRAM_CHAT_ID` must both be in `.env`; run the `alerts` role first, which writes the chat id there.
- Variables and defaults: `defaults/main.yml`. Secrets and ARNs come from `.env`; see
  `.env.example`.

Run: `ansible-playbook site.yml --limit bidsenseai_extractor`.

## Yearly renewal

The Claude Code token (`claude setup-token`) and the end-entity certificate both last one
year. Create the new certificate with the openssl steps in the BidSense AI `infra/README.md`,
section "Homeserver extractor (IAM Roles Anywhere)", update `CLAUDE_CODE_OAUTH_TOKEN` and the
files referenced by `EXTRACTOR_CERT_FILE` and `EXTRACTOR_KEY_FILE` in `.env`, and re-run the play.
