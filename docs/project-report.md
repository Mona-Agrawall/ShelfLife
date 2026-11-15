# ShelfLife: A Cloud-Deployed Pantry Expiry Tracker with Automated CI/CD Pipeline

**Course**: DevOps Engineering  
**Submission Type**: Project Report  

---

## Abstract

Food waste is a significant household problem, often caused by a simple lack of visibility into what is in the pantry and when it expires. ShelfLife is a cloud-deployed web application that addresses this by allowing users to log pantry items, track their expiry dates, and receive at-a-glance warnings about items that are expiring soon or have already expired. Built with Flask and SQLite, the app is containerized with Docker and deployed to AWS EC2.

However, the application itself is not the primary focus of this project. The central deliverable is a fully automated CI/CD pipeline built with Jenkins, Terraform, and Docker. Every code push to the main branch triggers an automated sequence: unit tests are run, a Docker image is built and pushed to Docker Hub, and the latest version is deployed to a live server — all without manual intervention. This project demonstrates a complete, real-world DevOps workflow from local development to cloud production.

---

## 1. Problem Statement

Households routinely discard food that has passed its expiry date, often simply because there was no easy way to track what was in the pantry and when it would expire. Manual methods — such as checking every item by hand or maintaining a spreadsheet — are error-prone, time-consuming, and rarely kept up to date. The result is unnecessary food waste and unnecessary spending.

Beyond the application-level problem, software development teams face an analogous challenge: manually deploying application updates is slow, inconsistent, and error-prone. Without automation, every deployment is a potential source of human error — a file not copied, a service not restarted, or a dependency version mismatch.

ShelfLife addresses both problems simultaneously: it provides a simple, effective tool for tracking pantry expiry dates, and it is delivered through a fully automated CI/CD pipeline that eliminates manual deployment steps. The pipeline ensures that every change is automatically tested before it reaches production and deployed consistently every time.

---

## 2. Objectives

1. **Build a functional Flask web application** that allows users to add, view, and delete pantry items with expiry dates, and categorize items by status (expired, expiring soon, fresh).
2. **Write a comprehensive automated test suite** (minimum 10 pytest tests) covering business logic, HTTP routes, and database operations, achieving 100% pass rate.
3. **Containerize the application** using Docker with a production-safe configuration (non-root user, persistent volume for the database).
4. **Provision AWS infrastructure as code** using Terraform: two EC2 instances (Jenkins server and app server), security groups, Elastic IPs, and a CloudWatch CPU alarm.
5. **Implement a fully automated CI/CD pipeline** using Jenkins that runs tests, builds and pushes Docker images, and deploys to the app server on every push to `main`, with branch-aware behavior (no deployment on feature branches).
6. **Demonstrate the pipeline end-to-end** by pushing a code change and verifying the update appears live at the app server's public IP address.

---

## 3. Tools and Technologies

### Flask
**What it is**: Flask is a lightweight, micro web framework for Python. It provides routing, templating (via Jinja2), request handling, and a development server with minimal boilerplate.

**Why chosen**: Flask is ideal for small-to-medium web applications where the developer wants full control over the stack without the overhead of a full framework like Django. For a learning project, Flask's simplicity makes the application code easy to read and understand. Its built-in test client also makes writing automated tests straightforward.

---

### SQLite
**What it is**: SQLite is a self-contained, serverless, file-based relational database engine included in Python's standard library (`sqlite3` module).

**Why chosen**: For a single-container application without concurrent write requirements, SQLite requires zero configuration and no separate database process. This simplifies both local development and Docker deployment (the database is just a file on a Docker volume). It is a deliberate pedagogical choice to keep the infrastructure simple and focus attention on the CI/CD pipeline.

---

### Docker
**What it is**: Docker is a platform for packaging applications and their dependencies into portable containers. A `Dockerfile` defines the image; `docker compose` orchestrates multi-container local environments.

**Why chosen**: Docker ensures the application runs identically in every environment — a developer's Windows laptop, the Jenkins build server, and the AWS app server. It eliminates "works on my machine" problems and makes deployment a matter of pulling and running an image rather than manually installing dependencies.

---

