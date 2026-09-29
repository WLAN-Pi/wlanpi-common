#!/bin/bash
# wlanpi-rotate-shared-host-keys.sh: every shipped key (tests/fixtures) is in
# the list and triggers a full replacement, a device's own keys are not
# touched, a second run is a no-op, and failures leave the current keys alone.
set -eu

S=$PWD/opt/wlanpi-common/wlanpi-rotate-shared-host-keys.sh
FIX=$PWD/tests/fixtures/shipped-host-keys.pub
REAL_KEYGEN=$(command -v ssh-keygen)

T=$(mktemp -d)
trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
D=$T/etc/ssh
fail=0
check() {
    if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1 (got '$2', want '$3')"; fail=1; fi
}
fresh() { rm -rf "$D"; mkdir -p "$D"; ssh-keygen -q -A -f "$T/"; }
fps() { for k in rsa ecdsa ed25519; do ssh-keygen -lf "$D/ssh_host_${k}_key" | cut -d' ' -f2; done; }
run() { rc=0; SSH_DIR=$D bash "${1:-$S}" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
shared() { printf '%s\n%s\n' "$1" "$2" | sort | uniq -d | wc -l; }

grep -q 'wlanpi-rotate-shared-host-keys.sh' debian/postinst || { echo "FAIL: postinst does not run it"; exit 1; }
grep -q '10) deb-systemd-invoke try-restart ssh.service' debian/postinst ||
    { echo "FAIL: postinst must restart ssh only on exit 10"; exit 1; }

# The list holds exactly the fingerprints of the shipped public keys.
listed=$(grep -oE '^SHA256:[A-Za-z0-9+/]+$' "$S" | sort)
fixtures=$(ssh-keygen -lf "$FIX" | cut -d' ' -f2 | sort)
check "list: 15 shipped keys" "$(echo "$fixtures" | wc -l)" 15
check "list matches the fixtures" "$listed" "$fixtures"

# Own keys: left alone.
fresh; before=$(fps)
check "own keys: exit status" "$(run)" 0
check "own keys: unchanged" "$(fps)" "$before"

# Each real shipped public key triggers a full replacement.
n=0
while read -r type key tag; do
    fresh; before=$(fps)
    case $type in ssh-rsa) k=rsa ;; ecdsa-*) k=ecdsa ;; ssh-ed25519) k=ed25519 ;; esac
    echo "$type $key" > "$D/ssh_host_${k}_key.pub"
    rc=$(run)
    [ "$rc" = 10 ] && [ "$(shared "$before" "$(fps)")" = 0 ] && [ "$(run)" = 0 ] ||
        { echo "FAIL - shipped $k key from $tag: rc=$rc"; fail=1; continue; }
    n=$((n + 1))
done < "$FIX"
check "each shipped key replaced, second run no-op" "$n" 15

# A shipped private key without its .pub is still found. The list copy adds
# this device's ed25519 fingerprint to stand in for a shipped key.
fresh
own=$(ssh-keygen -lf "$D/ssh_host_ed25519_key" | cut -d' ' -f2)
sed "s#^SHIPPED_FINGERPRINTS=\"#&\\n$own#" "$S" > "$T/rotate.sh"
rm -f "$D/ssh_host_ed25519_key.pub"; before=$(fps)
check "missing .pub: exit status" "$(run "$T/rotate.sh")" 10
check "missing .pub: all keys replaced" "$(shared "$before" "$(fps)")" 0
check "missing .pub: new .pub written" "$([ -s "$D/ssh_host_ed25519_key.pub" ] && echo yes)" yes

# ssh-keygen -A writes nothing (it exits 0 on write errors): current keys stay.
fresh
own=$(ssh-keygen -lf "$D/ssh_host_ed25519_key" | cut -d' ' -f2)
sed "s#^SHIPPED_FINGERPRINTS=\"#&\\n$own#" "$S" > "$T/rotate.sh"
mkdir -p "$T/bin"
printf '#!/bin/sh\ncase " $* " in *" -A "*) exit 0 ;; esac\nexec %s "$@"\n' "$REAL_KEYGEN" > "$T/bin/ssh-keygen"
chmod +x "$T/bin/ssh-keygen"
before=$(fps)
rc=0; PATH="$T/bin:$PATH" SSH_DIR=$D bash "$T/rotate.sh" >/dev/null 2>&1 || rc=$?
check "keygen fails: exit status" "$rc" 1
check "keygen fails: keys unchanged" "$(fps)" "$before"
check "keygen fails: no temp dir left" "$(find "$D" -name '.rotate-host-keys.*' | wc -l)" 0

# Read-only /etc/ssh: nothing can be replaced, current keys stay.
chmod 555 "$D"
check "read-only dir: exit status" "$(run "$T/rotate.sh")" 1
check "read-only dir: keys unchanged" "$(fps)" "$before"
chmod 755 "$D"

# No keys at all: nothing to do.
rm -f "$D"/ssh_host_*
check "no keys: exit status" "$(run)" 0

exit "$fail"
