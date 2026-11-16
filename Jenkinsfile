// Jenkinsfile — Declarative Pipeline for the ShelfLife project
//
// NOTES:
//   - This pipeline is designed for a Multibranch Pipeline job in Jenkins.
//   - dev branch  : runs Checkout, Install & Test, Build Docker Image only.
//   - main branch : runs all stages including Push, Deploy, and Smoke Test.
//   - Simpler alternative: create a regular Pipeline job pointed at main branch
//     and remove the `when { branch 'main' }` conditions.
//
// REQUIRED JENKINS CREDENTIALS:
//   - dockerhub-creds  : Username/Password credential for Docker Hub
//   - app-server-ssh   : SSH private key credential for the app server

pipeline {
    agent any

    environment {
        // Docker Hub username
        DOCKERHUB_USER = 'monaagrawal'
        IMAGE_NAME = 'shelflife'
        // Full image name with registry
        IMAGE_FULL = "${DOCKERHUB_USER}/${IMAGE_NAME}"
    }

    parameters {
        // The app server IP - can also be set as a Jenkins environment variable
        string(name: 'APP_SERVER_IP', defaultValue: '34.192.143.226', description: 'App server public IP (from Terraform output)')
    }

    stages {
        stage('Checkout') {
            steps {
                // Source code is checked out automatically in a pipeline job
                echo "Checking out branch: ${env.BRANCH_NAME ?: 'main'}"
                sh 'git log -1 --oneline || echo "Git info unavailable"'
            }
        }

        stage('Install & Test') {
            steps {
                // Create virtual environment and install dependencies
                sh '''
                    python3 -m venv venv
                    ./venv/bin/pip install --upgrade pip
                    ./venv/bin/pip install -r requirements.txt
                '''
                // Run pytest with JUnit XML output for Jenkins to parse
                sh './venv/bin/pytest --junitxml=test-results.xml -v'
            }
            post {
                always {
                    // Publish test results regardless of pass/fail
                    junit 'test-results.xml'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                // Build and tag with build number and 'latest'
                sh "docker build -t ${IMAGE_FULL}:${BUILD_NUMBER} -t ${IMAGE_FULL}:latest ."
            }
        }

        stage('Push to Docker Hub') {
            // Only push on main branch
            when { branch 'main' }
            steps {
                // Use stored Docker Hub credentials (ID: dockerhub-creds)
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                    sh "docker push ${IMAGE_FULL}:${BUILD_NUMBER}"
                    sh "docker push ${IMAGE_FULL}:latest"
                }
            }
        }

        stage('Deploy to App Server') {
            // Only deploy on main branch
            when { branch 'main' }
            steps {
                script {
                    env.TARGET_IP = (params.APP_SERVER_IP && params.APP_SERVER_IP.trim()) ? params.APP_SERVER_IP.trim() : '34.192.143.226'
                }
                // Use SSH agent with stored private key (credential ID: app-server-ssh)
                sshagent(['app-server-ssh']) {
                    sh """
                        # Copy deploy script to app server
                        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null scripts/deploy.sh ubuntu@${env.TARGET_IP}:/tmp/deploy.sh
                        
                        # Strip CRLF, make executable, and execute deployment
                        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@${env.TARGET_IP} \\
                            "sed -i 's/\\r\$//' /tmp/deploy.sh && chmod +x /tmp/deploy.sh && IMAGE=${IMAGE_FULL}:${BUILD_NUMBER} /tmp/deploy.sh"
                    """
                }
            }
        }

        stage('Smoke Test') {
            // Only smoke test on main branch after deploy
            when { branch 'main' }
            steps {
                script {
                    env.TARGET_IP = (params.APP_SERVER_IP && params.APP_SERVER_IP.trim()) ? params.APP_SERVER_IP.trim() : '34.192.143.226'
                }
                // Wait a moment for the container to fully initialize
                sh 'sleep 3'
                // Curl the health endpoint on the app server with retries; fail build if not 200
                sh """
                    echo "Testing /health endpoint on http://${env.TARGET_IP} ..."
                    STATUS=false
                    for i in 1 2 3 4 5 6; do
                        HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" http://${env.TARGET_IP}/health || true)
                        if [ "\$HTTP_CODE" = "200" ]; then
                            echo "Smoke test PASSED: /health returned 200 (attempt \$i)"
                            STATUS=true
                            break
                        fi
                        echo "Attempt \$i: /health returned HTTP \$HTTP_CODE, retrying in 5s..."
                        sleep 5
                    done
                    if [ "\$STATUS" != "true" ]; then
                        echo "Smoke test FAILED: /health did not return 200 after 6 attempts"
                        exit 1
                    fi
                """
            }
        }
    }

    post {
        success {
            echo "Pipeline SUCCEEDED! Build #${BUILD_NUMBER} deployed successfully."
            echo "App URL: http://${params.APP_SERVER_IP ?: '34.192.143.226'}"
        }
        failure {
            echo "Pipeline FAILED on build #${BUILD_NUMBER}. Check the logs above."
        }
        always {
            // Clean up dangling Docker images to save disk space
            sh 'docker image prune -f || true'
        }
    }
}