### Jenkins
**What it is**: Jenkins is an open-source automation server written in Java. It orchestrates CI/CD pipelines defined as code in a `Jenkinsfile` (using the declarative Pipeline DSL).

**Why chosen**: Jenkins is the most widely deployed open-source CI/CD tool in the industry. Its `Jenkinsfile`-based Pipeline as Code approach means the pipeline definition lives alongside the application code in version control. Jenkins supports GitHub webhooks for event-driven triggers and has a rich plugin ecosystem (SSH Agent, Docker Pipeline, JUnit, etc.).

---

### Terraform
**What it is**: Terraform is an open-source Infrastructure as Code (IaC) tool by HashiCorp. It uses a declarative HCL language to define cloud resources and manages their lifecycle (create, update, destroy).

**Why chosen**: Provisioning infrastructure manually through the AWS console is not repeatable. Terraform allows the entire two-server AWS environment to be defined in code, version-controlled, and reproduced with a single `terraform apply` command. It also makes cleanup trivial with `terraform destroy`.

---

### AWS EC2
**What it is**: Amazon Elastic Compute Cloud (EC2) provides resizable virtual machine instances in the AWS cloud.

**Why chosen**: EC2 instances provide the compute substrate for both the Jenkins CI/CD server and the app server. t3.small instances offer sufficient RAM (2 GB) for Jenkins and Docker operations while remaining within a manageable cost range (and within AWS Academy lab budgets).

---

### AWS CloudWatch
**What it is**: Amazon CloudWatch is AWS's native monitoring and observability service. It collects metrics, logs, and events from AWS resources and applications.

**Why chosen**: CloudWatch is integrated with EC2 at no additional cost for standard metrics like CPU utilization. A CloudWatch alarm is configured as part of the Terraform infrastructure to alert when the app server's CPU exceeds 80% — demonstrating a basic production monitoring pattern without requiring any additional tooling.

---

### Git / GitHub
**What it is**: Git is a distributed version control system; GitHub is a cloud-hosted Git repository platform with features for collaboration, webhooks, and CI/CD integration.

**Why chosen**: Git is the industry standard for version control. GitHub's webhook support is the trigger mechanism for the Jenkins pipeline — every `git push` automatically fires the pipeline without any manual intervention. The project also demonstrates branch-based pipeline behavior: feature branches trigger only tests, while `main` triggers the full deploy.

---

## 4. Architecture

The full architectural diagram and component descriptions are detailed in [`docs/architecture.md`](architecture.md). The following is a summary.

The system uses a **two-server AWS architecture**:

- **Jenkins Server (EC2 t3.small)**: Hosts the Jenkins CI/CD orchestrator. It receives GitHub webhooks, runs the pipeline stages, and SSH-deploys to the app server. It is provisioned automatically by Terraform.
- **App Server (EC2 t3.small)**: Runs the ShelfLife Docker container on port 80. It receives deployments from Jenkins by pulling the latest image from Docker Hub and restarting the container. A CloudWatch CPU alarm monitors this instance.

Both servers are provisioned in the same AWS region and VPC, with security groups restricting access to only the necessary ports (22, 80, 8080). Infrastructure is defined entirely in the `terraform/` directory and can be reproduced or destroyed with a single command.

---

## 5. Implementation Steps

### Step 1: Flask Application Development
The application was built using the Flask app factory pattern (`create_app(db_path=None)`), which allows the database path to be injected — critical for testing. The app uses Python's built-in `sqlite3` module to interact with a SQLite database, creating the `items` table automatically on startup if it does not exist.

Five routes were implemented:
- `GET /` — Dashboard with item counts by status
- `GET /add`, `POST /add` — Item creation form with validation
- `GET /expiring` — Items expiring within 3 days or already expired
- `GET /inventory`, `POST /inventory/delete/<id>` — Full inventory with delete
- `GET /health` — JSON health check endpoint

A pure helper function `get_status(expiry_date, today=None)` computes item status without side effects, making it trivially unit-testable.

### Step 2: Writing Tests
Ten pytest tests were written in `tests/test_app.py`, covering:
- `get_status()` logic for all three status values
- HTTP route responses (200 OK, 302 redirect on successful form POST)
- Database read/write operations via the test client
- The `/health` JSON endpoint

