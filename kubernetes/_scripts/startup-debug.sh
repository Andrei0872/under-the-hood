#!/usr/bin/env bash
# Start hack/local-up-cluster.sh with some components paused under dlv, so they
# can be debugged from their first line.
#
#   STARTUP_DEBUG=kube-apiserver,kubelet kubernetes/_scripts/startup-debug.sh
#
# Build with `make DBG=1 WHAT=...` first. Extra arguments go to
# local-up-cluster.sh (don't pass -O: it would override GO_OUT).
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
K8S_SRC="$REPO_ROOT/kubernetes/_upstream"
BIN_DIR="$K8S_SRC/_output/local/bin/$(go env GOOS)/$(go env GOARCH)"
DLV="$(command -v dlv || echo "$HOME/go/bin/dlv")"  # absolute: sudo resets PATH

# One fixed dlv port per component.
declare -A PORTS=(
    [kube-apiserver]=2345
    [kube-controller-manager]=2346
    [kube-scheduler]=2347
    [kubelet]=2348
    [kube-proxy]=2349
)

# Paused components block startup, so every wait in the script gets an hour.
# Patched in by _patches/0001-configurable-startup-waits.patch, except the first.
DEBUG_WAIT=${DEBUG_WAIT:-3600}
export WAIT_FOR_URL_API_SERVER=${WAIT_FOR_URL_API_SERVER:-$DEBUG_WAIT}
export WAIT_FOR_NODE=${WAIT_FOR_NODE:-$DEBUG_WAIT}
export WAIT_FOR_NODE_READY=${WAIT_FOR_NODE_READY:-$DEBUG_WAIT}
export WAIT_FOR_COREDNS=${WAIT_FOR_COREDNS:-$DEBUG_WAIT}

IFS=, read -ra components <<< "${STARTUP_DEBUG:-}"
for c in "${components[@]}"; do
    [[ -n "${PORTS[$c]-}" ]] || { echo "unknown component in STARTUP_DEBUG: $c (one of: ${!PORTS[*]})" >&2; exit 1; }
done
[[ -x "$DLV" ]] || { echo "dlv not found" >&2; exit 1; }
[[ -d "$BIN_DIR" ]] || { echo "no binaries in $BIN_DIR, build them first" >&2; exit 1; }

# local-up-cluster.sh runs every component as ${GO_OUT}/<name>. Point GO_OUT at
# a directory of stand-ins: a dlv wrapper for each component to debug, a
# symlink to the real binary for everything else.
STAND_INS="$(mktemp -d)"
trap 'rm -rf "$STAND_INS"' EXIT

for bin in "$BIN_DIR"/*; do
    name="$(basename "$bin")"
    if [[ ",${STARTUP_DEBUG:-}," == *",$name,"* ]]; then
        # --only-same-user=false: the kubelet and kube-proxy run under sudo, so
        # their dlv runs as root while the debug client runs as you.
        cat > "$STAND_INS/$name" <<EOF
#!/usr/bin/env bash
exec "$DLV" exec "$bin" --headless --listen=127.0.0.1:${PORTS[$name]} \\
    --api-version=2 --accept-multiclient --only-same-user=false --check-go-version=false -- "\$@"
EOF
        chmod +x "$STAND_INS/$name"
        echo -e "\033[33m[startup-debug]\033[0m $name paused, dlv listening on 127.0.0.1:${PORTS[$name]}"
    else
        ln -s "$bin" "$STAND_INS/$name"
    fi
done

cd "$K8S_SRC"
GO_OUT="$STAND_INS" hack/local-up-cluster.sh "$@"
