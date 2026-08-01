#!/usr/bin/env bash
# Holdout rehearsal — run the unseen-incident path before the unseen incident.
#
# The sealed dataset lands in the final hours. The worst possible time to
# discover that the loader wants a column we don't have, or that the baseline
# ladder has no rung for a short slice, is then. So we manufacture an "unseen"
# file now and put it through the *real* command path, end to end:
#
#     export a slice -> DATA_DIR=... load.sh -> engine.run -> bundle
#
# When the real file arrives, the pipeline is executing for the second time.
#
# Usage: scripts/holdout-rehearsal.sh [days] [end]
#   days  length of the synthetic slice        (default 14)
#   end   last instant to include, YYYY-MM-DD  (default: end of the data)
#
# The end option matters: rehearsing only the tail of the dataset tests the
# plumbing but not the detection, because the tail holds no planted anomalies.
# Pointing it at a window that DOES contain one is what tests the baseline
# ladder's weaker rungs.
set -euo pipefail

DAYS="${1:-14}"
END="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${CH_ENV:-$HOME/.config/clickhouse/clickathon.env}"
CH="${CH_CLIENT:-$HOME/Documents/projects/click/bin/clickhouse}"
SRC_DB="${SRC_DB:-pw}"
HOLDOUT_DB="${HOLDOUT_DB:-pw_holdout}"
STAGE="${STAGE:-/tmp/holdout-$DAYS d}"
STAGE="${STAGE// /}"

# shellcheck disable=SC1090
source "$ENV_FILE"
ch() { "$CH" client --host "$CH_HOST" --port 9440 --secure \
        --user "$CH_USER" --password "$CH_PASSWORD" "$@"; }

echo "==> exporting the last $DAYS days of $SRC_DB as an 'unseen' package"
mkdir -p "$STAGE"

# Cutoff is derived from the data, never hardcoded — the same discipline the
# engine follows, and the thing most likely to break on a real unseen file.
if [[ -n "$END" ]]; then
  HI="$END 23:59:59"
else
  HI=$(ch --query "SELECT toString(max(event_time)) FROM $SRC_DB.ad_events_raw")
fi
CUT=$(ch --query "SELECT toString(subtractDays(toDateTime('$HI'), $DAYS))")
echo "    window: $CUT  ->  $HI"

ch --query "SELECT * FROM $SRC_DB.ad_events_raw WHERE event_time >= '$CUT' AND event_time <= '$HI' ORDER BY event_time FORMAT Parquet" \
   > "$STAGE/ad_events.parquet"
for t in apps advertisers geo_device; do
  ch --query "SELECT * FROM $SRC_DB.$t FORMAT CSVWithNames" > "$STAGE/$t.csv"
done
ls -la "$STAGE" | tail -4

echo
echo "==> loading it exactly as the unseen file would be loaded"
DATA_DIR="$STAGE" CH_DB="$HOLDOUT_DB" "$ROOT/load/load.sh" | tail -18

echo
echo "==> running the full pipeline against it"
CH_DB="$HOLDOUT_DB" python3 -m engine.run --out "$ROOT/out/holdout"

echo
echo "==> rehearsal bundle"
ls -la "$ROOT/out/holdout"
