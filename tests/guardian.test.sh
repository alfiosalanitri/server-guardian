#!/bin/bash
# Tests for the guardian script.
# Each test runs in an isolated tmp dir with stubbed system commands
# (curl, lscpu, uptime, free, df, systemctl, sudo) injected via PATH.

GUARDIAN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/guardian"
PASS=0
FAIL=0

# ── output ───────────────────────────────────────────────────────────────────
_green() { printf '\033[32m%s\033[0m\n' "$*"; }
_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
pass()   { PASS=$((PASS + 1)); _green "  PASS $1"; }
fail()   { FAIL=$((FAIL + 1)); _red   "  FAIL $1"; [ -n "${2-}" ] && _red "       → $2"; }

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then pass "$label"; else fail "$label" "exit $actual (expected $expected)"; fi
}
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then pass "$label"; else fail "$label" "missing: $needle"; fi
}
assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then pass "$label"; else fail "$label" "should not contain: $needle"; fi
}

# ── sandbox ──────────────────────────────────────────────────────────────────
_TESTDIR=""

setup() {
  _TESTDIR=$(mktemp -d)
  mkdir -p "$_TESTDIR/stubs"

  # alert file starts "yes" so send_message always fires on first check
  echo "yes" > "$_TESTDIR/send-alert.txt"

  # curl: outputs configured HTTP code when called with -w; silent otherwise.
  # Default: 200. Override: write a code to $_TESTDIR/curl_code.
  cat > "$_TESTDIR/stubs/curl" <<'STUB'
#!/bin/bash
code=$(cat "$(dirname "$0")/../curl_code" 2>/dev/null || echo "200")
if printf '%s\n' "$@" | grep -qx '\-w'; then echo "$code"; fi
STUB
  echo "200" > "$_TESTDIR/curl_code"

  # lscpu: 4 CPUs. Override: write "$_TESTDIR/stubs/lscpu" before calling setup.
  printf '#!/bin/bash\necho "CPU(s):                  4"\n' > "$_TESTDIR/stubs/lscpu"

  # uptime: low load. Override: write load string to $_TESTDIR/load.
  cat > "$_TESTDIR/stubs/uptime" <<'STUB'
#!/bin/bash
load=$(cat "$(dirname "$0")/../load" 2>/dev/null || echo "0.10, 0.20, 0.15")
echo " 12:00:00 up 1 day,  1 user,  load average: $load"
STUB

  # free: 30% RAM. Override: write integer pct to $_TESTDIR/ram_pct.
  cat > "$_TESTDIR/stubs/free" <<'STUB'
#!/bin/bash
pct=$(cat "$(dirname "$0")/../ram_pct" 2>/dev/null || echo "30")
total=8000000; used=$((total * pct / 100))
printf '%s\n%s\n' \
  "               total        used        free" \
  "Mem:     $total  $used  $((total - used))"
STUB

  # systemctl: no failures. Create $_TESTDIR/svc_failed to simulate a failure.
  cat > "$_TESTDIR/stubs/systemctl" <<'STUB'
#!/bin/bash
if [ -f "$(dirname "$0")/../svc_failed" ]; then
  printf '  UNIT                LOAD   ACTIVE SUB    DESCRIPTION\n'
  printf '● broken.service     loaded failed failed  Broken\n'
else
  echo "  0 loaded units listed."
fi
STUB

  # sudo: pass-through (preserves PATH so stubs are still found)
  printf '#!/bin/bash\nexec "$@"\n' > "$_TESTDIR/stubs/sudo"

  # df: 50% disk. Override: write integer pct to $_TESTDIR/disk_pct.
  cat > "$_TESTDIR/stubs/df" <<'STUB'
#!/bin/bash
pct=$(cat "$(dirname "$0")/../disk_pct" 2>/dev/null || echo "50")
printf 'Use%%\n%s%%\n' "$pct"
STUB

  chmod +x "$_TESTDIR"/stubs/*
}

teardown() { rm -rf "$_TESTDIR"; }

# Run guardian with given args. Sets $OUT (combined stdout+stderr) and $RC.
run() {
  OUT=$(cd "$_TESTDIR" && PATH="$_TESTDIR/stubs:$PATH" bash "$GUARDIAN" "$@" 2>&1) && RC=0 || RC=$?
}

# Write a complete monitoring config to $_TESTDIR/guardian.conf
full_config() {
  cat > "$_TESTDIR/guardian.conf" <<EOF
telegram_bot_token=fake_token_abc
telegram_user_chat_id=fake_chat_456
send_alert_every_minutes=60
memory_perc_limit=70
disk_space_perc_limit=80
cpu_warning_level=medium
watch_cpu=1
watch_ram=1
watch_services=0
watch_hard_disk=0
EOF
}

# Write a credentials-only config (no monitoring vars) for --test
minimal_config() {
  cat > "$_TESTDIR/guardian.conf" <<EOF
telegram_bot_token=fake_token_abc
telegram_user_chat_id=fake_chat_456
EOF
}

# ── tests ────────────────────────────────────────────────────────────────────

t_help() {
  setup
  run --help
  assert_exit     "help: exits 0"        0 "$RC"
  assert_contains "help: shows Usage"    "Usage:" "$OUT"
  teardown
}

t_missing_config_file() {
  setup
  run --config /nonexistent/path.conf
  assert_exit     "missing config: exits 1"          1 "$RC"
  assert_contains "missing config: reports not found" "not exists" "$OUT"
  teardown
}

t_no_config_file() {
  setup
  # No .config in testdir, no --config flag
  run --watch-cpu 0 --watch-ram 0 --watch-services 0 --watch-hard-disk 0 --warn-every 60
  assert_exit     "no config: exits 1"              1 "$RC"
  assert_contains "no config: config required msg"  "config file is required" "$OUT"
  teardown
}

t_missing_bot_token() {
  setup
  cat > "$_TESTDIR/guardian.conf" <<EOF
telegram_user_chat_id=fake_chat
send_alert_every_minutes=60
watch_cpu=0
watch_ram=0
watch_services=0
watch_hard_disk=0
EOF
  run --config "$_TESTDIR/guardian.conf"
  assert_exit     "missing token: exits 1"          1 "$RC"
  assert_contains "missing token: names variable"   "telegram_bot_token" "$OUT"
  teardown
}

# Fix 4: error message must show the variable NAME, not the empty value
t_missing_chat_id_error_message() {
  setup
  cat > "$_TESTDIR/guardian.conf" <<EOF
telegram_bot_token=fake_token
send_alert_every_minutes=60
watch_cpu=0
watch_ram=0
watch_services=0
watch_hard_disk=0
EOF
  run --config "$_TESTDIR/guardian.conf"
  assert_exit         "missing chatid: exits 1"              1 "$RC"
  assert_contains     "missing chatid: shows variable name"  "telegram_user_chat_id" "$OUT"
  assert_not_contains "missing chatid: not blank variable"   "The variable  not" "$OUT"
  teardown
}

# Fix 2: --test must work with a credentials-only config (no monitoring vars needed)
t_test_minimal_config() {
  setup
  minimal_config
  run --test --config "$_TESTDIR/guardian.conf"
  assert_exit     "test+minimal config: exits 0"                0 "$RC"
  assert_contains "test+minimal config: sends test message"     "Test message sent successfully" "$OUT"
  teardown
}

# Fix 6: --test reports Telegram API errors instead of always succeeding
t_test_curl_200() {
  setup
  full_config
  echo "200" > "$_TESTDIR/curl_code"
  run --test --config "$_TESTDIR/guardian.conf"
  assert_exit     "test 200: exits 0"         0 "$RC"
  assert_contains "test 200: success message" "Test message sent successfully" "$OUT"
  teardown
}

t_test_curl_401() {
  setup
  full_config
  echo "401" > "$_TESTDIR/curl_code"
  run --test --config "$_TESTDIR/guardian.conf"
  assert_exit     "test 401: exits 1"           1 "$RC"
  assert_contains "test 401: shows HTTP code"   "HTTP 401" "$OUT"
  teardown
}

# Fix 1: --test must run before monitoring; a high-CPU server must not bypass it
t_test_runs_before_monitoring() {
  setup
  full_config
  echo "4.00, 4.00, 4.00" > "$_TESTDIR/load"   # 4 cores, 4.00 load → 100% → alert threshold
  run --test --config "$_TESTDIR/guardian.conf" \
      --watch-cpu 1 --cpu-warning-level medium \
      --watch-ram 0 --watch-services 0 --watch-hard-disk 0 --warn-every 60
  assert_exit         "--test before monitoring: exits 0"           0 "$RC"
  assert_contains     "--test before monitoring: test message sent" "Test message sent successfully" "$OUT"
  assert_not_contains "--test before monitoring: no alert fired"    "message has been sent" "$OUT"
  teardown
}

# Fix 3: custom variable name with awk regex chars must not leak other config values
t_awk_injection_prevention() {
  setup
  cat > "$_TESTDIR/guardian.conf" <<EOF
telegram_bot_token=real_token
telegram_user_chat_id=real_chat
other_secret=LEAKED_VALUE
send_alert_every_minutes=60
watch_cpu=0
watch_ram=0
watch_services=0
watch_hard_disk=0
EOF
  # Injection: alternation that would match other_secret= with old regex code
  run --config "$_TESTDIR/guardian.conf" \
      --config-telegram-variable-token "telegram_bot_token|other_secret" \
      --watch-cpu 0 --watch-ram 0 --watch-services 0 --watch-hard-disk 0 --warn-every 60
  assert_not_contains "awk injection: LEAKED_VALUE not in output" "LEAKED_VALUE" "$OUT"
  teardown
}

# Fix 5: lscpu returning 0 cores must not crash with division-by-zero
t_cpu_zero_cores_no_crash() {
  setup
  full_config
  printf '#!/bin/bash\necho "CPU(s):                  0"\n' > "$_TESTDIR/stubs/lscpu"
  chmod +x "$_TESTDIR/stubs/lscpu"
  echo "4.00, 4.00, 4.00" > "$_TESTDIR/load"
  run --config "$_TESTDIR/guardian.conf" \
      --watch-cpu 1 --cpu-warning-level medium \
      --watch-ram 0 --watch-services 0 --watch-hard-disk 0 --warn-every 60
  assert_exit     "zero cores: no crash"    0 "$RC"
  assert_contains "zero cores: all right"  "it's all right" "$OUT"
  teardown
}

# Core: all metrics within limits → clean exit
t_all_clear() {
  setup
  full_config
  run --config "$_TESTDIR/guardian.conf" \
      --watch-cpu 1 --cpu-warning-level medium \
      --watch-ram 1 --watch-services 0 --watch-hard-disk 1 \
      --warn-every 60
  assert_exit     "all clear: exits 0"      0 "$RC"
  assert_contains "all clear: message"      "it's all right" "$OUT"
  teardown
}

# Core: high CPU load triggers alert
t_high_cpu_alert() {
  setup
  full_config
  echo "4.00, 4.00, 4.00" > "$_TESTDIR/load"   # 4 cores × 100% load
  run --config "$_TESTDIR/guardian.conf" \
      --watch-cpu 1 --cpu-warning-level medium \
      --watch-ram 0 --watch-services 0 --watch-hard-disk 0 --warn-every 60
  assert_exit     "high CPU: exits 0"          0 "$RC"
  assert_contains "high CPU: alert triggered"  "message has been sent" "$OUT"
  teardown
}

# Core: high RAM usage triggers alert
t_high_ram_alert() {
  setup
  full_config
  echo "80" > "$_TESTDIR/ram_pct"   # 80% > 70% limit
  run --config "$_TESTDIR/guardian.conf" \
      --watch-cpu 0 --watch-ram 1 --watch-services 0 --watch-hard-disk 0 --warn-every 60
  assert_exit     "high RAM: exits 0"          0 "$RC"
  assert_contains "high RAM: alert triggered"  "message has been sent" "$OUT"
  teardown
}

# Core: failed service triggers alert
t_failed_service_alert() {
  setup
  full_config
  touch "$_TESTDIR/svc_failed"
  run --config "$_TESTDIR/guardian.conf" \
      --watch-cpu 0 --watch-ram 0 --watch-services 1 --watch-hard-disk 0 --warn-every 60
  assert_exit     "failed svc: exits 0"         0 "$RC"
  assert_contains "failed svc: alert triggered" "message has been sent" "$OUT"
  teardown
}

# Core: disk over limit triggers alert
t_disk_full_alert() {
  setup
  full_config
  echo "90" > "$_TESTDIR/disk_pct"   # 90% > 80% limit
  run --config "$_TESTDIR/guardian.conf" \
      --watch-cpu 0 --watch-ram 0 --watch-services 0 --watch-hard-disk 1 --warn-every 60
  assert_exit     "disk full: exits 0"          0 "$RC"
  assert_contains "disk full: alert triggered"  "message has been sent" "$OUT"
  teardown
}

# ── run all ──────────────────────────────────────────────────────────────────
echo "Running guardian tests..."
echo ""

t_help
t_missing_config_file
t_no_config_file
t_missing_bot_token
t_missing_chat_id_error_message
t_test_minimal_config
t_test_curl_200
t_test_curl_401
t_test_runs_before_monitoring
t_awk_injection_prevention
t_cpu_zero_cores_no_crash
t_all_clear
t_high_cpu_alert
t_high_ram_alert
t_failed_service_alert
t_disk_full_alert

echo ""
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  _green "All tests passed."
else
  _red "$FAIL test(s) failed."
  exit 1
fi
