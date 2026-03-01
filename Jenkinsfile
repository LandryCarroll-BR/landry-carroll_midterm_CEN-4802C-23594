pipeline {
  agent any
  options { timestamps() }

  environment {
    IMAGE_NAME = "springboot-demo"
    CONTAINER_NAME = "springboot-demo"
  }

  stages {
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
      steps {
        script {
          def sha = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
          env.IMAGE_TAG = sha
        }
        sh 'docker build -t $IMAGE_NAME:$IMAGE_TAG .'
      }
    }

    stage('Deploy (Run Container Locally)') {
      steps {
        sh '''
          # Stop/remove existing container if it exists
          docker rm -f $CONTAINER_NAME || true

          # Run the new version
          docker run -d --name $CONTAINER_NAME -p 9090:8080 $IMAGE_NAME:$IMAGE_TAG

          # Show running containers for demo visibility
          docker ps | head -n 20
        '''
      }
    }
  }

  post {
    always {
      sh 'docker logs --tail 50 $CONTAINER_NAME || true'
    }
  }
}