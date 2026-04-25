pipeline {
  agent any
  options { timestamps() }

  environment {
    IMAGE_NAME = "springboot-demo"
    MAIN_CONTAINER_NAME = "springboot-demo"
    STAGING_CONTAINER_NAME = "springboot-demo-staging"
    MAIN_PORT = "9090"
    STAGING_PORT = "9091"
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
        sh 'chmod +x mvnw || true'
        sh './mvnw -B test'
      }
      post {
        always {
          junit 'target/surefire-reports/*.xml'
        }
      }
    }

    stage('Build Docker Image') {
      when {
        anyOf {
          branch 'main'
          branch 'staging'
        }
      }
      steps {
        script {
          def sha = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
          env.IMAGE_TAG = sha
        }
        sh 'docker build -t $IMAGE_NAME:$IMAGE_TAG .'
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

    stage('Deploy Main') {
      when {
        branch 'main'
      }
      steps {
        sh '''
          # Stop/remove existing container if it exists
          docker rm -f $MAIN_CONTAINER_NAME || true

          # Run the main version
          docker run -d --name $MAIN_CONTAINER_NAME -p $MAIN_PORT:8080 $IMAGE_NAME:$IMAGE_TAG

          # Show running containers for demo visibility
          docker ps | head -n 20
        '''
        sh 'docker logs --tail 50 $MAIN_CONTAINER_NAME || true'
      }
    }
  }
}
