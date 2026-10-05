#!/bin/bash

# Usage:
#   ./node-drain.sh <label> <node>
#
# Example:
#   ./node-drain.sh drain-worker worker

set -u

LABEL=$1
NODE=$2

OUT=~/pg-ha-k8s/docs/results-notes.txt
CLUSTER=pg-cluster
LOADGEN=loadgen

cluster_phase() {
    kubectl get cluster "$CLUSTER" -o jsonpath='{.status.phase}'
}

current_primary() {
    kubectl get cluster "$CLUSTER" -o jsonpath='{.status.currentPrimary}'
}

timestamp() {
    date -u +%s
}

if [ "$#" -ne 2 ]; then
    echo "Usage: ./node-drain.sh <label> <node>"
    exit 1
fi

echo "========================================"
echo "Experiment: $LABEL"
echo "Action:     node-drain"
echo "Node:       $NODE"
echo "========================================"

echo "[1/8] Checking node..."
kubectl get node "$NODE" \
    -L topology.kubernetes.io/zone

echo
echo "[2/8] Waiting for healthy cluster..."
until [ "$(cluster_phase)" = "Cluster in healthy state" ]; do
    sleep 3
done

echo "Cluster is healthy."

echo
echo "[3/8] Starting load generator..."

kubectl delete pod "$LOADGEN" --now --ignore-not-found >/dev/null 2>&1

kubectl apply \
    -f ~/pg-ha-k8s/loadgen/loadgen-pod.yaml \
    >/dev/null

echo "Waiting for load generator..."

until kubectl exec "$LOADGEN" -- test -s /tmp/log.jsonl 2>/dev/null; do
    sleep 1
done

echo "Load generator is writing."

TIMELINE="/tmp/pg-ha-node-timeline.txt"

rm -f "$TIMELINE"

(
    while true; do
        echo "$(date -u +%s) $(date -u +%H:%M:%S) $(current_primary) | $(cluster_phase)"
        sleep 1
    done
) > "$TIMELINE" &

TL=$!

sleep 25

BEFORE=$(current_primary)
KILL_EPOCH=$(timestamp)
KILL_TIME=$(date -u +%H:%M:%S)

echo
echo "[4/8] Current PostgreSQL placement:"
kubectl get pods \
    -l cnpg.io/cluster="$CLUSTER" \
    -o wide

echo
echo "[5/8] Draining node..."
echo "Node: $NODE"
echo "Primary before: $BEFORE"
echo "Drain time UTC: $KILL_TIME"

kubectl drain "$NODE" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --timeout=120s

DRAIN_EXIT=$?

DRAIN_END=$(timestamp)

echo
echo "kubectl drain exit code: $DRAIN_EXIT"

echo
echo "[6/8] Waiting for load generator to finish..."

until kubectl logs "$LOADGEN" 2>/dev/null | grep -q "RUN FINISHED"; do
    sleep 3
done

RUN_END=$(timestamp)

echo
echo "[7/8] Waiting for cluster to become healthy..."

until [ "$(cluster_phase)" = "Cluster in healthy state" ]; do
    sleep 3
done

RECOVERY_END=$(timestamp)

AFTER=$(current_primary)

# Capture final state before killing monitor
echo "$(date -u +%s) $(date -u +%H:%M:%S) $(current_primary) | $(cluster_phase)" >> "$TIMELINE"

kill "$TL" 2>/dev/null || true

RESULT=$(kubectl exec "$LOADGEN" -- python /app/lg.py verify)

RECOVERY_TIME=$((RECOVERY_END - KILL_EPOCH))

{
    echo
    echo "========================================"
    echo "Experiment: $LABEL"
    echo "Action: node-drain"
    echo "Node: $NODE"
    echo "Drain time UTC: $KILL_TIME"
    echo "Primary before: $BEFORE"
    echo "Primary after:  $AFTER"
    echo "kubectl drain exit: $DRAIN_EXIT"
    echo "CNPG recovery time: ${RECOVERY_TIME}s"
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
    echo "--- PostgreSQL placement after drain ---"

    kubectl get pods \
        -l cnpg.io/cluster="$CLUSTER" \
        -o wide

    echo
    echo "--- writer verification ---"
    echo "$RESULT"

    echo
} | tee -a "$OUT"

echo
echo "[8/8] Experiment complete."

echo
echo "IMPORTANT:"
echo "The node is currently cordoned."
echo "Run:"
echo "  kubectl uncordon $NODE"
echo
echo "Results saved to:"
echo "$OUT"