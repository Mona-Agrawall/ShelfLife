# ShelfLife — Pantry & Expiry Tracker with CI/CD Pipeline

ShelfLife is a lightweight Flask web application that helps you track pantry items and their expiry dates — so you always know what's fresh, what's expiring soon, and what's already gone off. The **primary deliverable of this project is not just the app itself, but a complete, production-style CI/CD pipeline** that automatically tests, builds, and deploys the application to AWS whenever code is pushed to the main branch.

---

## Architecture Diagram

```
┌─────────────┐    Push     ┌─────────────┐
│  Developer  │────────────▶│   GitHub    │
│  (Local)    │             │   (Repo)    │
└─────────────┘             └──────┬──────┘
                                   │ Webhook
                                   ▼
┌──────────────────────────────────────────┐
│           Jenkins Server (EC2)            │
│  ┌────────┐ ┌──────┐ ┌──────┐ ┌───────┐ │
│  │Checkout│▶│ Test │▶│Build │▶│ Push  │ │
│  └────────┘ └──────┘ └──────┘ └───┬───┘ │
└──────────────────────────────────│──────┘
                                   │ Docker Hub
                              ┌────▼─────┐
                              │ App Server│
                              │  (EC2)   │
                              │ Docker   │
                              │Container │
                              └──────────┘
```

---

## Tech Stack

| Tool | Usage in this project |
|------|----------------------|
| AWS EC2 | Hosts Jenkins and the app server |
| AWS CloudWatch | CPU monitoring and log aggregation |
| Git | Version control, branch-based pipeline triggers |
| Jenkins | CI/CD orchestration, automated test/build/deploy |
| Docker | Containerizes the Flask app, ensures consistency |
| Docker Hub | Container image registry |
| Terraform | Infrastructure as Code — provisions all AWS resources |
| Flask | Lightweight Python web framework for the app |
| SQLite | Simple file-based database for local/container use |

---

## How to Run Locally (without Docker)

```bash
cd DevOps
python -m venv venv
venv\Scripts\activate      # Windows
# source venv/bin/activate # Linux/Mac
pip install -r requirements.txt
set DB_PATH=data/shelflife.db  # Windows
# export DB_PATH=data/shelflife.db  # Linux/Mac
python -c "from app.app import create_app; create_app().run(debug=True)"
# Visit http://localhost:5000
```

---

## How to Run with Docker

```bash
docker compose up --build
# Visit http://localhost:5000
docker compose down
```

---

## How to Run Tests

```bash
python -m venv venv
venv\Scripts\pip install -r requirements.txt
venv\Scripts\pytest
# or
pytest -v
```

---

## Full Deployment Guide

### 7a. AWS Credentials Setup