Tests use `pytest` fixtures (`app`, `client`) with a temporary SQLite file so tests are fully isolated and leave no state behind.

### Step 3: Dockerization
A multi-stage-aware `Dockerfile` was written that:
1. Starts from `python:3.11-slim`
2. Creates a non-root `appuser` for security
3. Copies `requirements.txt` and installs dependencies
4. Copies application code
5. Creates the `/data` directory for the SQLite volume
6. Exposes port 5000 and sets the `gunicorn` entrypoint

A `docker-compose.yml` was written for local development, mapping port 5000 and mounting `./data:/data` for database persistence.

### Step 4: Terraform Infrastructure as Code
The `terraform/` directory defines:
- `main.tf`: EC2 instances, security groups, Elastic IPs, key pair
- `cloudwatch.tf`: CPU alarm for the app server
- `variables.tf`: Configurable inputs (region, instance type, key name)
- `outputs.tf`: Outputs for Jenkins URL, app URL, and SSH commands
- `terraform.tfvars.example`: Safe template for user-specific values

### Step 5: Jenkins Pipeline Setup
A declarative `Jenkinsfile` was written with six stages: Checkout, Install & Test, Build, Push, Deploy, and Smoke Test. The Push, Deploy, and Smoke Test stages are gated with `when { branch 'main' }` so feature branch pushes only run tests and builds.

Jenkins was configured with:
- `dockerhub-creds` credential for Docker Hub push authentication
- `app-server-ssh` credential for SSH deployment to the app server
- A Multibranch Pipeline job pointing at the GitHub repository
- A GitHub webhook for event-driven triggering

### Step 6: AWS Deployment
1. AWS credentials were configured (`~/.aws/credentials`).
2. `terraform init && terraform apply` provisioned both EC2 instances.
3. Jenkins was set up via its web UI (initial admin password, plugins, credentials).
4. The first pipeline run was triggered manually; subsequent runs fire automatically on push.
5. The app was verified live at `http://<app-ip>` and the `/health` endpoint confirmed a 200 response.

---

## 6. Pipeline Stages Explained

### Stage 1: Checkout
Jenkins checks out the repository at the specific commit SHA that triggered the pipeline. This ensures the build is always reproducible and tied to an exact version of the code. Git metadata (specifically the short commit SHA) is captured for use as the Docker image tag.

### Stage 2: Install & Test
Jenkins creates a Python virtual environment inside the workspace, installs all dependencies from `requirements.txt`, and runs `pytest`. The test results are written to `test-results.xml` in JUnit XML format, which Jenkins parses and displays as a visual test report (pass/fail counts, test names, failure details). If any test fails, the pipeline aborts immediately and marks the build as failed — no broken code proceeds to build.

### Stage 3: Build
Jenkins runs `docker build`, producing an image tagged with both the Git commit SHA (e.g., `username/shelflife:a1b2c3d`) and `latest`. Using the commit SHA tag ensures every image is traceable back to its source commit, while `latest` provides a convenient alias for deployment.

### Stage 4: Push *(main branch only)*
Jenkins authenticates to Docker Hub using the `dockerhub-creds` credential and pushes both tags. This stage only runs on the `main` branch — feature branch builds produce a local image for validation but do not pollute the registry.

### Stage 5: Deploy *(main branch only)*
Jenkins uses the `app-server-ssh` SSH credential to connect to the app server and run a deployment script. The script:
1. Pulls the new image from Docker Hub
2. Stops and removes the existing `shelflife` container
3. Starts a new container from the fresh image, binding port 80 and mounting the data volume

This "stop-remove-start" approach is intentionally simple. For zero-downtime deployment, a rolling update strategy or container orchestrator (ECS, Kubernetes) would be used.

### Stage 6: Smoke Test *(main branch only)*
Jenkins sends an HTTP GET request to `http://<app-ip>/health` from the Jenkins server and asserts the response is `{"status": "ok"}` with HTTP 200. This provides basic confirmation that the new container started successfully and the app is accepting traffic. If the smoke test fails (e.g., the container crashed on startup), the build is marked as failed and the team is alerted.

---

## 7. Results

All project objectives were met:

