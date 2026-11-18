# ShelfLife: Comprehensive Project & CI/CD Pipeline Explanation Guide

> **Purpose**: This document provides a complete, structured walkthrough of the entire ShelfLife project. It is specifically designed to help you explain every architectural decision, tool, and pipeline stage with confidence during a project presentation, interview, or viva evaluation.

---

## 📑 Table of Contents

1. [Executive Summary (The 30-Second Elevator Pitch)](#1-executive-summary-the-30-second-elevator-pitch)
2. [End-to-End System Architecture](#2-end-to-end-system-architecture)
3. [The DevOps Tech Stack & Justifications](#3-the-devops-tech-stack--justifications)
4. [Application Architecture & Core Logic](#4-application-architecture--core-logic)
5. [Automated Testing Strategy (Pytest)](#5-automated-testing-strategy-pytest)
6. [Containerization Design (Docker & Gunicorn)](#6-containerization-design-docker--gunicorn)
7. [Infrastructure as Code (Terraform on AWS)](#7-infrastructure-as-code-terraform-on-aws)
8. [The Complete CI/CD Pipeline Walkthrough (Jenkinsfile)](#8-the-complete-cicd-pipeline-walkthrough-jenkinsfile)
9. [Deployment Mechanism & Zero-Downtime Script (`deploy.sh`)](#9-deployment-mechanism--zero-downtime-script-deploysh)
10. [Engineering Challenges Overcome (Real Troubleshooting)](#10-engineering-challenges-overcome-real-troubleshooting)
11. [Top 15 Viva & Interview Questions with Model Answers](#11-top-15-viva--interview-questions-with-model-answers)
12. [Step-by-Step Live Demonstration Script](#12-step-by-step-live-demonstration-script)

---

## 1. Executive Summary (The 30-Second Elevator Pitch)

> **"What is ShelfLife?"**
>
> *"ShelfLife is a cloud-native pantry inventory and food waste reduction application that dynamically calculates expiry dates and alerts users to items expiring soon or already expired. More importantly, it serves as the foundation for an enterprise-grade, fully automated CI/CD pipeline.*
>
> *Every commit pushed to GitHub triggers an automated Jenkins Multibranch Pipeline that creates an isolated virtual environment, runs a 10-test automated suite, packages the app into a secure, non-root Docker container, publishes versioned images to Docker Hub, deploys the updated container over SSH to an AWS EC2 instance, and executes an automated smoke test against the live `/health` endpoint to guarantee zero downtime and maximum reliability."*

---

## 2. End-to-End System Architecture

### Visual Architectural Flowchart

```
[ Developer Local Machine ]
         │  git push (main or dev)
         ▼
[ GitHub Repository: Mona-Agrawall/ShelfLife ]
         │  GitHub Webhook (POST JSON)
         ▼
[ AWS EC2: Jenkins CI Server (184.73.140.54) ]
   ├── Stage 1: Checkout SCM (Clones exact commit SHA)
   ├── Stage 2: Install & Test (Python venv, requirements.txt, Pytest 10/10)
   ├── Stage 3: Build Docker Image (Tagged :BUILD_NUMBER & :latest)
   │
   │───[ IF Branch == 'dev' ] ──▶ Pipeline Ends Safely (Validation only)
   │
   └───[ IF Branch == 'main' ] ──▶ Continues Full CD Lifecycle:
         ├── Stage 4: Push to Docker Hub (Masked credentials: dockerhub-creds)
         │        │
         │        ▼
         │   [ Docker Hub: monaagrawal/shelflife ]
         │
         ├── Stage 5: Deploy to App Server (SSH Agent: app-server-ssh)
         │        │  SCP scripts/deploy.sh
         │        ▼
         │   [ AWS EC2: Production App Server (34.192.143.226) ]
         │        ├── Pulls latest image from Docker Hub
         │        ├── Gracefully stops & removes old container
         │        ├── Starts new container (Port 80 -> Container 5000)
         │        └── Mounts persistent SQLite volume (`shelflife-data:/data`)
         │
         └── Stage 6: Smoke Test
                  │  Polls http://34.192.143.226/health
                  ▼
             Verifies HTTP 200 {"status":"ok"}
```

---

## 3. The DevOps Tech Stack & Justifications

| Technology | Category | Why This Specific Tool Was Chosen |
|---|---|---|
| **Python 3.11 / Flask** | Application Framework | Lightweight micro-framework with zero boilerplate, ideal for microservices and API endpoints. Uses Application Factory pattern for high testability. |
| **Gunicorn** | Production WSGI Server | Multi-threaded, pre-fork worker WSGI server that replaces the single-threaded Flask development server to handle concurrent production requests. |
| **SQLite 3** | Database Engine | Serverless, zero-configuration database persisted via Docker volume. Keeps the infrastructure lightweight while maintaining ACID compliance. |
| **Pytest** | Automated Testing | Industry standard Python testing framework. Generates JUnit XML reports parsed natively by Jenkins for test pass/fail trend graphs. |
| **Docker** | Containerization | Ensures 100% environmental parity ("runs the same on developer laptop, CI server, and production"). Uses non-root user for container security. |
| **Docker Hub** | Container Registry | Centralized, cloud-hosted public registry allowing decoupled image building and deployment. Supports dual-tagging (`:BUILD_NUMBER` + `:latest`). |
| **Jenkins** | CI/CD Automation | Self-hosted, open-source orchestration server. Configured via declarative `Jenkinsfile` (Pipeline-as-Code) with Multibranch support. |
| **Terraform** | Infrastructure as Code | Declarative cloud provisioning tool. Defines EC2 instances, Security Groups, Elastic IPs, and CloudWatch alarms reproducibly with version control. |
| **AWS EC2 (Ubuntu 22.04)** | Cloud Compute | Reliable virtual servers in AWS cloud with dedicated Elastic IPs ensuring static addresses across reboots. |
| **AWS CloudWatch** | Monitoring & Alerting | Continuous observability tracking App Server CPU utilization (> 70% alarm) and aggregating centralized application logs. |

---

## 4. Application Architecture & Core Logic

### 1. Flask Application Factory Pattern (`app/app.py`)
Instead of a global Flask instance, the app uses `create_app(db_path=None)`:
- Allows test cases to inject a temporary, isolated SQLite database path without mutating real user data.
- Reads `DB_PATH` from environment variables, defaulting to `/data/shelflife.db` in Docker and `data/shelflife.db` locally.

### 2. Pure Business Logic: Expiry Calculation (`get_status`)
```python
def get_status(expiry_date, today=None):
    if today is None:
        today = date.today()
    if expiry_date < today:
        return "expired"
    elif (expiry_date - today).days <= 3:
        return "expiring_soon"
    else:
        return "fresh"
```
- **Expired**: Expiry date is in the past (`< today`).
- **Expiring Soon**: Expires within 0 to 3 days from today.
- **Fresh**: Expires in 4 days or more.
- *Pure function design*: The `today` parameter can be overridden, making unit tests completely deterministic without mocking system clocks.

### 3. Application Routes
- `GET /`: Dashboard showing category counters (Dairy, Vegetables, Fruits, etc.) and stat badges (Fresh, Expiring Soon, Expired).
- `GET /add` & `POST /add`: Form to insert new items with server-side validation (name required, quantity > 0, valid ISO date).
- `GET /expiring`: Filtered alert view highlighting items expiring soon or expired in warning colors.
- `GET /inventory`: Full inventory table with chronological sorting and delete buttons.
- `POST /inventory/delete/<id>`: Removes an item from the database with flash messaging.
- `GET /health`: Healthcheck endpoint returning `{"status":"ok"}` with HTTP 200. Crucial for Docker healthchecks and CI/CD smoke tests.

---

## 5. Automated Testing Strategy (Pytest)

### Why Automated Testing is Critical in DevOps:
In Continuous Integration, no code is allowed to reach packaging or deployment unless it passes all automated unit and integration tests. This enforces the **Fail-Fast Principle**: defects are caught within seconds at the testing stage, preventing broken builds from reaching production.

### The 10 Automated Test Cases (`tests/test_app.py`)

```
============================= test session starts =============================
tests/test_app.py::test_get_status_expired PASSED                        [ 10%]
tests/test_app.py::test_get_status_today PASSED                          [ 20%]
tests/test_app.py::test_get_status_3_days PASSED                         [ 30%]
tests/test_app.py::test_get_status_4_days PASSED                         [ 40%]
tests/test_app.py::test_health_endpoint PASSED                           [ 50%]
tests/test_app.py::test_dashboard_renders PASSED                         [ 60%]
tests/test_app.py::test_expiring_page PASSED                             [ 70%]
tests/test_app.py::test_inventory_page PASSED                            [ 80%]
tests/test_app.py::test_add_item_post PASSED                             [ 90%]
tests/test_app.py::test_delete_item PASSED                               [100%]
============================= 10 passed in 0.43s ==============================
```

1. **`test_get_status_expired`**: Asserts past date returns `"expired"`.
2. **`test_get_status_today`**: Asserts today's date returns `"expiring_soon"`.
3. **`test_get_status_3_days`**: Asserts exactly 3 days remaining returns `"expiring_soon"`.
4. **`test_get_status_4_days`**: Asserts 4 days remaining returns `"fresh"`.
5. **`test_health_endpoint`**: Sends HTTP GET to `/health` and validates `200 OK` and JSON response.
6. **`test_dashboard_renders`**: Sends HTTP GET to `/` and validates dashboard HTML elements.
7. **`test_expiring_page`**: Sends HTTP GET to `/expiring` and checks table structure.
8. **`test_inventory_page`**: Sends HTTP GET to `/inventory` and checks inventory listing.
9. **`test_add_item_post`**: Simulates form submission to `/add`, verifies database write and HTTP 302 redirect.
10. **`test_delete_item`**: Inserts an item, calls delete endpoint, and confirms database record deletion.

### Test Isolation with Pytest Fixtures
Tests use a `client` fixture with a temporary SQLite database (`tempfile.mkstemp` or `tmp_path`). Each test runs with a fresh, isolated database that is deleted immediately after the test completes.

---

## 6. Containerization Design (Docker & Gunicorn)

### The Dockerfile Architecture

```dockerfile
FROM python:3.11-slim

# Security: Create non-root user and group
RUN groupadd -r shelflife && useradd -r -g shelflife shelflife

WORKDIR /app

# Layer Caching Optimization: Install requirements before copying app code
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY app/ ./app/

# Create persistent storage directory with proper user ownership
RUN mkdir -p /data && chown shelflife:shelflife /data

# Switch to unprivileged user
USER shelflife

ENV DB_PATH=/data/shelflife.db
ENV PYTHONUNBUFFERED=1

EXPOSE 5000

# Container Healthcheck instruction
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app.app:create_app()"]
```

### Key Engineering Decisions in Dockerfile:
1. **`python:3.11-slim` Base Image**: Reduces image size from ~1 GB (standard Python image) to ~160 MB, dramatically speeding up build and push times.
2. **Layer Caching**: `COPY requirements.txt` and `pip install` happen *before* `COPY app/`. When only Python code changes, Docker reuses cached dependency layers, completing builds in under 5 seconds!
3. **Non-Root User (`shelflife`)**: Prevents container breakout vulnerabilities. If an attacker breaches the web application, they possess zero root privileges on the host system.
4. **Persistent Named Volume (`/data`)**: When containers are replaced during deployments, container filesystems are ephemeral (wiped). Mounting a Docker named volume (`shelflife-data:/data`) ensures database items persist indefinitely across deployments.
5. **Gunicorn WSGI with 2 Workers**: Replaces development server with production-ready concurrent request processing.

---

## 7. Infrastructure as Code (Terraform on AWS)

Instead of manually clicking through the AWS Console, all infrastructure is codified in `terraform/main.tf`:

### Provisioned Cloud Resources:
1. **EC2 Instances (2x `t3.small` on Ubuntu 22.04 LTS)**:
   - `jenkins_server`: Bootstrapped via `user_data_jenkins.sh` (installs Java 21 LTS, Jenkins, Docker, Git, 2GB swap).
   - `app_server`: Bootstrapped via `user_data_app.sh` (installs Docker, configures `/data` volume permissions).
2. **2 Elastic IPs (EIPs)**:
   - Allocates static public IP addresses (`184.73.140.54` and `34.192.143.226`) that do not change when instances are stopped or restarted.
3. **Security Groups (Firewall Rules)**:
   - `shelflife-jenkins-sg`: Allows Inbound Port 22 (SSH) and Port 8080 (Jenkins UI).
   - `shelflife-app-sg`: Allows Inbound Port 22 (SSH), Port 80 (HTTP Web), and Port 5000 (Internal App).
4. **4096-bit RSA TLS Key Pair**:
   - Automatically generated by Terraform (`tls_private_key`) and registered with AWS EC2 (`aws_key_pair`). Private key is exported to `shelflife-key.pem`.
5. **Amazon CloudWatch Alarm**:
   - `shelflife-app-cpu-high`: Triggers if App Server CPU utilization exceeds 70% over two 5-minute evaluation periods.

---

## 8. The Complete CI/CD Pipeline Walkthrough (Jenkinsfile)

The pipeline is written using the **Declarative Pipeline syntax** in `Jenkinsfile`.

### Branching Strategy (`main` vs `dev`)
- **`dev` branch**: Developers push feature branches or PRs here. It runs:
  `Checkout ➔ Install & Test ➔ Docker Build`
  *It purposefully stops before pushing or deploying to avoid polluting the Docker registry or destabilizing production.*
- **`main` branch**: Production branch. It runs the full 6-stage lifecycle:
  `Checkout ➔ Install & Test ➔ Docker Build ➔ Push to Docker Hub ➔ SSH Deploy ➔ Smoke Test`

---

### Step-by-Step Breakdown of All 6 Stages

#### Stage 1: Checkout SCM
```groovy
stage('Checkout') {
    steps {
        checkout scm
    }
}
```
- **What it does**: Clones the exact Git commit that triggered the build using Jenkins' Git SCM plugin.
- **Why it matters**: Ensures builds are 100% deterministic and traceable to an exact Git commit SHA.

#### Stage 2: Install & Test
```groovy
stage('Install & Test') {
    steps {
        sh '''
            python3 -m venv venv
            . venv/bin/activate
            pip install --upgrade pip
            pip install -r requirements.txt
            pytest --junitxml=test-results.xml -v
        '''
    }
}
```
- **What it does**: Spawns an isolated Python virtual environment, installs dependencies, and runs the 10 Pytest test cases.
- **JUnit Parsing**: In the `post { always }` block, `junit 'test-results.xml'` reads the XML output and updates Jenkins' visual test reports. If any test fails, the build halts immediately.

#### Stage 3: Build Docker Image
```groovy
stage('Build Docker Image') {
    steps {
        sh '''
            docker build -t monaagrawal/shelflife:${BUILD_NUMBER} -t monaagrawal/shelflife:latest .
        '''
    }
}
```
- **Dual-Tagging Strategy**:
  - `monaagrawal/shelflife:${BUILD_NUMBER}` (Immutable tag: enables instant rollbacks to any previous build).
  - `monaagrawal/shelflife:latest` (Mutable tag: always points to the most recent passing build).

#### Stage 4: Push to Docker Hub (`when { branch 'main' }`)
```groovy
stage('Push to Docker Hub') {
    when { branch 'main' }
    steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh '''
                echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                docker push monaagrawal/shelflife:${BUILD_NUMBER}
                docker push monaagrawal/shelflife:latest
                docker logout
            '''
        }
    }
}
```
- **DevOps Security Best Practice**: Uses `--password-stdin` so credentials never appear in Linux process trees (`ps aux`) or bash history. `withCredentials` ensures Jenkins masks the password in console logs.

#### Stage 5: Deploy to App Server (`when { branch 'main' }`)
```groovy
stage('Deploy to App Server') {
    when { branch 'main' }
    steps {
        sshagent(['app-server-ssh']) {
            sh '''
                scp -o StrictHostKeyChecking=no scripts/deploy.sh ubuntu@$APP_SERVER_IP:/tmp/deploy.sh
                ssh -o StrictHostKeyChecking=no ubuntu@$APP_SERVER_IP "sed -i 's/\\r$//' /tmp/deploy.sh && chmod +x /tmp/deploy.sh && IMAGE=monaagrawal/shelflife:${BUILD_NUMBER} /tmp/deploy.sh"
            '''
        }
    }
}
```
- **Agent-based SSH Execution**: Uses Jenkins `sshagent` to hold the 4096-bit private key in memory.
- Copies `scripts/deploy.sh` to the remote server, strips Windows carriage returns (`sed -i 's/\r$//'`), and executes the script passing the exact build image tag.

#### Stage 6: Smoke Test (`when { branch 'main' }`)
```groovy
stage('Smoke Test') {
    when { branch 'main' }
    steps {
        sh '''
            echo "Waiting for application to become healthy..."
            for i in $(seq 1 6); do
                if curl -s -f "http://${APP_SERVER_IP}/health" | grep '"status":"ok"'; then
                    echo "Smoke test passed! Application is live."
                    exit 0
                fi
                echo "Attempt $i failed. Retrying in 5 seconds..."
                sleep 5
            done
            echo "Smoke test failed: application is not responding at http://${APP_SERVER_IP}/health"
            exit 1
        '''
    }
}
```
- **Active Verification**: Does not assume deployment succeeded just because Docker started. It actively queries `http://34.192.143.226/health` across 6 retries. If the container crashed or port mapping failed, the pipeline marks the build as **FAILED**.

#### Post Actions (Cleanup & Hygiene)
```groovy
post {
    always {
        junit allowEmptyResults: true, testResults: 'test-results.xml'
        sh 'docker image prune -f || true'
    }
}
```
- Prunes dangling build layers after every run, preventing the Jenkins EC2 disk from filling up.

---

## 9. Deployment Mechanism & Zero-Downtime Script (`deploy.sh`)

The deployment logic on the App Server (`scripts/deploy.sh`) follows this sequence:

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-monaagrawal/shelflife:latest}"
CONTAINER_NAME="shelflife"
DATA_VOLUME="shelflife-data"

echo "==> Pulling fresh image: ${IMAGE}"
docker pull "${IMAGE}"

echo "==> Stopping existing container..."
docker stop "${CONTAINER_NAME}" || true
docker rm -f "${CONTAINER_NAME}" || true

echo "==> Starting updated container..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p 80:5000 \
  -v "${DATA_VOLUME}:/data" \
  --restart unless-stopped \
  "${IMAGE}"

echo "==> Validating container health..."
for i in $(seq 1 6); do
  if docker inspect --format='{{.State.Status}}' "${CONTAINER_NAME}" | grep -q "running"; then
    echo "Container is running."
    exit 0
  fi
  sleep 5
done
```

### Why this design works:
- **Zero Data Loss**: The SQLite database is mounted at `shelflife-data:/data`. Even though the container is deleted and recreated, the volume stays intact.
- **Port Translation**: Maps standard HTTP port 80 on the host to container port 5000 (`-p 80:5000`), allowing users to visit `http://34.192.143.226` without specifying `:5000`.
- **Automatic Recovery**: `--restart unless-stopped` guarantees that if the EC2 instance reboots, Docker automatically restarts the ShelfLife container.

---

## 10. Engineering Challenges Overcome (Real Troubleshooting)

During implementation, real DevOps challenges were diagnosed and resolved:

### 1. Jenkins GPG Repository Key Expiration (March 2026)
- **Problem**: `apt-get update` failed on the Jenkins EC2 instance with `NO_PUBKEY 7198F4B714ABFC68`.
- **Root Cause**: The official Jenkins Debian repository rotated from `jenkins.io-2023.key` to `jenkins.io-2026.key`.
- **Fix**: Updated `user_data_jenkins.sh` to download the new 2026 key directly from `https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key`.

### 2. Jenkins JVM Version Incompatibility
- **Problem**: Jenkins service failed to start (`Supported Java versions are: [21, 25], found 17`).
- **Root Cause**: Modern Jenkins releases (`2.580+`) completely deprecated Java 17 support.
- **Fix**: Configured `openjdk-21-jdk` installation and set default JVM via `update-alternatives`.

### 3. Docker Hub Personal Access Token Scopes
- **Problem**: Jenkins build failed at Docker push with `error: insufficient scopes`.
- **Root Cause**: The Docker Hub PAT was generated with Read-Only permissions.
- **Fix**: Generated a new PAT with **Read & Write** permissions at `hub.docker.com/settings/security` and updated the `dockerhub-creds` credential in Jenkins.

### 4. Windows CRLF vs. Linux LF Line Endings
- **Problem**: Remote execution of `deploy.sh` on EC2 failed with `/bin/bash^M: bad interpreter`.
- **Root Cause**: Git on Windows converted script line endings to CRLF.
- **Fix**: Added `.gitattributes` (`* text eol=lf`) to enforce LF line endings, and added `sed -i 's/\r$//' /tmp/deploy.sh` in the pipeline before execution.

### 5. Windows OpenSSH Key File Permissions
- **Problem**: SSH commands failed with `UNPROTECTED PRIVATE KEY FILE! Permissions are too open`.
- **Root Cause**: Windows NTFS permissions granted read access to other accounts.
- **Fix**: Stripped inherited permissions with `icacls shelflife-key.pem /inheritance:r` and granted read only to the active user `icacls shelflife-key.pem /grant:r "$($env:USERNAME):(R)"`.

---

## 11. Top 15 Viva & Interview Questions with Model Answers

#### Q1: What is the core problem ShelfLife solves?
> **Answer**: At the application level, it reduces household food waste by giving visibility into pantry inventory and highlighting expiring items. At the engineering level, it solves manual deployment risks by implementing an automated CI/CD pipeline from Git push to cloud deployment.

#### Q2: Why did you choose Jenkins over GitHub Actions?
> **Answer**: Jenkins is the industry benchmark for self-hosted CI/CD orchestration. It gives complete control over the build environment, private networking inside AWS VPCs, custom credential management, and hands-on experience configuring Jenkins agents, Docker daemons, and plugins.

#### Q3: Why did you choose SQLite over PostgreSQL/MySQL?
> **Answer**: For a single-instance containerized application, SQLite requires zero configuration and zero external dependencies. The database resides on a Docker named volume (`/data`). If high concurrent write throughput or horizontal clustering were required, we would migrate to Amazon RDS PostgreSQL.

#### Q4: Why do you tag Docker images with both `:BUILD_NUMBER` and `:latest`?
> **Answer**: Dual-tagging is a DevOps best practice. `:BUILD_NUMBER` provides an immutable, auditable artifact tied to a specific build, enabling instant rollbacks. `:latest` provides a convenient floating pointer for automated deployment scripts.

#### Q5: What happens if a Pytest test fails in the pipeline?
> **Answer**: The pipeline immediately halts at Stage 2 (Install & Test). Jenkins marks the build as RED/FAILED and does not proceed to Docker Build, Push, or Deploy. This prevents broken code from reaching Docker Hub or production.

#### Q6: How does the pipeline ensure database data is not lost when redeploying?
> **Answer**: Container storage is ephemeral, but persistent storage is decoupled using a Docker Named Volume (`shelflife-data:/data`). When `deploy.sh` stops and removes the old container, the volume remains on the host and is reattached to the new container.

#### Q7: What is the purpose of the Smoke Test stage?
> **Answer**: A container can start successfully according to Docker but crash internally (e.g., missing environment variable, database lock, or internal 500 error). The smoke test actively curls `http://<app-ip>/health` to confirm the web server is responding with `HTTP 200` before concluding the build.

#### Q8: What is the difference between the `dev` and `main` branches?
> **Answer**: `dev` runs continuous integration only (checkout, testing, local Docker build) to validate pull requests. `main` runs full continuous delivery (pushes to Docker Hub, deploys to EC2, and runs smoke tests).

#### Q9: How are secrets and passwords protected in your pipeline?
> **Answer**: No credentials or private keys are ever committed to Git. Docker credentials and SSH private keys are stored in the encrypted Jenkins Credentials Store and bound at runtime using `withCredentials` and `sshagent`. Passwords are submitted via `--password-stdin` and automatically masked with `****` in build logs.

#### Q10: Why did you use Terraform instead of creating EC2 instances in the AWS Console?
> **Answer**: Terraform provides Infrastructure as Code (IaC). It makes infrastructure reproducible, auditable, and version-controlled. It eliminates human error, allows rapid spin-up and teardown in under 3 minutes, and prevents configuration drift.

#### Q11: What is an Elastic IP and why is it used?
> **Answer**: Standard AWS public IP addresses change every time an EC2 instance stops or restarts. Elastic IPs provide static, permanent IP addresses, ensuring that Jenkins webhook URLs, SSH connections, and web links never break.

#### Q12: Why run Gunicorn instead of `python app/app.py` in production?
> **Answer**: Flask's built-in development server is single-threaded and not designed for production security or performance. Gunicorn is a battle-tested WSGI HTTP server that forks multiple worker processes to handle concurrent requests efficiently.

#### Q13: Why did you run the container as a non-root user (`USER shelflife`)?
> **Answer**: Following the Principle of Least Privilege: if an application vulnerability (like Remote Code Execution) is exploited, the attacker only has unprivileged container access and cannot alter host system files or escape the container.

#### Q14: How does GitHub notify Jenkins of a new commit?
> **Answer**: Via a GitHub Webhook configured at `http://<jenkins-ip>:8080/github-webhook/`. When code is pushed, GitHub sends an HTTP POST event with JSON metadata, prompting Jenkins to trigger the corresponding branch build immediately.

#### Q15: How does AWS CloudWatch fit into this architecture?
> **Answer**: CloudWatch provides observability. An alarm (`shelflife-app-cpu-high`) monitors CPU utilization on the application EC2 instance and triggers an alarm state if CPU exceeds 70% for two consecutive 5-minute periods, signaling potential traffic spikes or runaway processes.

---

## 12. Step-by-Step Live Demonstration Script

When presenting to evaluators, use this seamless 5-minute walkthrough:

1. **Show the Web Application (30 seconds)**:
   - Open `http://34.192.143.226` (or `http://localhost:5000`).
   - Add an item (e.g., *"Fresh Milk"*, Category: *Dairy*, Expiry: *Tomorrow*).
   - Show it appearing under **Expiring Soon** in orange/red.
   - Show the `/health` endpoint returning `{"status":"ok"}`.

2. **Show the GitHub Repository & Code Structure (1 minute)**:
   - Point out clean repository organization: `app/`, `tests/`, `terraform/`, `scripts/`, `Dockerfile`, and `Jenkinsfile`.
   - Show `tests/test_app.py` with 10 unit/integration tests.

3. **Show Infrastructure as Code (1 minute)**:
   - Show `terraform/main.tf` and explain how 2 EC2 instances, Security Groups, EIPs, and CloudWatch alarms were provisioned automatically.

4. **Show Jenkins CI/CD Pipeline (2 minutes)**:
   - Open `http://184.73.140.54:8080`.
   - Open `ShelfLife` Multibranch Pipeline.
   - Show the 6 green stages in the Stage View.
   - Click **Test Result** and show the **10 / 10 Passing JUnit tests**.
   - Click **Console Output** on the latest build to show credential masking, Docker Hub push, SSH deployment, and smoke test passing.

5. **Show Docker Hub Registry (30 seconds)**:
   - Open `https://hub.docker.com/r/monaagrawal/shelflife`.
   - Show the pushed images tagged with build numbers and `latest`.

---
*Created for ShelfLife DevOps Project Presentation & Academic Submission.*
