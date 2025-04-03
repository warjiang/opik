#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <query_file_1.sql> <query_file_2.sql>"
  exit 1
fi

# Configuration
HOST="localhost"
PORT="9000"
USER="opik"
PASS="opik"
DB="opik"
CONCURRENCY=1
ITERATIONS=10

run_benchmark() {
  local file="$1"
  local label="$2"

  echo "▶ Running benchmark for $label..."

  # Capture stderr (clickhouse-benchmark outputs to stderr)
  local output
  output=$(clickhouse-benchmark \
    --host "$HOST" \
    --port "$PORT" \
    --user "$USER" \
    --password "$PASS" \
    --database "$DB" \
    --concurrency "$CONCURRENCY" \
    --iterations "$ITERATIONS" \
    --query="$(cat "$file")" 2>&1)

  echo "$output" > "${label}_benchmark.log"

  # Extract the LAST summary line only
  local summary=$(echo "$output" | grep -E 'queries: .*QPS:' | tail -n1)

  # Extract the values
  local qps=$(echo "$summary" | grep -oE 'QPS: [0-9.]+' | head -n1 | awk '{print $2}')
  local rps=$(echo "$summary" | grep -oE 'RPS: [0-9.]+' | head -n1 | awk '{print $2}')
  local p95=$(echo "$output" | grep -E "^\s*95%" | tail -n1 | awk '{print $2}')

  echo "$label: QPS=$qps, RPS=$rps, p95=${p95}s"
  echo ""

  BENCH_QPS="$qps"
  BENCH_RPS="$rps"
  BENCH_P95="$p95"
}

percent_diff() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (a == "" || b == "" || b == 0) print "N/A";
    else printf "%.2f", (a - b) / b * 100;
  }'
}

# Run benchmarks
run_benchmark "$1" "QueryA"
A_QPS=$BENCH_QPS
A_RPS=$BENCH_RPS
A_P95=$BENCH_P95

run_benchmark "$2" "QueryB"
B_QPS=$BENCH_QPS
B_RPS=$BENCH_RPS
B_P95=$BENCH_P95

# Final comparison
echo "📊 Comparison:"
echo "QPS diff  : $(percent_diff "$A_QPS" "$B_QPS")% (A vs B)"
echo "RPS diff  : $(percent_diff "$A_RPS" "$B_RPS")% (A vs B)"
echo "p95 diff  : $(percent_diff "$B_P95" "$A_P95")% faster (A vs B)"

# Clear decision
echo ""
if [[ $(echo "$A_QPS > $B_QPS" | bc -l) -eq 1 ]]; then
  echo "✅ QueryA is faster based on QPS, RPS, and lower latency."
else
  echo "✅ QueryB is faster based on QPS, RPS, and lower latency."
fi
