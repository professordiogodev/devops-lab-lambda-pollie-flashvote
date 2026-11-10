#!/usr/bin/env bash
# Sends N votes (default 200) with P in parallel (default 20) to your API, then prints the results.
# Usage: ./loadtest.sh [N] [P]        The poll id is random, so every run starts at zero.
set -u
N=${1:-200}; P=${2:-20}
API=$(aws apigatewayv2 get-apis --query "Items[?Name=='pollie-flashvote']|[0].ApiEndpoint" --output text 2>/dev/null)
case "$API" in https://*) ;; *) echo "No HTTP API named pollie-flashvote found. Deploy it first (Part 4)." >&2; exit 1;; esac
POLL="load-$(date +%s)"
echo "API:  $API"; echo "Poll: $POLL"; echo "Sending $N votes, $P at a time..."
start=$(date +%s)
seq 1 "$N" | xargs -P "$P" -I{} curl -s -o /dev/null -w '%{http_code}\n' -X POST "$API/polls/$POLL/votes" -H 'content-type: application/json' -d '{"option":"python"}' | sort | uniq -c
echo "Took $(( $(date +%s) - start ))s. Results:"
curl -s "$API/polls/$POLL/results"; echo
