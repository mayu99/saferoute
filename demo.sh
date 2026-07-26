#!/usr/bin/env bash
# Clean full demo run: reset dynamic state, seed the base graph if needed
# (idempotent — no-op if junctions already exist), then run the match
# scenario. Safe to re-run before every rehearsal.
#
# --hazard: also close Bay St and reroute the households affected by it,
# proving the graph adapts to a blocked road after the initial assignment.
set -euo pipefail
cd "$(dirname "$0")"
source ~/jacenv/bin/activate

echo "== Reset =="
jac run reset.jac

echo
echo "== Seed (idempotent) =="
jac run seed.jac

echo
echo "== Demo: match households to shelters =="
jac run match.jac

if [[ "${1:-}" == "--hazard" ]]; then
    echo
    echo "== Hazard: close a road and reroute affected households =="
    jac run hazard.jac
fi
