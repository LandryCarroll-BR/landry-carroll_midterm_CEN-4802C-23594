pipeline {
  agent any
  options { timestamps() }
  parameters {
    booleanParam(
      name: 'SIMULATE_POST_SWITCH_FAILURE',
      defaultValue: false,
      description: 'Main only: fail after blue/green traffic switches to exercise automatic failback before updating the stable tag.'
    )
    string(
      name: 'DEPLOY_TAG',
      defaultValue: '',
      description: 'Main only: deploy an existing Docker Hub tag for manual rollback instead of the current commit SHA.'
    )
  }

  environment {
    IMAGE_NAME = "springboot-demo"
    LEGACY_MAIN_CONTAINER_NAME = "springboot-demo"
    STAGING_CONTAINER_NAME = "springboot-demo-staging"
    STAGING_PORT = "9091"
    DOCKERHUB_REPO = "landtry/springboot-demo"
    DOCKERHUB_CREDENTIALS_ID = "dockerhub-credentials"
    PROD_PROXY_NAME = "springboot-demo-main-proxy"
    PROD_NETWORK = "springboot-demo-main-network"
    PROD_BLUE_NAME = "springboot-demo-main-blue"
    PROD_GREEN_NAME = "springboot-demo-main-green"
    PROD_PORT = "9090"
    STABLE_TAG = "stable"
    PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${env.PATH}"
  }

  stages {
    stage('Debug Docker') {
      steps {
        sh '''
          echo "PATH=$PATH"
          echo "BRANCH_NAME=$BRANCH_NAME"
          which docker || true
          docker --version || true
          docker version || true
        '''
      }
    }

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Test (JUnit)') {
      steps {
        script {
          if (env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) {
            echo "Skipping tests for manual rollback to Docker Hub tag ${params.DEPLOY_TAG}."
          } else {
            sh 'chmod +x mvnw || true'
            sh './mvnw -B test'
          }
        }
      }
      post {
        always {
          script {
            if (env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) {
              echo "No fresh JUnit results for manual rollback runs."
            } else {
              junit 'target/surefire-reports/*.xml'
            }
          }
        }
      }
    }

    stage('Prepare Build Metadata') {
      when {
        anyOf {
          branch 'main'
          branch 'staging'
        }
      }
      steps {
        script {
          if (env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) {
            env.IMAGE_TAG = params.DEPLOY_TAG.trim()
          } else {
            env.IMAGE_TAG = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
          }
          currentBuild.description = "${env.BRANCH_NAME}:${env.IMAGE_TAG}"
          if (env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) {
            currentBuild.description = "${currentBuild.description} [manual-rollback]"
          }
          if (params.SIMULATE_POST_SWITCH_FAILURE && env.BRANCH_NAME == 'main') {
            currentBuild.description = "${currentBuild.description} [simulate-failback]"
          }
          echo "Using image tag ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Build Docker Image') {
      when {
        anyOf {
          allOf {
            branch 'main'
            expression { !params.DEPLOY_TAG?.trim() }
          }
          branch 'staging'
        }
      }
      steps {
        sh 'chmod +x scripts/ci/*.sh || true'
        sh '''
          if [ "$BRANCH_NAME" = "main" ]; then
            docker build -t $IMAGE_NAME:$IMAGE_TAG -t $DOCKERHUB_REPO:$IMAGE_TAG .
          else
            docker build -t $IMAGE_NAME:$IMAGE_TAG .
          fi
        '''
      }
    }

    stage('Validate Main Deployment Configuration') {
      when {
        branch 'main'
      }
      steps {
        script {
          if (env.DOCKERHUB_REPO == 'your-dockerhub-namespace/springboot-demo') {
            error("Update DOCKERHUB_REPO in Jenkinsfile to your real Docker Hub repository before running main deployments.")
          }
          if (params.DEPLOY_TAG?.trim()) {
            echo "Manual rollback deploy requested for Docker Hub tag ${params.DEPLOY_TAG}."
          }
        }
      }
    }

    stage('Deploy Staging') {
      when {
        branch 'staging'
      }
      steps {
        sh '''
          # Stop/remove existing container if it exists
          docker rm -f $STAGING_CONTAINER_NAME || true

          # Run the staging version
          docker run -d --name $STAGING_CONTAINER_NAME -p $STAGING_PORT:8080 $IMAGE_NAME:$IMAGE_TAG

          # Show running containers for demo visibility
          docker ps | head -n 20
        '''
        sh 'docker logs --tail 50 $STAGING_CONTAINER_NAME || true'
      }
    }

    stage('Deploy Main Blue/Green') {
      when {
        branch 'main'
      }
      steps {
        sh 'chmod +x scripts/ci/*.sh || true'
        withCredentials([usernamePassword(credentialsId: env.DOCKERHUB_CREDENTIALS_ID, usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_PASSWORD')]) {
          sh '''
            set +x
            trap 'docker logout || true' EXIT
            echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
            if [ -z "${DEPLOY_TAG}" ]; then
              docker push $DOCKERHUB_REPO:$IMAGE_TAG
            else
              echo "Using existing Docker Hub tag $DEPLOY_TAG for manual rollback."
            fi
            scripts/ci/main-blue-green-deploy.sh
          '''
        }
      }
      post {
        always {
          sh 'docker ps | head -n 20'
          sh 'docker logs --tail 50 $PROD_PROXY_NAME || true'
          sh 'docker logs --tail 50 $PROD_BLUE_NAME || true'
          sh 'docker logs --tail 50 $PROD_GREEN_NAME || true'
          sh 'docker logs --tail 50 $LEGACY_MAIN_CONTAINER_NAME || true'
        }
      }
    }
  }
}
