#!/usr/bin/env bash
# Report which cosmic-comp is running and how much CPU it and its llvmpipe
# (software rendering) threads use over a sampling window.
#
# Usage: tools/measure.sh [seconds]   (default: 10)
# Run it while reproducing the workload (moving windows on the DisplayLink
# monitor, opening the workspace overview, ...).
set -euo pipefail

secs=${1:-10}
pid=$(pgrep -x cosmic-comp | head -n1) || { echo "cosmic-comp is not running" >&2; exit 1; }
hz=$(getconf CLK_TCK)

exe=$(readlink "/proc/$pid/exe")
owner=$(pacman -Qoq "$exe" 2>/dev/null || echo "not owned by a package")
echo "cosmic-comp pid $pid: $exe ($owner)"

echo -n "DisplayLink (evdi) outputs:"
found=0
for s in /sys/class/drm/card*-*/status; do
    conn=$(basename "$(dirname "$s")")
    dev=$(readlink -f "/sys/class/drm/${conn%%-*}/device/driver" 2>/dev/null || true)
    if [[ $dev == */evdi && $(cat "$s") == connected ]]; then
        echo -n " $conn"
        found=1
    fi
done
[ "$found" -eq 1 ] || echo -n " none"
echo

if journalctl -b --no-pager -o cat "_PID=$pid" 2>/dev/null | grep -q 'will use primary GPU for rendering'; then
    echo "Patch active: evdi outputs are rendered on the primary GPU"
elif journalctl -b --no-pager -o cat "_PID=$pid" 2>/dev/null | grep -q 'Falling back to cpu-copy'; then
    echo "Patch NOT active: compositor fell back to cpu-copy for evdi"
else
    echo "Patch status unknown (no matching log lines for this compositor)"
fi

sample() {
    local total=0 lp=0 t c ticks
    for t in /proc/"$pid"/task/*; do
        read -r c < "$t/comm" || continue
        ticks=$(awk '{print $14 + $15}' "$t/stat" 2>/dev/null) || continue
        total=$((total + ticks))
        [[ $c == llvmpipe* ]] && lp=$((lp + ticks))
    done
    echo "$total $lp"
}

read -r t0 l0 < <(sample)
timeout "$secs" tail -f /dev/null || true
read -r t1 l1 < <(sample)

awk -v t=$((t1 - t0)) -v l=$((l1 - l0)) -v s="$secs" -v hz="$hz" 'BEGIN {
    printf "Over %ss: cosmic-comp %.2f cores, of which llvmpipe %.2f cores\n", s, t/hz/s, l/hz/s
}'
