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
        // Docker Hub username - set this to your Docker Hub username
        DOCKERHUB_USER = 'YOUR_DOCKERHUB_USERNAME'
        IMAGE_NAME = 'shelflife'
        // Full image name with registry
        IMAGE_FULL = "${DOCKERHUB_USER}/${IMAGE_NAME}"
    }

    parameters {
        // The app server IP - can also be set as a Jenkins environment variable
        string(name: 'APP_SERVER_IP', defaultValue: '', description: 'App server public IP (from Terraform output)')
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
                // Use SSH agent with stored private key (credential ID: app-server-ssh)
                sshagent(['app-server-ssh']) {
                    sh """
                        # Copy deploy script to app server
                        scp -o StrictHostKeyChecking=no scripts/deploy.sh ubuntu@${params.APP_SERVER_IP}:/tmp/deploy.sh
                        
                        # Make it executable and run it
                        ssh -o StrictHostKeyChecking=no ubuntu@${params.APP_SERVER_IP} \\
                            "chmod +x /tmp/deploy.sh && IMAGE=${IMAGE_FULL}:${BUILD_NUMBER} /tmp/deploy.sh"
                    """
                }
            }
        }

        stage('Smoke Test') {
            // Only smoke test on main branch after deploy
            when { branch 'main' }
            steps {
                // Wait a moment for the container to fully start
                sh 'sleep 5'
                // Curl the health endpoint on the app server; fail build if not 200
                sh """
                    HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" http://${params.APP_SERVER_IP}/health)
                    if [ "\$HTTP_CODE" != "200" ]; then
                        echo "Smoke test FAILED: /health returned HTTP \$HTTP_CODE"
                        exit 1
                    fi
                    echo "Smoke test PASSED: /health returned 200"
                """
            }
        }
    }

    post {
        success {
            echo "Pipeline SUCCEEDED! Build #${BUILD_NUMBER} deployed successfully."
            echo "App URL: http://${params.APP_SERVER_IP}"
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
