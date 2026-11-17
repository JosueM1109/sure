# Josue's Sure

This checkout is the budgeting app at https://budget.mendhome.net: upstream Sure plus a few small patches, built by GitHub Actions and run on menddell. It is reachable from the tailnet and LAN only.

## Branches and remotes
- `upstream` is github.com/we-promise/sure. Its push URL is set to `DISABLED`, so never push there.
- `origin` is github.com/JosueM1109/sure, the public fork.
- `josue` is an upstream release tag (`v2026.11.17-alpha` style) plus the fork's commits. It only ever moves to release tags, never to upstream `main`.
- `Local/` holds only files upstream doesn't have, so it never conflicts on a rebase.

## The fork's commits
| What | Files |
|---|---|
| Plaid guardrails | `app/models/plaid_guardrails.rb`, `config/initializers/plaid_guardrails.rb`, `test/models/plaid_guardrails_test.rb` |
| Import an existing Plaid Item by access token | `app/models/plaid_item/token_import.rb`, `lib/tasks/plaid_import.rake`, `test/models/plaid_item/token_import_test.rb` |
| Image build | `.github/workflows/josue-image.yml` |
| Deploy, update, backup | `Local/` |

Every change is a new file, so a rebase onto a new release almost never conflicts.

## Plaid guardrails
The Plaid account is on the Trial plan: 10 Items, and removing one does not give its slot back. The same Items feed the plaid-personal MCP and the n8n bookkeeping, so Sure only reads them.
- Sure never calls `/item/remove`. Deleting a connection in the app deletes it in Sure only and logs `[PlaidGuardrails] Skipped Plaid /item/remove`.
- Every Plaid request passes through `Plaid::ApiClient#call_api`, which only lets read endpoints through. Anything else (`/item/webhook/update`, `/item/remove`, ...) raises `PlaidGuardrails::Blocked` before it is sent.
- Plaid Link is off: `/link/token/create` and `/item/public_token/exchange` need `PLAID_ALLOW_LINK=true`. "Connect via Plaid" and "update connection" show an error instead.
- `/transactions/refresh` (billed per call) needs `PLAID_ALLOW_TRANSACTIONS_REFRESH=true`. Syncs still get what Plaid pulls from the bank on its own schedule.
- Plaid's sandbox is exempt (fake Items, used by upstream's tests).

`/transactions/sync` cursors belong to the caller, so Sure syncing these Items doesn't move the n8n workflow's cursors.

## Adding a Plaid Item
Items come in by access token, never through Link:
```sh
ssh menddell
cd ~/sure
docker compose exec -T web bin/rails "plaid:import_item[josuemendives05@gmail.com]" < token.txt
```
The token is read from stdin (or `PLAID_ACCESS_TOKEN`). The task calls `/item/get` and `/institutions/get_by_id`, creates the Item, sets a 2 hour sync schedule and starts the first sync. Running it again for the same Item changes nothing.

## Sync schedule
Plaid webhooks can't reach a tailnet-only host, so each imported Item gets a Sure sync schedule (`SyncSchedule`, every 120 minutes, at even UTC hours). Sure's daily sync of everything also runs (02:22 by default, Settings > Self-Hosting). To change one Item's interval: the account's connection menu in the app, or `SyncSchedule.assign(PlaidItem.find(id), 240)` in `bin/rails console`.

## Updating
```sh
Local/update.sh                     # newest upstream release tag
Local/update.sh v2026.11.20-alpha   # a specific tag
Local/update.sh --deploy            # redeploy the current josue build
```
It fetches upstream tags, rebases `josue` onto the release, disables any upstream workflow GitHub has started listing, force-pushes `josue` (with lease), and waits for the "Josue image" workflow: the Plaid tests, then the image build. Then on menddell it copies `Local/menddell-compose.yml` and `Local/backup.sh` over, takes a backup, pulls `ghcr.io/josuem1109/sure:<tag>-josue`, pins `SURE_IMAGE_TAG` in `.env`, restarts web and worker (web runs the migrations when it starts) and waits for `/up`. On a rebase conflict, a failed run or a failed health check it stops and says what to do.

Images are never built on menddell (its Docker build cache once filled the disk).

## GitHub Actions
Only `.github/workflows/josue-image.yml` runs in the fork. Upstream's workflows would publish images, Helm charts and apps, so they are disabled with `gh workflow disable` as GitHub lists them (`update.sh` repeats this). A push to `wip/**` runs only the tests.

## menddell
- `~/sure/`: `compose.yml` (a copy of `Local/menddell-compose.yml`), `.env` (chmod 600, see `Local/.env.example`), `backup.sh`, `backups/`.
- Containers: web (:4440), worker (Sidekiq), db (Postgres 16), redis, each with a `mem_limit`.
- `SECRET_KEY_BASE` and the three `ACTIVE_RECORD_ENCRYPTION_*` keys must never change: the Plaid tokens in the database are encrypted with them. Every backup holds a copy of `.env`.

## Backups and restore
`backup.sh` runs from cron at 09:05 UTC: Sure's own `sure-backup` (pg_dump, uploaded files, `.env`, `compose.yml`, `restore.sh`) into `~/sure/backups/<version>/<date>-scheduled/`, 14 days kept, mirrored with rsync to macux `~/backups/sure-menddell/`.
```sh
cd ~/sure
docker compose stop web worker
docker compose run --rm backup restore latest     # or <version>/<date>-scheduled
docker compose up -d
```
On a new machine: copy a backup folder over and run `sh <backup>/restore.sh`.

## Rollback
Set `SURE_IMAGE_TAG` in `~/sure/.env` back to the previous `<tag>-josue`. If the newer version ran migrations, restore the backup `update.sh` took just before it, then `docker compose up -d`.
