# PostgreSQL High Availability on Kubernetes

A fault-tolerant PostgreSQL platform deployed on Kubernetes using **CloudNativePG**, with automatic failover, persistent storage, topology-aware scheduling, AWS S3 backups, WAL archiving, Point-in-Time Recovery (PITR), Prometheus/Grafana monitoring, alerting, and failure testing.

## Architecture

![PostgreSQL HA Architecture](docs/architecture.png)

The platform consists of:

* **3 PostgreSQL instances** managed by CloudNativePG
* Streaming replication with automatic primary failover
* Persistent storage for each PostgreSQL instance
* Topology-aware scheduling across Kubernetes nodes
* AWS S3 for backups and WAL archiving
* Prometheus and Grafana for monitoring
* PrometheusRule-based alerting
* Python workload generator for failure testing

> The Kubernetes environment is a local Kind cluster. The topology zones simulate node separation and do not represent real availability zones.

---

## Technologies

| Technology        | Purpose                                |
| ----------------- | -------------------------------------- |
| Kubernetes / Kind | Container orchestration                |
| CloudNativePG     | PostgreSQL HA and lifecycle management |
| PostgreSQL        | Database                               |
| AWS S3            | Backup and WAL storage                 |
| Barman Cloud      | Backup/WAL archiving                   |
| Terraform         | AWS infrastructure                     |
| Prometheus        | Metrics and alerting                   |
| Grafana           | Monitoring                             |
| Python / Bash     | Load generation and chaos testing      |

---

## High Availability

Applications connect through the CloudNativePG read/write service:

```text
pg-cluster-rw
```

rather than directly to a PostgreSQL pod.

When the primary fails, CloudNativePG automatically promotes a healthy replica and updates the read/write service.

The project tested:

* Graceful primary failure
* Forced primary failure
* Replica failure
* Kubernetes node drain

---

## Failure Testing Results

A custom Python load generator continuously writes to PostgreSQL while failures are introduced. It records successful requests, failed requests, latency, and acknowledged writes.

### Primary Failure — Graceful

| Metric                     |         Result |
| -------------------------- | -------------: |
| Tests                      | 5/5 successful |
| Failed requests            |              0 |
| Acknowledged writes lost   |              0 |
| Avg. full cluster recovery |         81.4 s |
| Avg. observed write gap    |       ~0.054 s |

### Primary Failure — Forced

| Metric                     |         Result |
| -------------------------- | -------------: |
| Tests                      | 5/5 successful |
| Avg. failed requests       |           26.2 |
| Acknowledged writes lost   |              0 |
| Avg. write interruption    |       ~20.09 s |
| Avg. full cluster recovery |         66.0 s |

### Replica Failure

| Metric                   |   Result |
| ------------------------ | -------: |
| Tests                    |      5/5 |
| Primary failovers        |        0 |
| Failed requests          |        0 |
| Acknowledged writes lost |        0 |
| Avg. write gap           | ~0.058 s |

> Full cluster recovery time and application write interruption are measured separately. A cluster can take longer to return to 3/3 healthy instances while application write interruption remains much shorter.

---

## Backup & Point-in-Time Recovery

High availability protects against instance failures, but replication alone does not protect against accidental data deletion or logical corruption.

The project therefore implements:

* PostgreSQL base backups
* Continuous WAL archiving
* AWS S3 external storage
* Point-in-Time Recovery

### PITR Validation

| Metric         |    Result |
| -------------- | --------: |
| Backup source  |    AWS S3 |
| Test dataset   | 1000 rows |
| Recovered rows | 1000/1000 |
| Recovery time  |    ~105 s |

Backups are managed using the **CloudNativePG Barman Cloud plugin**.

The S3 infrastructure is provisioned with Terraform.

---

## Monitoring & Alerting

Prometheus and Grafana are used to monitor the PostgreSQL cluster.

The dashboard tracks:

* PostgreSQL instances ready
* Replication lag
* WAL archive failures
* Transactions/sec
* Database connections
* WAL archive activity
* Replica WAL receiver status

Configured Prometheus alerts include:

* PostgreSQL collector down
* Replica not streaming
* High replication lag
* WAL archive failures
* WAL archiving stalled
* Collector errors
* High connection wait count
* High rollback rate

---

## Project Structure

```text
pg-ha-k8s/
├── cluster/
├── backup/
├── monitoring/
│   ├── alerts/
│   └── dashboard.json
├── loadgen/
├── chaos/
├── slo/
├── terraform-s3/
├── docs/
└── README.md
```

---

## Deployment

### Prerequisites

* Docker
* Kind
* kubectl
* Helm
* Terraform
* AWS CLI
* AWS account

### Create the Kubernetes cluster

```bash
kind create cluster --config kind-config.yaml --name pg-lab
```

### Deploy PostgreSQL

```bash
kubectl apply -f cluster/
```

Verify:

```bash
kubectl get cluster pg-cluster
kubectl get pods -l cnpg.io/cluster=pg-cluster -o wide
```

### Deploy monitoring

```bash
kubectl apply -f monitoring/
```

### Configure AWS S3

```bash
cd terraform-s3
terraform init
terraform plan
terraform apply
```

Then configure the CloudNativePG ObjectStore and backup resources.

---

## Limitations

This project runs on a local Kind environment.

Therefore:

* Kubernetes nodes are not physically independent.
* Topology zones are simulated.
* Persistent storage is node-local.
* Recovery times are laboratory measurements, not production benchmarks.

The node-drain experiment demonstrated the limitation of node-local storage: a PostgreSQL instance whose volume was tied to a drained node could not immediately reschedule to another node.

---

## Key Takeaways

This project demonstrates practical experience with:

* Kubernetes stateful workloads
* PostgreSQL high availability
* Streaming replication
* Automatic failover
* Persistent storage
* Backup and disaster recovery
* WAL archiving and PITR
* AWS S3
* Terraform
* Prometheus/Grafana
* SRE-oriented failure testing
* Reliability measurement and SLOs

The focus of the project is not simply deploying PostgreSQL on Kubernetes, but **designing, testing, monitoring, and measuring a fault-tolerant database platform**.

---

## Author

**Omar Ahorrar**
Cloud & DevOps Engineering Student — ENSIMAG / INPT