- **Flask application**: A fully functional five-route Flask app was built, with correct expiry status logic, form validation, and a health endpoint.
- **Test suite**: All 10 automated tests pass consistently. The JUnit XML report is published in Jenkins for every build.
- **Docker**: The app runs correctly in a container on both local (`docker compose up`) and the AWS app server.
- **Terraform**: Both EC2 instances, security groups, Elastic IPs, and the CloudWatch alarm were provisioned successfully in under 3 minutes with `terraform apply`.
- **Jenkins pipeline**: The pipeline runs end-to-end automatically on every push to `main`. Feature branch pushes correctly skip the Push and Deploy stages.
- **Live deployment**: After merging a code change to `main` and pushing, the updated application was visible at `http://<app-ip>` within approximately 90 seconds of the push — without any manual intervention.
- **Health endpoint**: `curl http://<app-ip>/health` returns `{"status": "ok"}` with HTTP 200, confirming the application is healthy.

---

## 8. Screenshots to Take

Replace each placeholder below with an actual screenshot before submission.

- [ ] **Screenshot 1**: ShelfLife Dashboard running in browser (`http://<app-ip>`) — shows the three stat cards (Expired / Expiring Soon / Fresh) and category breakdown.
- [ ] **Screenshot 2**: Add Item form (`http://<app-ip>/add`) — shows the input fields for name, category dropdown, quantity, and expiry date.
- [ ] **Screenshot 3**: Inventory page (`http://<app-ip>/inventory`) — shows a table of items color-coded by status with Delete buttons.
- [ ] **Screenshot 4**: Expiring items page (`http://<app-ip>/expiring`) — shows items expiring within 3 days highlighted in orange/red.
- [ ] **Screenshot 5**: Jenkins pipeline view — the Blue Ocean or classic stage view showing all pipeline stages with green checkmarks.
- [ ] **Screenshot 6**: Jenkins Test Results — the JUnit test report showing all 10 tests passing with pass counts and test names.
- [ ] **Screenshot 7**: Docker Hub — your repository page showing the pushed image with both the commit-SHA tag and the `latest` tag.
- [ ] **Screenshot 8**: Terraform apply output — terminal output showing the resources created and the final `Apply complete! Resources: X added` summary.
- [ ] **Screenshot 9**: AWS EC2 console — the Instances list showing both `shelflife-jenkins` and `shelflife-app` instances in the **Running** state.
- [ ] **Screenshot 10**: CloudWatch CPU alarm — the AWS CloudWatch console showing the `shelflife-app-cpu-alarm` alarm in an OK state.

---

## 9. Conclusion

This project successfully demonstrates a complete DevOps workflow applied to a real-world application. ShelfLife solves the practical problem of pantry expiry tracking while serving as the vehicle for a production-style CI/CD pipeline. By combining Flask, Docker, Jenkins, Terraform, and AWS, the project covers the full lifecycle of a cloud application: development, testing, containerization, infrastructure provisioning, automated deployment, and monitoring. The pipeline ensures that any code change is automatically validated before it reaches production, reducing the risk of regressions and eliminating manual deployment overhead. The result is a reproducible, infrastructure-as-code-driven system that can be spun up from scratch and torn down with single commands — a key capability for modern cloud-native software engineering.

---

## 10. Future Scope

1. **Email / push notifications**: Integrate an email service (AWS SES or SendGrid) or a mobile push service to alert users when items are within 1 day of expiry, so they don't need to actively check the dashboard.

2. **Mobile application**: Build a React Native or Flutter companion app that wraps the existing Flask API, allowing users to scan barcodes or QR codes to add items and check expiry status on their phone.

3. **Multi-user authentication**: Add user accounts with Flask-Login or Auth0 integration, so multiple household members or family units can maintain separate inventories without data crossover.

4. **PostgreSQL / managed database**: Replace SQLite with Amazon RDS (PostgreSQL) to support horizontal scaling of the app tier, concurrent writes, and proper backup/recovery. Update Terraform to provision the RDS instance.

5. **Kubernetes deployment (EKS)**: Migrate the Docker deployment from a single EC2 instance to an Amazon EKS cluster, using a Helm chart to manage the ShelfLife deployment. Update the Jenkins pipeline to use `helm upgrade --install` in the Deploy stage, enabling rolling updates, replica management, and auto-scaling.
