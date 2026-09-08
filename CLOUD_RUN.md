# Production Service Health Check Mapping: Local to Cloud Run & Kubernetes

This document provides a conceptual mapping between our local Docker Compose health check implementation for `orders-api` and production cloud container orchestration platforms (Google Cloud Run and Kubernetes).

---

## 1. Mapping Overview

| Local Docker / Compose Concept | Cloud Run Equivalent | Kubernetes (K8s) Equivalent | Purpose & Behavior on Failure |
| :--- | :--- | :--- | :--- |
| **GET `/health`** | **Liveness Probe** (`livenessProbe`) | **Liveness Probe** (`livenessProbe`) | **Process Pulse**: Verifies container process is responsive and not deadlocked.<br>**Failure Action**: Restarts/recreates the container instance. |
| **GET `/ready`** | **Startup Probe** / HTTP Probe | **Readiness Probe** (`readinessProbe`) | **Dependency & Traffic Ready**: Verifies app can serve traffic (e.g., DB ping).<br>**Failure Action**: Removes container from load balancer routing pool (no restarts). |
| **`HEALTHCHECK` Instruction** | Health Check Specification | Container Probe Configuration | Periodic background polling mechanism executed against container endpoints. |

---

## 2. Cloud Run Configuration (YAML / CLI)

In Google Cloud Run, health checks are specified under container service definitions or via `gcloud` flags.

### Cloud Run Service Manifest Mapping
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: orders-api
spec:
  template:
    spec:
      containers:
      - image: gcr.io/my-project/orders-api:latest
        ports:
        - containerPort: 3000
        # Startup Probe - Ensures DB connectivity before routing initial traffic
        startupProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        # Liveness Probe - Ensures application event loop is responsive
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
```

---

## 3. Kubernetes Probe Specification

In Kubernetes, the distinction between **liveness** and **readiness** is explicit and critical for high availability.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: orders-api
  template:
    metadata:
      labels:
        app: orders-api
    spec:
      containers:
      - name: orders-api
        image: orders-api:latest
        ports:
        - containerPort: 3000
        # Liveness: Shallow process check (Restart container if deadlocked)
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        # Readiness: Deep dependency check (Stop routing traffic if DB is down)
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
```

---

## 4. Architectural Rules & Best Practices

> [!WARNING]
> **Golden Rule**: **NEVER put shared external dependencies (like databases or third-party APIs) into a Liveness Probe!**

### Why Liveness must be Shallow:
If a shared database experiences a temporary 30-second network hiccup:
- **Wrong Design (DB check in Liveness)**: Liveness fails across **all** app instances. The orchestrator simultaneously kills and restarts the entire fleet. Cold-starting instances hit the recovering DB all at once, exacerbating the outage.
- **Correct Design (DB check in Readiness only)**: Liveness remains green (`/health` returns `200 OK`). Readiness fails (`/ready` returns `503`). The load balancer temporarily stops sending user requests to the instances. Once DB connectivity is restored, `/ready` passes, and traffic resumes immediately with zero container restarts and zero downtime.
