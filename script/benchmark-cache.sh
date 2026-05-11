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

# ─── cores ──────────────────────────────────────────────────────

if [ -t 1 ]; then
  BOLD="$(tput bold)"
  DIM="$(tput dim)"
  GREEN="$(tput setaf 2)"
  CYAN="$(tput setaf 6)"
  YELLOW="$(tput setaf 3)"
  RED="$(tput setaf 1)"
  BLUE="$(tput setaf 4)"
  MAGENTA="$(tput setaf 5)"
  RESET="$(tput sgr0)"
else
  BOLD=""
  DIM=""
  GREEN=""
  CYAN=""
  YELLOW=""
  RED=""
  BLUE=""
  MAGENTA=""
  RESET=""
fi

# ─── helpers visuais ─────────────────────────────────────────────

line() {
  printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '─'
}

small_line() {
  printf '%*s\n' 60 '' | tr ' ' '─'
}

header() {
  echo
  echo "${CYAN}${BOLD}╔$(printf '═%.0s' $(seq 1 66))╗${RESET}"
  printf "${CYAN}${BOLD}║ %-64s ║${RESET}\n" "$1"
  echo "${CYAN}${BOLD}╚$(printf '═%.0s' $(seq 1 66))╝${RESET}"
}

section() {
  echo
  echo "${BOLD}$1${RESET}"
  echo "${DIM}$(small_line)${RESET}"
}

field() {
  printf "  ${DIM}%-18s${RESET} %s\n" "$1" "$2"
}

bar() {
  local value="$1"
  local max="$2"
  local width="${3:-30}"
  local color="${4:-$GREEN}"

  awk -v value="$value" -v max="$max" -v width="$width" \
      -v color="$color" -v reset="$RESET" '
    BEGIN {
      if (max <= 0) max = 1

      filled = int((value / max) * width)
      if (filled < 0) filled = 0
      if (filled > width) filled = width

      empty = width - filled

      printf "%s", color
      for (i = 0; i < filled; i++) printf "█"
      printf "%s", reset

      for (i = 0; i < empty; i++) printf "░"
    }
  '
}

# ─── extração de dados do wrk ────────────────────────────────────

extract_rps() {
  awk '/Requests\/sec:/ { print $2 }'
}

extract_latency_raw() {
  awk '/Latency/ { print $2; exit }'
}

extract_latency_unit() {
  awk '/Latency/ {
    value = $2

    if (value ~ /us$/) {
      gsub("us", "", value)
      print value / 1000
      exit
    }

    if (value ~ /ms$/) {
      gsub("ms", "", value)
      print value
      exit
    }

    if (value ~ /s$/) {
      gsub("s", "", value)
      print value * 1000
      exit
    }

    print value
    exit
  }'
}

compare_percent() {
  awk -v base="$1" -v current="$2" 'BEGIN {
    if (base == 0) {
      print "n/a"
      exit
    }

    diff = ((current - base) / base) * 100
    sign = diff >= 0 ? "+" : ""
    printf "%s%.2f%%", sign, diff
  }'
}

compare_latency_percent() {
  awk -v base="$1" -v current="$2" 'BEGIN {
    if (base == 0) {
      print "n/a"
      exit
    }

    diff = ((base - current) / base) * 100
    sign = diff >= 0 ? "+" : ""
    printf "%s%.2f%%", sign, diff
  }'
}

speedup() {
  awk -v base="$1" -v current="$2" 'BEGIN {
    if (current == 0) {
      print "n/a"
      exit
    }

    printf "%.2fx", base / current
  }'
}

# ─── execução do benchmark ───────────────────────────────────────

run_wrk() {
  local label="$1"
  local url="$2"
  local color="$3"
  local output

  section "▶️ $label"

  echo "${DIM}Comando:${RESET} wrk -t$THREADS -c$CONNECTIONS -d$DURATION $url"
  echo

  output="$(wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$url")"

  echo "$output"
  echo

  local latency_raw
  local latency_ms
  local rps

  latency_raw="$(echo "$output" | extract_latency_raw)"
  latency_ms="$(echo "$output" | extract_latency_unit)"
  rps="$(echo "$output" | extract_rps)"

  echo "${BOLD}Resumo do cenário${RESET}"
  field "Latency avg" "$latency_raw"
  field "Latency ms" "${latency_ms} ms"
  field "Requests/sec" "$rps"

  WRK_LAST_OUTPUT="$output"
  WRK_LAST_RPS="$rps"
  WRK_LAST_LATENCY_RAW="$latency_raw"
  WRK_LAST_LATENCY_MS="$latency_ms"
}

print_config() {
  header "BENCHMARK: Cache Redis vs Postgres"

  echo "${DIM}Configuração usada no teste:${RESET}"
  echo

  field "Base URL" "$BASE_URL"
  field "User ID" "$USER_ID"
  field "Target" "$TARGET"
  field "Threads" "$THREADS"
  field "Connections" "$CONNECTIONS"
  field "Duration" "$DURATION"

  echo
  field "Sem cache" "$NO_CACHE_URL"
  field "Com cache" "$CACHED_URL"

  echo
  echo "${DIM}Leitura rápida:${RESET}"
  echo "  - Sem cache: força consulta no Postgres."
  echo "  - Com cache: usa Redis quando o dado já foi armazenado."
  echo "  - Requests/sec maior indica mais vazão."
  echo "  - Latency menor indica resposta mais rápida."
}

