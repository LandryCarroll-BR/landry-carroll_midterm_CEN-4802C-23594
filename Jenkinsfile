pipeline {
  agent any
  options { timestamps() }

  environment {
    IMAGE_NAME = "springboot-demo"
    MAIN_CONTAINER_NAME = "springboot-demo"
    STAGING_CONTAINER_NAME = "springboot-demo-staging"
    MAIN_PORT = "9090"
    STAGING_PORT = "9091"
    CONTAINER_NAME = ""
    HOST_PORT = ""
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

    stage('Configure Deployment Target') {
      steps {
        script {
          if (env.BRANCH_NAME == 'staging') {
            env.CONTAINER_NAME = env.STAGING_CONTAINER_NAME
            env.HOST_PORT = env.STAGING_PORT
          } else if (env.BRANCH_NAME == 'main') {
            env.CONTAINER_NAME = env.MAIN_CONTAINER_NAME
            env.HOST_PORT = env.MAIN_PORT
          } else {
            echo "Branch ${env.BRANCH_NAME} is not configured for deployment. Only 'staging' and 'main' deploy containers."
          }

          if (env.CONTAINER_NAME?.trim()) {
            currentBuild.description = "${env.BRANCH_NAME} -> ${env.CONTAINER_NAME}:${env.HOST_PORT}"
            echo "Deploy target: ${env.CONTAINER_NAME} on port ${env.HOST_PORT}"
          }
        }
      }
    }

    stage('Test (JUnit)') {
      when {
        anyOf {
          branch 'main'
          branch 'staging'
        }
      }
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

    stage('Deploy (Run Container Locally)') {
      when {
        anyOf {
          branch 'main'
          branch 'staging'
        }
      }
      steps {
        sh '''
          # Stop/remove existing container if it exists
          docker rm -f $CONTAINER_NAME || true

          # Run the new version
          docker run -d --name $CONTAINER_NAME -p $HOST_PORT:8080 $IMAGE_NAME:$IMAGE_TAG

          # Show running containers for demo visibility
          docker ps | head -n 20
        '''
      }
    }
  }

  post {
    always {
      script {
        if (env.CONTAINER_NAME?.trim()) {
          sh 'docker logs --tail 50 $CONTAINER_NAME || true'
        } else {
          echo "No deployment target for branch ${env.BRANCH_NAME}. Skipping container log collection."
        }
      }
    }
  }
}
