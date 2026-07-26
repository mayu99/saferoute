#!/usr/bin/env bash
# Clean full demo run: reset dynamic state, seed the base graph if needed
# (idempotent — no-op if junctions already exist), then run the match
# scenario. Safe to re-run before every rehearsal.
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
