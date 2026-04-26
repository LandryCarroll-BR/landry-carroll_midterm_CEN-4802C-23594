pipeline {
  agent any
  options { timestamps() }
  parameters {
    booleanParam(
      name: 'SIMULATE_POST_SWITCH_FAILURE',
      defaultValue: false,
      description: 'Main only: fail after blue/green traffic switches to exercise automatic failback before updating the stable tag.'
    )
    booleanParam(
      name: 'ENABLE_INCIDENT_SIMULATION',
      defaultValue: false,
      description: 'Expose /simulate/error and /simulate/crash in deployed containers so you can trigger incident tests without breaking the build.'
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
    DATADOG_API_KEY_CREDENTIALS_ID = "DATADOG_API_KEY"
    DD_SITE_CREDENTIALS_ID = "DD_SITE"
    DATADOG_AGENT_NAME = "springboot-demo-datadog-agent"
    DATADOG_AGENT_IMAGE = "gcr.io/datadoghq/agent:7"
    DATADOG_APP_SERVICE = "springboot-demo"
    DATADOG_PROXY_SERVICE = "springboot-demo-proxy"
    DATADOG_TRACE_PORT = "8126"
    PERF_ARTIFACT_ROOT = "target/performance"
    PERF_ARTIFACT_DIR = "target/performance/default"
    PERF_BASELINE_FILE = "performance/baseline.json"
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
      steps {
        script {
          if (env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) {
            env.IMAGE_TAG = params.DEPLOY_TAG.trim()
          } else {
            env.IMAGE_TAG = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
          }
          def rawBranchName = env.BRANCH_NAME ?: sh(returnStdout: true, script: "git rev-parse --abbrev-ref HEAD").trim()
          def normalizedBranch = rawBranchName
            .toLowerCase()
            .replaceAll(/[^a-z0-9]+/, '-')
            .replaceAll(/^-+/, '')
            .replaceAll(/-+$/, '')

          env.NORMALIZED_BRANCH = normalizedBranch ?: 'unknown'
          env.PERF_GATE_STATUS = '0'
          env.PERF_ARTIFACT_DIR = "${env.PERF_ARTIFACT_ROOT}/${env.NORMALIZED_BRANCH}-${env.BUILD_NUMBER ?: env.IMAGE_TAG}"

          currentBuild.description = "${rawBranchName}:${env.IMAGE_TAG}"
          if (env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) {
            currentBuild.description = "${currentBuild.description} [manual-rollback]"
          }
          if (params.SIMULATE_POST_SWITCH_FAILURE && env.BRANCH_NAME == 'main') {
            currentBuild.description = "${currentBuild.description} [simulate-failback]"
          }
          if (params.ENABLE_INCIDENT_SIMULATION) {
            currentBuild.description = "${currentBuild.description} [incident-sim]"
          }
          echo "Using image tag ${env.IMAGE_TAG}"
          echo "Performance artifacts will be written to ${env.PERF_ARTIFACT_DIR}"
        }
      }
    }

    stage('Build Local Performance Image') {
      when {
        expression { !(env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) }
      }
      steps {
        sh 'chmod +x scripts/ci/*.sh scripts/perf/*.sh || true'
        sh '''
          docker build -t $IMAGE_NAME:$IMAGE_TAG .

          if [ "$BRANCH_NAME" = "main" ]; then
            docker tag $IMAGE_NAME:$IMAGE_TAG $DOCKERHUB_REPO:$IMAGE_TAG
          fi
        '''
      }
    }

    stage('Run Lightweight Load Test') {
      when {
        expression { !(env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) }
      }
      steps {
        timeout(time: 3, unit: 'MINUTES') {
          sh 'chmod +x scripts/ci/*.sh scripts/perf/*.sh || true'
          sh 'scripts/perf/run-load-test.sh'
        }
      }
    }

    stage('Evaluate Performance Baseline') {
      when {
        expression { !(env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) }
      }
      steps {
        timeout(time: 1, unit: 'MINUTES') {
          sh 'chmod +x scripts/perf/*.sh || true'
          script {
            echo "Evaluating baseline from ${env.PERF_BASELINE_FILE} using artifacts in ${env.PERF_ARTIFACT_DIR}"
            int perfStatus = sh(returnStatus: true, script: 'scripts/perf/evaluate-baseline.sh')
            env.PERF_GATE_STATUS = perfStatus.toString()
            echo "Performance gate status: ${env.PERF_GATE_STATUS}"

            if (perfStatus != 0) {
              currentBuild.description = "${currentBuild.description} [perf-regression]"
            }
          }
        }
      }
    }

    stage('Publish Performance Metrics to Datadog') {
      when {
        expression { !(env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) }
      }
      steps {
        timeout(time: 1, unit: 'MINUTES') {
          sh 'chmod +x scripts/perf/*.sh || true'
          catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
            withCredentials([
              string(credentialsId: env.DATADOG_API_KEY_CREDENTIALS_ID, variable: 'DATADOG_API_KEY'),
              string(credentialsId: env.DD_SITE_CREDENTIALS_ID, variable: 'DD_SITE')
            ]) {
              sh 'scripts/perf/publish-datadog-metrics.sh'
            }
          }
        }
      }
    }

    stage('Archive Performance Artifacts') {
      when {
        expression { !(env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) }
      }
      steps {
        timeout(time: 1, unit: 'MINUTES') {
          echo "Archiving performance artifacts from ${env.PERF_ARTIFACT_DIR}"
          archiveArtifacts artifacts: "${env.PERF_ARTIFACT_DIR}/**/*", allowEmptyArchive: false
        }
      }
    }

    stage('Enforce Performance Gate') {
      when {
        expression { !(env.BRANCH_NAME == 'main' && params.DEPLOY_TAG?.trim()) }
      }
      steps {
        timeout(time: 1, unit: 'MINUTES') {
          script {
            echo "Final performance gate status is ${env.PERF_GATE_STATUS}"
            if (env.PERF_GATE_STATUS != '0') {
              error("Performance thresholds failed. Review ${env.PERF_ARTIFACT_DIR}/threshold-report.txt for details.")
            }
          }
        }
      }
    }

    stage('Ensure Datadog Agent') {
      when {
        anyOf {
          branch 'main'
          branch 'staging'
        }
      }
      steps {
        sh 'chmod +x scripts/ci/*.sh scripts/perf/*.sh || true'
        withCredentials([
          string(credentialsId: env.DATADOG_API_KEY_CREDENTIALS_ID, variable: 'DATADOG_API_KEY'),
          string(credentialsId: env.DD_SITE_CREDENTIALS_ID, variable: 'DD_SITE')
        ]) {
          sh 'scripts/ci/ensure-datadog-agent.sh'
        }
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
          APP_LOGS_LABEL='[{"source":"java","service":"'"$DATADOG_APP_SERVICE"'"}]'

          # Stop/remove existing container if it exists
          docker rm -f $STAGING_CONTAINER_NAME || true

          # Run the staging version
          docker run -d \
            --name $STAGING_CONTAINER_NAME \
            --network $PROD_NETWORK \
            -p $STAGING_PORT:8080 \
            -e DD_ENV=staging \
            -e DD_SERVICE=$DATADOG_APP_SERVICE \
            -e DD_VERSION=$IMAGE_TAG \
            -e DD_TRACE_ENABLED=true \
            -e DD_AGENT_HOST=$DATADOG_AGENT_NAME \
            -e DD_TRACE_AGENT_PORT=$DATADOG_TRACE_PORT \
            -e DD_LOGS_INJECTION=true \
            -e INCIDENT_SIMULATION_ENABLED=$ENABLE_INCIDENT_SIMULATION \
            -l com.datadoghq.tags.env=staging \
            -l com.datadoghq.tags.service=$DATADOG_APP_SERVICE \
            -l com.datadoghq.tags.version=$IMAGE_TAG \
            -l com.datadoghq.ad.logs="$APP_LOGS_LABEL" \
            $IMAGE_NAME:$IMAGE_TAG

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
        sh 'chmod +x scripts/ci/*.sh scripts/perf/*.sh || true'
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