**AWS Academy (Vocareum):**
1. Log in to your AWS Academy Learner Lab via Vocareum.
2. Click **AWS Details** → **Show** next to "AWS CLI".
3. Copy the credentials block (`aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`).
4. Paste them into `~/.aws/credentials` (create the file if it doesn't exist):
   ```ini
   [default]
   aws_access_key_id = ASIA...
   aws_secret_access_key = ...
   aws_session_token = ...
   ```
5. ⚠️ **Session tokens expire every 4 hours.** Repeat this process if Terraform commands start returning auth errors.
6. The lab provides a pre-created **LabInstanceProfile** IAM role — use this for EC2 instance profiles instead of creating your own.

**Personal Free Tier:**
1. Go to IAM → Users → Create user with programmatic access.
2. Attach policies: `AmazonEC2FullAccess`, `CloudWatchFullAccess`.
3. Download the access key and secret.
4. Run `aws configure` and enter the access key, secret, and your preferred region.

---

### 7b. Terraform: Deploy Infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings:
#   - aws_region
#   - key_name (your EC2 key pair name)
#   - dockerhub_user
terraform init
terraform plan
terraform apply
# Note the outputs: jenkins_url, app_url, SSH commands
```

Terraform will provision:
- Two EC2 instances (Jenkins server + App server)
- Security groups for HTTP, SSH, and Jenkins port 8080
- An Elastic IP for each server
- A CloudWatch CPU alarm on the app server

---

### 7c. Jenkins Initial Setup

1. SSH into the Jenkins server:
   ```bash
   ssh -i shelflife-key.pem ubuntu@<jenkins-ip>
   ```
2. Wait for Jenkins to start (can take 3–5 minutes):
   ```bash
   sudo systemctl status jenkins
   ```
3. Get the initial admin password:
   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
4. Open Jenkins at `http://<jenkins-ip>:8080` in your browser.
5. Enter the initial admin password.
6. Choose **Install suggested plugins**, then also install:
   - **SSH Agent Plugin**
   - **Pipeline** (usually included)
7. Create your admin user when prompted.

---

### 7d. Jenkins Credentials & Job Setup

**Add Docker Hub credentials:**
1. Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credential
2. Kind: **Username with password**
3. ID: `dockerhub-creds`
4. Username: your Docker Hub username
5. Password: your Docker Hub **access token** (not your login password — generate one at hub.docker.com → Account Settings → Security)

**Add app server SSH key:**
1. Add another credential
2. Kind: **SSH Username with private key**
3. ID: `app-server-ssh`
4. Username: `ubuntu`
5. Private key: paste the full contents of `shelflife-key.pem`

**Create the pipeline job:**
1. Jenkins → New Item → **Multibranch Pipeline** → name it `shelflife`
2. Branch Sources → Add source → **GitHub**
3. Enter your repository URL
4. Set credentials if the repo is private
5. Save and let Jenkins scan branches

**Add GitHub webhook:**
1. GitHub repo → Settings → Webhooks → Add webhook
2. Payload URL: `http://<jenkins-ip>:8080/github-webhook/`
3. Content type: `application/json`
4. Trigger: **Just the push event**

**Update Jenkinsfile:**
- Open `Jenkinsfile` and replace `your-dockerhub-username` in the `DOCKERHUB_USER` environment variable with your actual Docker Hub username.

---

### 7e. Demo Flow

1. Create a dev branch:
   ```bash
   git checkout -b dev
   ```
2. Make a small change (e.g., update a template heading).
3. Push the branch:
   ```bash
   git push origin dev
   ```
   → Jenkins detects the push via webhook and runs **Test + Build** stages only (no deploy on non-main branches).

4. Merge to main and push:
   ```bash
   git checkout main
   git merge dev
   git push origin main
   ```
   → Jenkins runs the **full pipeline** (Checkout → Test → Build → Push → Deploy → Smoke Test) and deploys the updated container to the app server.

5. Visit `http://<app-ip>` to confirm the update is live.

---

### 7f. Cleanup

```bash
cd terraform
terraform destroy
```

> [!CAUTION]
> `terraform destroy` permanently deletes ALL provisioned AWS resources including EC2 instances, security groups, and Elastic IPs. Ensure you have no data or logs you need to preserve before running this. AWS Academy environments auto-expire, but personal AWS accounts will continue to accrue charges if resources are left running.

---

### 7g. Troubleshooting

1. **Jenkins out of memory / OOM killed**
   Jenkins requires at least 512 MB RAM; a t2.micro may OOM under load. Add swap space:
   ```bash
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```
   Prefer **t3.small** over t2.micro for Jenkins.

2. **docker: permission denied**
   The `jenkins` user must be in the `docker` group:
   ```bash
   sudo usermod -aG docker jenkins
   sudo systemctl restart jenkins
   ```
   Log out and back in for group changes to take effect.

3. **AWS Academy credentials expired**
   Session tokens expire every 4 hours. Go to Vocareum → AWS Details → copy the new credentials block → paste into `~/.aws/credentials`. Then re-run `terraform apply`.

4. **Changed IPs after rebuild**
   Elastic IPs are attached so IPs shouldn't change between reboots. If you've destroyed and re-applied, run:
   ```bash
   terraform output
   ```
   Update `APP_SERVER_IP` in your Jenkins job parameter with the new value.

5. **Webhook not firing**
   Check GitHub → repo Settings → Webhooks — look for a red ✗ next to your webhook. Common causes:
   - Jenkins not reachable on port 8080 (check EC2 security group inbound rules)
   - Wrong webhook URL
   
   Test manually:
   ```bash
   curl -X POST http://<jenkins-ip>:8080/github-webhook/
   ```

6. **Pipeline fails: "Cannot connect to Docker daemon"**
   The Jenkins service must be restarted after adding jenkins to the docker group:
   ```bash
   sudo systemctl restart jenkins
   ```

7. **Terraform: "Error: No valid credential sources found"**
   AWS credentials are not configured. Run `aws configure` or manually populate `~/.aws/credentials`. For AWS Academy, recopy credentials from Vocareum.

8. **App container not starting on app server**
   SSH to the app server and inspect Docker logs:
   ```bash
   docker logs shelflife
   ```
   Common causes: Docker image not pulled yet, port 80 already in use by another process, or `/data` volume permission issues.

9. **SSH timeout connecting to EC2**
   - Confirm EC2 security group allows inbound TCP on port 22 from your current IP address.
   - Wait 2–3 minutes after `terraform apply` for instances to fully initialize before attempting SSH.

10. **pytest: ModuleNotFoundError for app**
    Ensure you run pytest from the **project root** (`DevOps/`) directory, not from inside `app/` or `tests/`. Confirm `pytest.ini` contains `testpaths = tests` and `pythonpath = .`. Alternatively, add a `conftest.py` at the project root that appends the project root to `sys.path`.
