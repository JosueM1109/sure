#!/usr/bin/env bash
# Nightly Sure backup on menddell (cron, see Local/README.md). Uses Sure's own
# backup tool: a pg_dump of the database, the uploaded files, .env and
# compose.yml, and a restore.sh, in ~/sure/backups/<version>/<date>-scheduled/.
# Scheduled backups older than 14 days are pruned, then the folder is mirrored
# to macux (BACKUP_RSYNC_TARGET in .env). Backups hold .env, so they stay
# readable by josue only, here and on macux.
set -euo pipefail
cd /home/josue/sure
umask 077
mkdir -p backups
docker compose --profile backup run --rm -T backup scheduled
chmod -R go-rwx backups
TARGET=$(grep -E '^BACKUP_RSYNC_TARGET=' .env | cut -d= -f2- | sed 's/[[:space:]]*#.*//' || true)
if [ -n "$TARGET" ]; then
  rsync -a --delete --chmod=Dgo-rwx,Fgo-rwx backups/ "$TARGET"
fi
latest=$(find backups -mindepth 2 -maxdepth 2 -type d -name '*-scheduled' | sort | tail -n 1)
echo "$(date -Is) backup ok: ${latest:-none}${TARGET:+ (mirrored)}"
