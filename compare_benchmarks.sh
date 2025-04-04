#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <query_file_1.sql> <query_file_2.sql>"
  exit 1
fi

# Configuration
HOST="clickhouseliya.dev.comet.com"
PORT="9000"
USER="opik"
PASS="opik"
DB="opik_prod"
CONCURRENCY=2
ITERATIONS=20
QUERY_LOOKBACK_MINUTES=2

run_benchmark() {
  local file="$1"
  local label="$2"

  echo "▶ Running benchmark for $label..."

  # Drop ClickHouse caches before each run (cold cache)
  clickhouse-client -q "SYSTEM DROP MARK CACHE" \
    --host "$HOST" \
    --port "$PORT" \
    --user "$USER" \
    --password "$PASS" \
    --database "$DB"

  clickhouse-client -q "SYSTEM DROP UNCOMPRESSED CACHE"  \
    --host "$HOST" \
    --port "$PORT" \
    --user "$USER" \
    --password "$PASS" \
    --database "$DB"

  # Capture SQL fingerprint for memory lookup
  query_text=$(cat "$file" | sed 's/^[[:space:]]*//' | tr -s ' ')
  query_tag=$(head -n1 "$file" | sed 's/^--//')

  echo "Query fingerprint: $query_tag"

  # Run the benchmark
  local output
  output=$(clickhouse-benchmark \
    --host "$HOST" \
    --port "$PORT" \
    --user "$USER" \
    --password "$PASS" \
    --database "$DB" \
    --concurrency "$CONCURRENCY" \
    --iterations "$ITERATIONS" \
    --delay=0 \
    --enable_filesystem_cache=0 \
    --query="$query_text" 2>&1)

  echo "$output" > "${label}_benchmark.log"

  # Extract summary line
  local summary
  summary=$(echo "$output" | grep -E 'queries: .*QPS:' | tail -n1)

  # Extract metrics
  local qps rps p90
  qps=$(echo "$summary" | grep -oE 'QPS: [0-9.]+' | head -n1 | awk '{print $2}')
  rps=$(echo "$summary" | grep -oE 'RPS: [0-9.]+' | head -n1 | awk '{print $2}')
  p90=$(echo "$output" | grep -E "^\s*90%" | tail -n1 | awk '{print $2}')

  # Wait 1 second for ClickHouse to flush query_log
  sleep 1

  # Query average and peak memory usage for the query

  local mem_avg mem_peak
  read -r mem_avg mem_peak <<< $(clickhouse-client \
    --host "$HOST" \
    --port "$PORT" \
    --user "$USER" \
    --password "$PASS" \
    --database "$DB" \
    --query "
      SELECT
        round(avg(memory_usage) / 1048576, 1),
        round(max(memory_usage) / 1048576, 1)
      FROM system.query_log
      WHERE type = 'QueryFinish'
        AND event_time > now() - INTERVAL $QUERY_LOOKBACK_MINUTES minute
        AND positionCaseInsensitive(query, '$query_tag') > 0
      LIMIT 1;
    "
  )

  echo "$label: QPS=$qps, RPS=$rps, p90=${p90}s, Mem(avg)=${mem_avg} MiB, Mem(peak)=${mem_peak} MiB"
  echo ""

  BENCH_QPS="$qps"
  BENCH_RPS="$rps"
  BENCH_P90="$p90"
  BENCH_MEM_AVG="$mem_avg"
  BENCH_MEM_PEAK="$mem_peak"
}

percent_diff() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (a == "" || b == "" || b == 0) print "N/A";
    else printf "%.2f", (a - b) / b * 100;
  }'
}

# Run benchmarks
if (( RANDOM % 2 )); then
  run_benchmark "$1" "QueryA"
  A_QPS=$BENCH_QPS
  A_RPS=$BENCH_RPS
  A_P90=$BENCH_P90
  A_MEM_AVG=$BENCH_MEM_AVG
  A_MEM_PEAK=$BENCH_MEM_PEAK

  run_benchmark "$2" "QueryB"
  B_QPS=$BENCH_QPS
  B_RPS=$BENCH_RPS
  B_P90=$BENCH_P90
  B_MEM_AVG=$BENCH_MEM_AVG
  B_MEM_PEAK=$BENCH_MEM_PEAK
else
  run_benchmark "$2" "QueryB"
  B_QPS=$BENCH_QPS
  B_RPS=$BENCH_RPS
  B_P90=$BENCH_P90
  B_MEM_AVG=$BENCH_MEM_AVG
  B_MEM_PEAK=$BENCH_MEM_PEAK

  run_benchmark "$1" "QueryA"
  A_QPS=$BENCH_QPS
  A_RPS=$BENCH_RPS
  A_P90=$BENCH_P90
  A_MEM_AVG=$BENCH_MEM_AVG
  A_MEM_PEAK=$BENCH_MEM_PEAK
fi


# Final comparison
echo "📊 Comparison:"
echo "QPS diff    : $(percent_diff "$A_QPS" "$B_QPS")% (A vs B)"
echo "RPS diff    : $(percent_diff "$A_RPS" "$B_RPS")% (A vs B)"
echo "p95 diff    : $(percent_diff "$B_P90" "$A_P90")% faster (A vs B)"
echo "Mem(avg)    : $(percent_diff "$B_MEM_AVG" "$A_MEM_AVG")% more memory used (B vs A)"
echo "Mem(peak)   : $(percent_diff "$B_MEM_PEAK" "$A_MEM_PEAK")% more memory used (B vs A)"


echo ""

# Performance winner
if [[ $(echo "$A_QPS > $B_QPS" | bc -l) -eq 1 ]]; then
  echo "✅ QueryA is faster based on QPS, RPS, and latency."
else
  echo "✅ QueryB is faster based on QPS, RPS, and latency."
fi

# Memory efficiency
if [[ $(echo "$A_MEM_AVG < $B_MEM_AVG" | bc -l) -eq 1 ]]; then
  echo "✅ QueryA used less average memory."
else
  echo "✅ QueryB used less average memory."
fi
