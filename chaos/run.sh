#!/bin/bash

# Usage:
#   ./run.sh <label> <primary-force|primary-graceful|replica>
#
# Examples:
#   ./run.sh force-1 primary-force
#   ./run.sh graceful-1 primary-graceful
#   ./run.sh replica-1 replica

set -u

LABEL=$1
ACTION=$2

OUT=~/pg-ha-k8s/docs/results-notes.txt
CLUSTER=pg-cluster
LOADGEN=loadgen

# --------------------------------------------------
# Helper functions
# --------------------------------------------------

cluster_phase() {
    kubectl get cluster "$CLUSTER" \
        -o jsonpath='{.status.phase}'
}

current_primary() {
    kubectl get cluster "$CLUSTER" \
        -o jsonpath='{.status.currentPrimary}'
}

timestamp() {
    date -u +%s
}

# --------------------------------------------------
# 1. Check arguments
# --------------------------------------------------

if [ "$#" -ne 2 ]; then
    echo "Usage: ./run.sh <label> <primary-force|primary-graceful|replica>"
    exit 1
fi

case "$ACTION" in
    primary-force|primary-graceful|replica)
        ;;
    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac

echo "========================================"
echo "Experiment: $LABEL"
echo "Action:     $ACTION"
echo "========================================"

# --------------------------------------------------
# 2. Wait for a healthy PostgreSQL cluster
# --------------------------------------------------

echo "[1/7] Waiting for healthy cluster..."

until [ "$(cluster_phase)" = "Cluster in healthy state" ]; do
    sleep 3
done

echo "Cluster is healthy."

# --------------------------------------------------
# 3. Start a fresh load generator
# --------------------------------------------------

echo "[2/7] Starting load generator..."

kubectl delete pod "$LOADGEN" \
    --now \
    --ignore-not-found >/dev/null 2>&1

kubectl apply \
    -f ~/pg-ha-k8s/loadgen/loadgen-pod.yaml >/dev/null

echo "Waiting for load generator to start writing..."

until kubectl exec "$LOADGEN" -- \
    test -s /tmp/log.jsonl 2>/dev/null
do
    sleep 1
done

echo "Load generator is writing."

# --------------------------------------------------
# 4. Start timeline monitor
# --------------------------------------------------

TIMELINE="/tmp/pg-ha-timeline.txt"

rm -f "$TIMELINE"

(
    while true; do
        echo "$(date -u +%s) $(date -u +%H:%M:%S) $(current_primary) | $(cluster_phase)"
        sleep 1
    done
) > "$TIMELINE" &

TL=$!

# Give the system 25 seconds of normal traffic
echo "[3/7] Running normal traffic for 25 seconds..."
sleep 25

# --------------------------------------------------
# 5. Record state before failure
# --------------------------------------------------

BEFORE=$(current_primary)
KILL_EPOCH=$(timestamp)
KILL_TIME=$(date -u +%H:%M:%S)

REPLICA=$(kubectl get pod \
    -l cnpg.io/cluster="$CLUSTER",cnpg.io/instanceRole=replica \
    -o name |
    head -1 |
    cut -d/ -f2)

echo "[4/7] Injecting failure..."
echo "Primary before: $BEFORE"

case "$ACTION" in

    primary-force)
        TARGET="$BEFORE"
        kubectl delete pod "$TARGET" \
            --grace-period=0 \
            --force
        ;;

    primary-graceful)
        TARGET="$BEFORE"
        kubectl delete pod "$TARGET"
        ;;

    replica)
        TARGET="$REPLICA"
        kubectl delete pod "$TARGET"
        ;;

esac

# --------------------------------------------------
# 6. Wait for load generator and cluster recovery
# --------------------------------------------------

echo "[5/7] Waiting for load generator to finish..."

until kubectl logs "$LOADGEN" 2>/dev/null |
    grep -q "RUN FINISHED"
do
    sleep 3
done

RUN_END=$(timestamp)

echo "[6/7] Waiting for cluster to become healthy..."

until [ "$(cluster_phase)" = "Cluster in healthy state" ]; do
    sleep 3
done

RECOVERY_END=$(timestamp)

AFTER=$(current_primary)

kill "$TL" 2>/dev/null || true

# --------------------------------------------------
# 7. Calculate and save results
# --------------------------------------------------

RESULT=$(kubectl exec "$LOADGEN" -- \
    python /app/lg.py verify)

FAILURE_DURATION=$((RECOVERY_END - KILL_EPOCH))

{
    echo "========================================"
    echo "Experiment: $LABEL"
    echo "Action: $ACTION"
    echo "Target: $TARGET"
    echo "Kill time UTC: $KILL_TIME"
    echo "Primary before: $BEFORE"
    echo "Primary after:  $AFTER"
    echo "CNPG recovery time: ${FAILURE_DURATION}s"
    echo
    echo "--- timeline (changes only) ---"

    awk '
    {
        t=$2
        $1=""
        $2=""
        sub(/^  */, "", $0)

        if ($0 != previous) {
            print t " " $0
            previous=$0
        }
    }
    ' "$TIMELINE"

    echo
    echo "--- writer verification ---"
    echo "$RESULT"
    echo

} | tee -a "$OUT"

echo "[7/7] Experiment complete."
echo "Results saved to:"
echo "$OUT"