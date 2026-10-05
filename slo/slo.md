# PostgreSQL HA Service Level Objectives

## Scope

These SLOs apply to the PostgreSQL HA platform deployed on Kubernetes
using CloudNativePG.

The platform provides:

- PostgreSQL high availability
- automatic primary failover
- streaming replication
- persistent storage
- monitoring
- backup and WAL archiving
- point-in-time recovery

---

## SLO 1 — Availability

### Objective

The PostgreSQL write endpoint should remain available during normal
operation and recover automatically after a primary failure.

### Target

99.9% availability.

### Measurement

The application connects through:

    pg-cluster-rw

Availability is evaluated using successful application write operations.

---

## SLO 2 — Automatic Failover

### Objective

After an unexpected primary failure, CloudNativePG should automatically
promote a healthy replica.

### Target

New primary selected within 30 seconds.

### Measurement

Measure the time between:

- primary failure injection
- new primary detection

---

## SLO 3 — Data Integrity

### Objective

No acknowledged write should be lost after a primary failure.

### Target

0 acknowledged writes lost.

### Measurement

The load generator records every successful write.

After recovery, acknowledged IDs are compared with the rows stored
in PostgreSQL.

---

## SLO 4 — Cluster Health

### Objective

The PostgreSQL cluster should normally have all configured instances
healthy.

### Target

3/3 PostgreSQL instances ready.

### Measurement

CloudNativePG cluster status and Kubernetes pod readiness.

---

## SLO 5 — Recovery Point Objective

### Objective

Limit potential data loss when recovering from backups.

### Target

The backup architecture provides continuous WAL archiving so that
recovery can target a specific point in time.

### Measurement

Validate using PITR experiments.

---

## SLO 6 — Recovery Time Objective

### Objective

Recover PostgreSQL data from an external backup after a disaster.

### Target

PITR recovery under 2 minutes for the current laboratory dataset.

This target is specific to the current test environment and dataset size.
Production targets would need to be established using realistic workloads.

---

# Current experimental results

## Graceful primary failure

- 5 experiments
- 0 failed writes
- 0 lost writes
- average observed write gap: approximately 0.05 seconds
- average cluster recovery time: approximately 81 seconds

Note: cluster recovery time includes the time required for the complete
CloudNativePG cluster to return to a healthy state. It is not equivalent
to application downtime.

## Force primary failure

- 5 experiments
- automatic failover: 5/5
- average failed requests: approximately 26
- average write interruption: approximately 20 seconds
- 0 lost acknowledged writes
- average cluster recovery time: approximately 66 seconds

The shorter cluster recovery time does not mean force failure is better.
The application experienced significantly more failed requests.

## Replica failure

- 5 experiments
- primary remained unchanged
- 0 failed writes
- 0 lost writes
- average observed write gap: approximately 0.06 seconds

## Node drain

The PostgreSQL service remained available, but the affected PostgreSQL
instance could not be rescheduled because its local persistent volume
was tied to the drained node.

This is a storage limitation of the Kind laboratory environment rather
than a PostgreSQL failover failure.

## PITR

PITR successfully recovered the test dataset from AWS S3.

The experiment recovered 1000/1000 test rows.