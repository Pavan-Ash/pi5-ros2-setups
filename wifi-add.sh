#!/usr/bin/env bash
#
# wifi-add.sh — add one Wi-Fi network to /etc/netplan/50-cloud-init.yaml
#
# Edit the CONFIG block below, then:
#   chmod 600 wifi-add.sh        # it holds a password — keep it unreadable
#   sudo ./wifi-add.sh
#
# Existing SSIDs are preserved. Re-running with the same SSID updates its
# password rather than duplicating it.
#
set -euo pipefail

# ============================== CONFIG ======================================
# Change these two lines each time you want to add a network.

WIFI_SSID="ChangeMe"
WIFI_PASSWORD="ChangeMe"

# Optional.
WIFI_HIDDEN=false          # true only if the AP does not broadcast its SSID
IFACE="wlan0"
NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
AUTO_APPLY=false           # false = netplan try (120s auto-revert, safer over SSH)
                           # true  = netplan apply (no safety net)
# ============================ END CONFIG ====================================

die() { echo "error: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run with sudo"
[ -f "$NETPLAN_FILE" ] || die "$NETPLAN_FILE not found"
[ "$WIFI_SSID" != "ChangeMe" ] || die "edit the CONFIG block first"
command -v netplan >/dev/null || die "netplan not installed"
python3 -c 'import yaml' 2>/dev/null || die "run: apt install -y python3-yaml"

# WPA passphrases are 8-63 chars; anything else silently fails to associate.
if [ -n "$WIFI_PASSWORD" ] && { [ ${#WIFI_PASSWORD} -lt 8 ] || [ ${#WIFI_PASSWORD} -gt 63 ]; }; then
  die "WPA passphrase must be 8-63 characters (got ${#WIFI_PASSWORD})"
fi

# Warn if the script itself is world-readable — it contains a password.
PERMS="$(stat -c '%a' "$0")"
case "$PERMS" in
  600|700) ;;
  *) echo "warning: $0 is mode $PERMS — run 'chmod 600 $0' to protect the password" ;;
esac

# ------------------------------------------------------------------- backups
# .orig is written once and never overwritten: the only pristine copy.
[ -f "${NETPLAN_FILE}.orig" ] || {
  cp -a "$NETPLAN_FILE" "${NETPLAN_FILE}.orig"
  echo "pristine backup: ${NETPLAN_FILE}.orig"
}
ROLLBACK="${NETPLAN_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$NETPLAN_FILE" "$ROLLBACK"
echo "rollback copy:   $ROLLBACK"

# ------------------------------------------------------------------ edit yaml
# Values pass through the environment, never argv — argv is visible in `ps`.
NETPLAN_FILE="$NETPLAN_FILE" IFACE="$IFACE" \
WIFI_SSID="$WIFI_SSID" WIFI_PASSWORD="$WIFI_PASSWORD" WIFI_HIDDEN="$WIFI_HIDDEN" \
python3 - <<'PY'
import os, yaml

path  = os.environ["NETPLAN_FILE"]
iface = os.environ["IFACE"]
ssid  = os.environ["WIFI_SSID"]
pw    = os.environ["WIFI_PASSWORD"]

doc   = yaml.safe_load(open(path)) or {}
net   = doc.setdefault("network", {})
net.setdefault("version", 2)
dev   = net.setdefault("wifis", {}).setdefault(iface, {})
dev.setdefault("dhcp4", True)
dev.setdefault("optional", True)      # don't block boot waiting for wifi
aps   = dev.setdefault("access-points", {})

existing = set(aps)
entry = {}
if pw:
    entry["password"] = pw            # omit the key entirely for an open AP
if os.environ["WIFI_HIDDEN"].lower() == "true":
    entry["hidden"] = True
aps[ssid] = entry

print("updated:" if ssid in existing else "added:", ssid)
print("total networks configured:", len(aps))

with open(path, "w") as f:
    yaml.safe_dump(doc, f, default_flow_style=False, sort_keys=False)
PY

chmod 600 "$NETPLAN_FILE"

# ------------------------------------------------------------------ validate
echo "validating..."
if ! netplan generate; then
  cp -a "$ROLLBACK" "$NETPLAN_FILE"
  die "netplan rejected the config — original restored, nothing changed"
fi
echo "config valid."

# --------------------------------------------------------------------- apply
if [ "$AUTO_APPLY" = true ]; then
  netplan apply
  echo "applied."
else
  echo
  echo "Running 'netplan try'. You are connected over $IFACE."
  echo "If the link drops, do nothing — it reverts automatically in 120s."
  echo "Press ENTER at the prompt only if you are still connected."
  echo
  netplan try || {
    cp -a "$ROLLBACK" "$NETPLAN_FILE"
    die "netplan try failed — original restored"
  }
fi

echo
echo "Configured SSIDs:"
NETPLAN_FILE="$NETPLAN_FILE" IFACE="$IFACE" python3 - <<'PY'
import os, yaml
d = yaml.safe_load(open(os.environ["NETPLAN_FILE"])) or {}
aps = ((d.get("network") or {}).get("wifis") or {}).get(os.environ["IFACE"], {}).get("access-points") or {}
for s in aps:
    print(" -", s)
PY
echo
echo "To undo: sudo cp $ROLLBACK $NETPLAN_FILE && sudo netplan apply"
