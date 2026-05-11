#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
USER_ID="${USER_ID:-1500}"
TARGET="${TARGET:-report}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"
DURATION="${DURATION:-30s}"

if [ "$TARGET" = "report" ]; then
  CACHED_URL="$BASE_URL/users/$USER_ID/report"
  NO_CACHE_URL="$BASE_URL/users/$USER_ID/report/no-cache"
else
  CACHED_URL="$BASE_URL/users/$USER_ID"
  NO_CACHE_URL="$BASE_URL/users/$USER_ID/no-cache"
fi

if [ -t 1 ]; then
  BOLD="$(tput bold)"
  DIM="$(tput dim)"
  GREEN="$(tput setaf 2)"
  CYAN="$(tput setaf 6)"
  YELLOW="$(tput setaf 3)"
  RED="$(tput setaf 1)"
  RESET="$(tput sgr0)"
else
  BOLD=""
  DIM=""
  GREEN=""
  CYAN=""
  YELLOW=""
  RED=""
  RESET=""
fi

line() {
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'
}

title() {
  echo
  line
  echo "${BOLD}$1${RESET}"
  line
}

field() {
  printf "  ${DIM}%-14s${RESET} %s\n" "$1" "$2"
}

extract_rps() {
  awk '/Requests\/sec:/ { print $2 }'
}

extract_latency() {
  awk '/Latency/ { print $2 $3; exit }'
}

compare_rps() {
  awk -v without="$1" -v cached="$2" 'BEGIN {
    if (without == 0) {
      print "n/a"
      exit
    }

    diff = ((cached - without) / without) * 100
    sign = diff >= 0 ? "+" : ""
    printf "%s%.2f%%", sign, diff
  }'
}

run_wrk() {
  local label="$1"
  local url="$2"
  local output

  title "$label"
  echo "${CYAN}Comando:${RESET} wrk -t$THREADS -c$CONNECTIONS -d$DURATION $url"
  echo

  output="$(wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$url")"
  echo "$output"
  echo

  field "Latency avg" "$(echo "$output" | extract_latency)"
  field "Requests/sec" "$(echo "$output" | extract_rps)"

  WRK_LAST_OUTPUT="$output"
}

if ! command -v wrk >/dev/null 2>&1; then
  echo "${RED}wrk nao encontrado.${RESET}"
  echo "macOS: brew install wrk"
  echo "Linux: use o gerenciador da sua distro ou compile https://github.com/wg/wrk"
  exit 1
fi

title "Benchmark: Postgres vs Redis"
field "Base URL" "$BASE_URL"
field "User ID" "$USER_ID"
field "Target" "$TARGET"
field "Threads" "$THREADS"
field "Connections" "$CONNECTIONS"
field "Duration" "$DURATION"
field "Com cache" "$CACHED_URL"
field "Sem cache" "$NO_CACHE_URL"

title "Validando endpoints"
curl -fsS "$NO_CACHE_URL" >/dev/null
curl -fsS "$CACHED_URL" >/dev/null
echo "${GREEN}OK${RESET} Os dois endpoints responderam."

run_wrk "Teste 1: sem cache, sempre Postgres" "$NO_CACHE_URL"
WITHOUT_CACHE_OUTPUT="$WRK_LAST_OUTPUT"
WITHOUT_CACHE_RPS="$(echo "$WITHOUT_CACHE_OUTPUT" | extract_rps)"
WITHOUT_CACHE_LATENCY="$(echo "$WITHOUT_CACHE_OUTPUT" | extract_latency)"

title "Aquecendo cache Redis"
curl -fsS "$CACHED_URL" >/dev/null
echo "${GREEN}OK${RESET} A primeira chamada gravou ou confirmou o item no cache."

run_wrk "Teste 2: com cache Redis aquecido" "$CACHED_URL"
CACHED_OUTPUT="$WRK_LAST_OUTPUT"
CACHED_RPS="$(echo "$CACHED_OUTPUT" | extract_rps)"
CACHED_LATENCY="$(echo "$CACHED_OUTPUT" | extract_latency)"

RPS_DIFF="$(compare_rps "$WITHOUT_CACHE_RPS" "$CACHED_RPS")"

title "Resumo"
printf "  %-18s %-16s %-16s\n" "Cenario" "Latency avg" "Requests/sec"
printf "  %-18s %-16s %-16s\n" "Sem cache" "$WITHOUT_CACHE_LATENCY" "$WITHOUT_CACHE_RPS"
printf "  %-18s %-16s %-16s\n" "Com cache" "$CACHED_LATENCY" "$CACHED_RPS"
echo

if [[ "$RPS_DIFF" == +* ]]; then
  echo "${GREEN}Resultado:${RESET} Redis entregou $RPS_DIFF requests/sec em relacao ao Postgres."
else
  echo "${YELLOW}Resultado:${RESET} Redis entregou $RPS_DIFF requests/sec em relacao ao Postgres."
fi
echo

echo "${DIM}Leitura rapida:${RESET}"
echo "  - Requests/sec maior geralmente indica mais vazao."
echo "  - Latency avg menor geralmente indica resposta mais rapida."
echo "  - Cache local nem sempre ganha em consultas simples."
echo "  - Use TARGET=report para testar uma consulta com join, subselect e string_agg."
echo

echo "${DIM}Dica:${RESET} altere parametros assim:"
echo "TARGET=report USER_ID=10 DURATION=10s CONNECTIONS=50 npm run benchmark:cache"
