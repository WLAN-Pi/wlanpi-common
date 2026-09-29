#!/bin/sh
# Shipped host keys are replaced, a device's own keys are not, and a second run
# changes nothing. Runs the script against a scratch /etc/ssh.
set -eu

S=opt/wlanpi-common/wlanpi-rotate-shared-host-keys.sh
grep -q "$S\\|wlanpi-rotate-shared-host-keys.sh" debian/postinst ||
    { echo "FAIL: postinst does not run the rotation"; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
D=$T/etc/ssh
mkdir -p "$D"
fps() { for k in rsa ecdsa ed25519; do ssh-keygen -lf "$D/ssh_host_${k}_key.pub" | cut -d' ' -f2; done; }
fail=0
check() {
    if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1 (got '$2', want '$3')"; fail=1; fi
}

# Own keys: left alone.
ssh-keygen -q -A -f "$T/"
before=$(fps)
rc=0; SSH_DIR=$D bash "$S" >/dev/null 2>&1 || rc=$?
check "own keys: exit status" "$rc" 0
check "own keys: unchanged" "$(fps)" "$before"

# One shipped key (fingerprint added to a copy of the list): all replaced.
own_ed=$(ssh-keygen -lf "$D/ssh_host_ed25519_key.pub" | cut -d' ' -f2)
sed "s#^SHIPPED_FINGERPRINTS=\"#&\\n$own_ed#" "$S" > "$T/rotate.sh"
before=$(fps)
rc=0; SSH_DIR=$D bash "$T/rotate.sh" >/dev/null 2>&1 || rc=$?
check "shipped key: exit status" "$rc" 10
for k in rsa ecdsa ed25519; do
    check "shipped key: ssh_host_${k}_key present" "$([ -s "$D/ssh_host_${k}_key" ] && echo yes)" yes
done
after=$(fps)
check "shipped key: every fingerprint changed" \
    "$(printf '%s\n%s\n' "$before" "$after" | sort | uniq -d | wc -l)" 0

# Second run: the new keys are not in the list, nothing changes.
rc=0; SSH_DIR=$D bash "$T/rotate.sh" >/dev/null 2>&1 || rc=$?
check "second run: exit status" "$rc" 0
check "second run: unchanged" "$(fps)" "$after"

# No keys at all: nothing to do.
rm -f "$D"/ssh_host_*
rc=0; SSH_DIR=$D bash "$S" >/dev/null 2>&1 || rc=$?
check "no keys: exit status" "$rc" 0

exit "$fail"