print_comparison() {
  local without_rps="$1"
  local cached_rps="$2"
  local without_latency="$3"
  local cached_latency="$4"
  local without_latency_raw="$5"
  local cached_latency_raw="$6"

  local max_rps
  local max_latency
  local rps_diff
  local latency_gain
  local latency_speedup

  max_rps="$(awk -v a="$without_rps" -v b="$cached_rps" 'BEGIN { print (a > b ? a : b) }')"
  max_latency="$(awk -v a="$without_latency" -v b="$cached_latency" 'BEGIN { print (a > b ? a : b) }')"

  rps_diff="$(compare_percent "$without_rps" "$cached_rps")"
  latency_gain="$(compare_latency_percent "$without_latency" "$cached_latency")"
  latency_speedup="$(speedup "$without_latency" "$cached_latency")"

  header "COMPARAÇÃO FINAL"

  printf "  ${BOLD}%-18s %-18s %-18s${RESET}\n" "Cenário" "Latency avg" "Requests/sec"
  printf "  %-18s ${YELLOW}%-18s${RESET} ${YELLOW}%-18s${RESET}\n" \
    "Sem cache" "$without_latency_raw" "$without_rps"

  printf "  %-18s ${GREEN}%-18s${RESET} ${GREEN}%-18s${RESET}\n" \
    "Com cache" "$cached_latency_raw" "$cached_rps"

  echo
  echo "${BOLD}Vazão por segundo:${RESET}"
  printf "  SEM cache  "
  bar "$without_rps" "$max_rps" 40 "$YELLOW"
  printf " ${YELLOW}%s req/s${RESET}\n" "$without_rps"

  printf "  COM cache  "
  bar "$cached_rps" "$max_rps" 40 "$GREEN"
  printf " ${GREEN}%s req/s${RESET}\n" "$cached_rps"

  echo
  echo "${BOLD}Latência média:${RESET}"
  printf "  SEM cache  "
  bar "$without_latency" "$max_latency" 40 "$YELLOW"
  printf " ${YELLOW}%s${RESET}\n" "$without_latency_raw"

  printf "  COM cache  "
  bar "$cached_latency" "$max_latency" 40 "$GREEN"
  printf " ${GREEN}%s${RESET}\n" "$cached_latency_raw"

  echo
  echo "${BOLD}Resultado:${RESET}"

  if [[ "$rps_diff" == +* ]]; then
    echo "  ${GREEN}Requests/sec:${RESET} Redis entregou ${BOLD}$rps_diff${RESET} em relação ao Postgres."
  else
    echo "  ${YELLOW}Requests/sec:${RESET} Redis entregou ${BOLD}$rps_diff${RESET} em relação ao Postgres."
  fi

  if [[ "$latency_gain" == +* ]]; then
    echo "  ${GREEN}Latency:${RESET} Redis reduziu a latência em ${BOLD}$latency_gain${RESET}."
    echo "  ${CYAN}Speedup:${RESET} Redis foi aproximadamente ${BOLD}$latency_speedup${RESET} mais rápido na latência média."
  else
    echo "  ${YELLOW}Latency:${RESET} Redis não reduziu a latência nesse cenário."
  fi

  echo
  echo "${DIM}Conclusão:${RESET}"
  echo "  - Redis tende a ganhar quando a consulta no Postgres é pesada ou repetida."
  echo "  - Em consultas muito simples, o ganho pode ser pequeno ou até inexistente."
  echo "  - Para validar melhor, rode mais de uma vez e varie CONNECTIONS, DURATION e TARGET."
}

# ─── validações ──────────────────────────────────────────────────

if ! command -v wrk >/dev/null 2>&1; then
  echo "${RED}wrk não encontrado.${RESET}"
  echo
  echo "macOS:"
  echo "  brew install wrk"
  echo
  echo "Linux:"
  echo "  use o gerenciador da sua distro ou compile:"
  echo "  https://github.com/wg/wrk"
  exit 1
fi

# ─── main ────────────────────────────────────────────────────────

print_config

section "Validando endpoints"

echo "${DIM}Testando endpoint sem cache...${RESET}"
curl -fsS "$NO_CACHE_URL" >/dev/null

echo "${DIM}Testando endpoint com cache...${RESET}"
curl -fsS "$CACHED_URL" >/dev/null

echo "${GREEN}OK${RESET} Os dois endpoints responderam."

run_wrk "CENÁRIO 1 — sem cache, sempre Postgres" "$NO_CACHE_URL" "$YELLOW"

WITHOUT_CACHE_OUTPUT="$WRK_LAST_OUTPUT"
WITHOUT_CACHE_RPS="$WRK_LAST_RPS"
WITHOUT_CACHE_LATENCY_RAW="$WRK_LAST_LATENCY_RAW"
WITHOUT_CACHE_LATENCY_MS="$WRK_LAST_LATENCY_MS"

section "Aquecendo cache Redis"

curl -fsS "$CACHED_URL" >/dev/null
echo "${GREEN}OK${RESET} A primeira chamada gravou ou confirmou o item no cache."

run_wrk "CENÁRIO 2 — com cache Redis aquecido" "$CACHED_URL" "$GREEN"

CACHED_OUTPUT="$WRK_LAST_OUTPUT"
CACHED_RPS="$WRK_LAST_RPS"
CACHED_LATENCY_RAW="$WRK_LAST_LATENCY_RAW"
CACHED_LATENCY_MS="$WRK_LAST_LATENCY_MS"

print_comparison \
  "$WITHOUT_CACHE_RPS" \
  "$CACHED_RPS" \
  "$WITHOUT_CACHE_LATENCY_MS" \
  "$CACHED_LATENCY_MS" \
  "$WITHOUT_CACHE_LATENCY_RAW" \
  "$CACHED_LATENCY_RAW"

echo
echo "${DIM}Dica:${RESET}"
echo "  TARGET=report USER_ID=10 DURATION=10s CONNECTIONS=50 npm run benchmark:cache"
echo
