#!/bin/bash
# Replace SSH host keys that were shipped inside published WLAN Pi OS images.
#
# Full images from 26.10-dev.3 to 26.10-rc.1 (pi-gen) included one set of host
# keys per release, so every device flashed from the same image shares them.
# If any host key on this device matches one of those, remove all host keys and
# generate new ones. Devices with their own keys are left alone.
#
# Exit status: 0 = nothing to do, 10 = keys replaced, 1 = replacement failed.

SSH_DIR="${SSH_DIR:-/etc/ssh}"

# SHA256 fingerprints of the host keys shipped in published images.
SHIPPED_FINGERPRINTS="
SHA256:dNeH/r5kJdDlOQETsii76xqoKDyGyNB9p+gg9DW1ieQ
SHA256:Vj0oK+G5atfQxnfxcfhvsgSnZEgQOC4nQoZCVR09N0Y
SHA256:35lSSwPSvNF/49HVEKj/PK3S3vMvK1YBMWVNpIewXgU
SHA256:jHR7urCUeIQAFVH9J9edAXyoH3nt2IEFD8/Hl565Zls
SHA256:YsQJ+epj457FUwi+7pHOwUAT4qsvTXDLmJzuX5HU6CY
SHA256:AhAFKMVsnRQoAarCtTtronzWf7lNDN+t45rWtAoXwtM
SHA256:PzrwZ8Hs7oj/awuhDvEPTNIcgDn+paHLYNfADRmkWl0
SHA256:34XlMgGj+z4ojgI9aqNgG/97wIPCNtS6etxWe4H4FR8
SHA256:P2EvTYOgwE4g3X6IoKJCrp/1kho20+Fkqp+hKTQy6lk
SHA256:1hTVEdLopARZagwg+LwbWU8hsBPVU7fcSEDeIBzbiGI
SHA256:ukCL9ckOLmV/oy5diz+0soAtLz4R8NK9hFDX7+ZZ3QQ
SHA256:jkXPROCvNYVez+wqjmO1Ql3YRfspSlgm5jNX4Wzi9hs
SHA256:0Y1OglU0SVL2++4mBXKGGcO+xPVFXdxjBssBFJwJfgY
SHA256:f8bQk/OmRFlI/gxBhj6gd43DJXcwAtjjK+Elp5rPP/Y
SHA256:OLbHxeyErgAAxH+KEY3eop10kczER2BBM53ZsvZiiWw
"

shipped=0
for pub in "$SSH_DIR"/ssh_host_*_key.pub; do
    [ -f "$pub" ] || continue
    fp=$(ssh-keygen -lf "$pub" 2>/dev/null | cut -d' ' -f2)
    if [ -n "$fp" ] && printf '%s\n' "$SHIPPED_FINGERPRINTS" | grep -qxF -- "$fp"; then
        shipped=1
        break
    fi
done
[ "$shipped" = 1 ] || exit 0

echo "SSH host keys on this device were shipped in a published image; generating new ones."
rm -f "$SSH_DIR"/ssh_host_*_key "$SSH_DIR"/ssh_host_*_key.pub
# -A writes to <root>/etc/ssh; derive the root from SSH_DIR.
ssh-keygen -A -f "${SSH_DIR%/etc/ssh}/"
# ssh-keygen -A exits 0 even when it cannot write a key, so check the result.
for type in rsa ecdsa ed25519; do
    if [ ! -s "$SSH_DIR/ssh_host_${type}_key" ]; then
        echo "Failed to generate $SSH_DIR/ssh_host_${type}_key" >&2
        exit 1
    fi
done
logger -t wlanpi-common "Replaced SSH host keys shipped in a published image" 2>/dev/null || true
exit 10
