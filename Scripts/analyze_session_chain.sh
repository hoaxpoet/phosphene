#!/usr/bin/env bash
# analyze_session_chain.sh — Post-session audio-chain health grader (ASH.2).
#
# Runs ChainAnalyzer out-of-process against any session directory (including
# pre-ASH historical dirs) — the SAME analyzer VisualizerEngine runs in-process
# at session end. Writes chain_health.json + a `CHAIN_HEALTH:` line into the dir
# and prints the verdict. Exit 0 iff verdict=clean (so reel/CI scripts can gate).
#
#   Scripts/analyze_session_chain.sh ~/Documents/phosphene_sessions/<timestamp>
#
# Run from repo root.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: Scripts/analyze_session_chain.sh <session-dir>" >&2
  exit 2
fi

exec swift run --package-path PhospheneEngine ChainHealthAnalyzer "$1"
