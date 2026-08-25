#!/bin/zsh

set -u

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || die "This script only supports macOS."

for command_name in route networksetup dig sudo dscacheutil killall; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
done

resolves() {
    local dns_server="${1:-}"
    local answer

    if [[ -n "$dns_server" ]]; then
        answer=$(dig +time=2 +tries=1 +short @"$dns_server" google.com A 2>/dev/null) || return 1
    else
        answer=$(dig +time=2 +tries=1 +short google.com A 2>/dev/null) || return 1
    fi

    [[ -n "${answer//[[:space:]]/}" ]]
}

echo "=== DNS diagnostic ==="

# 1. Find current default interface
IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')

[[ -n "$IFACE" ]] || die "Could not determine default network interface."

echo "Default interface: $IFACE"

# 2. Find macOS network service corresponding to that interface
SERVICE=$(networksetup -listnetworkserviceorder |
    awk -v dev="$IFACE" '
        /^\([0-9]+\)/ {
            service=$0
            sub(/^\([0-9]+\) /, "", service)
        }
        $0 ~ "Device: " dev "\\)" {
            print service
            exit
        }
    ')

[[ -n "$SERVICE" ]] || die "Could not map $IFACE to a macOS network service."

echo "Network service: $SERVICE"

# 3. Get manually configured DNS servers
if ! DNS_OUTPUT=$(networksetup -getdnsservers "$SERVICE" 2>/dev/null); then
    die "Could not read DNS servers for $SERVICE."
fi

if [[ "$DNS_OUTPUT" == "There aren't any DNS Servers set on "* ]]; then
    echo "No manually configured DNS servers found."
    echo "Nothing to fix."
    exit 0
fi

DNS_SERVERS=("${(@f)DNS_OUTPUT}")

echo "Configured DNS:"
for dns in "${DNS_SERVERS[@]}"; do
    echo "  $dns"
done

# 4. Check whether normal DNS resolution already works
echo
echo "Testing normal DNS resolution..."

if resolves; then
    echo "DNS is currently working."
    echo "No changes made."
    exit 0
fi

echo "Normal DNS resolution FAILED."

# 5. Test each configured DNS server directly
WORKING_CONFIGURED_DNS=false

for dns in "${DNS_SERVERS[@]}"; do
    echo "Testing configured DNS $dns..."

    if resolves "$dns"; then
        echo "  $dns works."
        WORKING_CONFIGURED_DNS=true
    else
        echo "  $dns FAILED."
    fi
done

if [[ "$WORKING_CONFIGURED_DNS" == true ]]; then
    echo
    echo "At least one configured DNS server works."
    echo "Not modifying DNS automatically."
    exit 1
fi

# 6. Verify that an external DNS resolver is reachable
echo
echo "Testing fallback resolver 1.1.1.1..."

if ! resolves "1.1.1.1"; then
    echo "Fallback DNS also failed."
    echo
    echo "This looks like a wider network/connectivity problem,"
    echo "NOT merely broken DNS configuration."
    echo "No changes made."
    exit 1
fi

echo "Fallback DNS works."

# 7. We now have:
#    - Internet path available
#    - normal DNS broken
#    - manually configured DNS present
#    - configured DNS servers broken
#
# Safe enough to clear the stale manual DNS configuration.

echo
echo "Broken manually configured DNS detected."
echo "Clearing DNS configuration from:"
echo "  $SERVICE"

sudo networksetup -setdnsservers "$SERVICE" Empty || die "Could not clear DNS servers for $SERVICE."

echo "Flushing macOS DNS caches..."

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

sleep 1

# 8. Final test
echo
echo "Testing DNS after repair..."

if resolves; then
    echo
    echo "SUCCESS: DNS is working again."
    exit 0
else
    echo
    echo "DNS configuration was cleared, but resolution still fails."
    echo "Further diagnosis is required."
    exit 2
fi
