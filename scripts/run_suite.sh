#!/usr/bin/env bash
# run_suite.sh — regressione completa dei test runtime di ArcadeMaze (Godot).
# Esegue ogni tests/test_*.tscn in headless, registra exit code e summary.
# Uso: bash scripts/run_suite.sh [filtro_sottostringa]
set -u
GODOT="${GODOT_BIN:-/tmp/my-project/tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
FILTER="${1:-}"
LOG="/tmp/suite_$(date +%s).log"
cd "$(dirname "$0")/.."

mapfile -t TESTS < <(ls godot/tests/test_*.tscn | sort)
if [ -n "$FILTER" ]; then
        mapfile -t TESTS < <(printf '%s\n' "${TESTS[@]}" | grep "$FILTER")
fi

total=0; passed=0; failed=0; flaky=""
echo "=== SUITE ArcadeMaze: ${#TESTS[@]} test ===" | tee "$LOG"
for t in "${TESTS[@]}"; do
        name="${t#godot/tests/}"
        total=$((total + 1))
        out=$(timeout 150 "$GODOT" --headless --path godot "res://tests/$name" 2>&1)
        rc=$?
        verdict=$(echo "$out" | grep -E "TUTTI PASSATI|TUTTI I CHECK SUPERATI" | head -1)
        if [ $rc -eq 0 ] && [ -n "$verdict" ]; then
                passed=$((passed + 1))
                printf "PASS  %s\n" "$name" | tee -a "$LOG"
        else
                failed=$((failed + 1))
                printf "FAIL  %s (rc=%d)\n" "$name" "$rc" | tee -a "$LOG"
                echo "$out" | grep -E "\[TEST\] (FALLITO|ESITO)|ERROR|SCRIPT ERROR" | head -8 | tee -a "$LOG"
        fi
done
echo "=== RISULTATO: $passed/$total PASS, $failed FAIL ===" | tee -a "$LOG"
echo "log completo: $LOG"
[ $failed -eq 0 ]
