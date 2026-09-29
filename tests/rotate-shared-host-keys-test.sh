#!/bin/bash
# wlanpi-rotate-shared-host-keys.sh: the list matches the shipped keys
# (tests/fixtures), a shipped key triggers a full replacement, a device's own
# keys are not touched, a second run is a no-op, and a keygen or mv failure
# leaves the current keys alone.
set -eu

S=$PWD/opt/wlanpi-common/wlanpi-rotate-shared-host-keys.sh
FIX=$PWD/tests/fixtures/shipped-host-keys.pub
REAL_KEYGEN=$(command -v ssh-keygen)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
D=$T/etc/ssh
fail=0
check() {
    if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1 (got '$2', want '$3')"; fail=1; fi
}
fresh() { rm -rf "$D"; mkdir -p "$D"; ssh-keygen -q -A -f "$T/"; }
fps() { for k in rsa ecdsa ed25519; do ssh-keygen -lf "$D/ssh_host_${k}_key" | cut -d' ' -f2; done; }
# run [dir]: run the script, with fake commands from dir first in PATH.
run() { rc=0; PATH="${1:+$1:}$PATH" SSH_DIR=$D bash "$S" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
tmpdirs() { find "$D" -name '.rotate-host-keys.*' | wc -l; }
shared() { printf '%s\n%s\n' "$1" "$2" | sort | uniq -d | wc -l; }
ship() { head -n1 "$FIX" | cut -d' ' -f1,2 > "$D/ssh_host_rsa_key.pub"; }

# The list holds exactly the fingerprints of the shipped public keys.
listed=$(grep -oE '^SHA256:[A-Za-z0-9+/]+$' "$S" | sort)
fixtures=$(ssh-keygen -lf "$FIX" | cut -d' ' -f2 | sort)
check "list: 15 shipped keys" "$(echo "$fixtures" | wc -l)" 15
check "list matches the fixtures" "$listed" "$fixtures"

# Own keys: left alone.
fresh; before=$(fps)
check "own keys: exit status" "$(run)" 0
check "own keys: unchanged" "$(fps)" "$before"

# A shipped key: all three keys replaced, second run does nothing.
fresh; ship; before=$(fps)
check "shipped key: exit status" "$(run)" 10
check "shipped key: all keys replaced" "$(shared "$before" "$(fps)")" 0
check "shipped key: no temp dir left" "$(tmpdirs)" 0
check "shipped key: second run" "$(run)" 0

# ssh-keygen -A writes empty keys (it exits 0 on write errors): current keys stay.
fresh; ship; before=$(fps)
mkdir -p "$T/keygen" "$T/mv"
cat > "$T/keygen/ssh-keygen" <<EOF
#!/bin/sh
case " \$* " in *" -A "*)
    for d; do :; done
    for t in rsa ecdsa ed25519; do : > "\$d/etc/ssh/ssh_host_\${t}_key"; : > "\$d/etc/ssh/ssh_host_\${t}_key.pub"; done
    exit 0 ;;
esac
exec $REAL_KEYGEN "\$@"
EOF
chmod +x "$T/keygen/ssh-keygen"
check "keygen fails: exit status" "$(run "$T/keygen")" 1
check "keygen fails: keys unchanged" "$(fps)" "$before"
check "keygen fails: no temp dir left" "$(tmpdirs)" 0

# mv fails: exit 1 so postinst doesn't restart sshd, current keys stay.
printf '#!/bin/sh\nexit 1\n' > "$T/mv/mv"; chmod +x "$T/mv/mv"
check "mv fails: exit status" "$(run "$T/mv")" 1
check "mv fails: keys unchanged" "$(fps)" "$before"
check "mv fails: no temp dir left" "$(tmpdirs)" 0

# No keys at all: nothing to do.
rm -f "$D"/ssh_host_*
check "no keys: exit status" "$(run)" 0

exit "$fail"
