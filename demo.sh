#!/usr/bin/env bash

TEMP_DIR="tmp"

## Check that we have all the tools we need for the demo
check_dependencies() {
  local tools=("git" "http")
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      echo "$tool not found. Please install $tool first."
      exit 1
    fi
  done
}

## Create a temp directory and switch to it
init() {
  rm -rf "$TEMP_DIR"
  mkdir "$TEMP_DIR"
  cd "$TEMP_DIR" || exit
  clear
}

## Install Concourse
install_concourse() {
  curl -O https://concourse-ci.org/docker-compose.yml
  sed -i '' 's/image: concourse\/concourse$/image: concourse\/concourse:7.14.1/' docker-compose.yml
  sed -i '' "s|CONCOURSE_EXTERNAL_URL: http://localhost:8080|CONCOURSE_EXTERNAL_URL: $CONCOURSE_EXTERNAL_URL|g" docker-compose.yml
  sed -i '' 's/8\.8\.8\.8/192.168.65.7/g' docker-compose.yml
  sed -i '' 's/tutorial/bill-tanzu/g' docker-compose.yml
  sed -i '' 's/overlay/naive/g' docker-compose.yml
  echo '    restart: unless-stopped' >>docker-compose.yml

  cat >>docker-compose.yml <<EOF
  nexus:
    image: sonatype/nexus3
    container_name: nexus
    ports:
      - "8081:8081"
    restart: unless-stopped
    environment:
      - INSTALL4J_ADD_VM_PARAMS=-Dnexus.security.randompassword=false
  nexus-config:
    image: curlimages/curl:latest
    depends_on:
      - nexus
    command: >
      sh -c "
        echo 'Waiting for Nexus to start...'
        export NEXUS_URL=http://nexus:8081
        export NEXUS_USER=admin
        export NEXUS_PASSWORD=admin123

        while ! curl -f -s \$\${NEXUS_URL}/service/rest/v1/status; do
          sleep 10
        done

        echo 'Configuring anonymous access...'
        curl -X PUT \"\$\${NEXUS_URL}/service/rest/v1/security/anonymous\" \
          -H 'Content-Type: application/json' \
          -u \"\$\${NEXUS_USER}:\$\${NEXUS_PASSWORD}\" \
          -d '{\"enabled\":true,\"userId\":\"anonymous\",\"realmName\":\"NexusAuthorizingRealm\"}'
        echo 'Configuration complete'

        echo \"Creating a new Maven proxy repository...\"
        curl -X POST \"\$\${NEXUS_URL}/service/rest/v1/repositories/maven/proxy\" -u \"\$\${NEXUS_USER}:\$\${NEXUS_PASSWORD}\" -H \"Content-Type: application/json\" -d '{ \
            \"name\": \"spring-enterprise\", \
            \"online\": true, \
            \"storage\": { \
              \"blobStoreName\": \"default\", \
              \"strictContentTypeValidation\": true \
            }, \
            \"proxy\": { \
              \"remoteUrl\": \"https://packages.broadcom.com/artifactory/spring-enterprise/\", \
              \"contentMaxAge\": 1440, \
              \"metadataMaxAge\": 1440 \
            }, \
            \"negativeCache\": { \
              \"enabled\": true, \
              \"timeToLive\": 1440 \
            }, \
            \"httpClient\": { \
              \"blocked\": false, \
              \"autoBlock\": true, \
              \"connection\": { \
                \"retries\": 0, \
                \"timeout\": 60, \
                \"enableCircularRedirects\": false, \
                \"enableCookies\": false \
              }, \
              \"authentication\": { \
                \"type\": \"username\", \
                \"username\": \"${MAVEN_USERNAME}\", \
                \"password\": \"${MAVEN_PASSWORD}\" \
              } \
            }, \
            \"maven\": { \
              \"versionPolicy\": \"RELEASE\", \
              \"layoutPolicy\": \"STRICT\" \
            } \
          }'
        
        echo 'Adding repository to maven-public group...'
        curl -X PUT \"\$\${NEXUS_URL}/service/rest/v1/repositories/maven/group/maven-public\" -u \"\$\${NEXUS_USER}:\$\${NEXUS_PASSWORD}\" -H \"Content-Type: application/json\" -d '{ \
            \"name\": \"maven-public\", \
            \"online\": true, \
            \"storage\": { \
              \"blobStoreName\": \"default\", \
              \"strictContentTypeValidation\": true \
            }, \
            \"group\": { \
              \"memberNames\": [ \
                \"maven-releases\", \
                \"maven-snapshots\", \
                \"maven-central\", \
                \"spring-enterprise\" \
              ] \
            }, \
            \"maven\": { \
              \"versionPolicy\": \"RELEASE\", \
              \"layoutPolicy\": \"STRICT\" \
            } \
          }'

        echo 'Disable strict content validation...'
        curl -X POST \"\$\${NEXUS_URL}/service/rest/v1/script\" \
          -H 'Content-Type: application/json' \
          -u \"\$\${NEXUS_USER}:\$\${NEXUS_PASSWORD}\" \
          -d '{\"name\":\"disable-strict\",\"type\":\"groovy\",\"content\":\"repository.getRepositoryManager().get(\\\"spring-enterprise\\\").configuration.attributes[\\\"storage\\\"][\\\"strictContentTypeValidation\\\"] = false\"}'

        echo \"\"
        echo 'Nexus configuration complete!'
      "
    restart: "no"
EOF

  docker compose down --remove-orphans
  docker volume prune -f
  docker compose up -d
}

## Install Fly
install_fly() {

  ### Download CLI
  until curl 'http://localhost:8080/api/v1/cli?arch=arm64&platform=darwin' -o fly; do
    echo "Retrying..."
    sleep 1
  done

  chmod +x ./fly
  ./fly -t advisor-demo login -c http://localhost:8080 -u test -p test -n main

  ### Create Concourse teams for GitHub orgs
  orgs=$(echo "$GITHUB_ORGS" | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g')
  IFS=',' read -ra ORG_ARRAY <<< "$orgs"
  for org in "${ORG_ARRAY[@]}"; do
    ./fly -t advisor-demo set-team --team-name "$org" --local-user test --non-interactive
  done

  ### Deploy Pipelines
  ./fly -t advisor-demo set-pipeline --non-interactive \
    -p rewrite-spawner \
    -c ../pipelines/spawner-pipeline.yml \
    -v advisor_version="$ADVISOR_VERSION" \
    -v github_token="$GIT_TOKEN_FOR_PRS" \
    -v github_orgs="$GITHUB_ORGS" \
    -v gitlab_token="${GITLAB_TOKEN:-}" \
    -v gitlab_groups="${GITLAB_GROUPS:-[]}" \
    -v gitlab_host="${GITLAB_HOST:-https://gitlab.com}" \
    -v git_email="$GIT_EMAIL" \
    -v git_name="$GIT_NAME" \
    -v api_base='https://api.github.com' \
    -v maven_password="$MAVEN_PASSWORD" \
    -v maven_username="$MAVEN_USERNAME" \
    -v docker-hub-username="$DOCKER_USER" \
    -v docker-hub-password="$DOCKER_PASS" > /dev/null

  ### Trigger Pipeline
  ./fly -t advisor-demo unpause-pipeline -p rewrite-spawner
  ./fly -t advisor-demo trigger-job -j rewrite-spawner/discover-and-spawn
}

main() {
  check_dependencies
  init
  install_concourse
  install_fly
}

main
