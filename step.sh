#!/bin/bash
set -exuo pipefail

JAVA_VERSION_MAJOR=$(java -version 2>&1 | grep -i version | sed 's/.*version ".*\.\(.*\)\..*"/\1/; 1q')
if [ ! -z "${JAVA_VERSION_MAJOR}" ]; then
  if [ "${JAVA_VERSION_MAJOR}" -lt "8" ]; then
    echo -e "\e[93mSonar Scanner CLI requires JRE or JDK version 8 or newer. Version \"${JAVA_VERSION_MAJOR}\" has been detected, CLI may not work properly.\e[0m"
  fi
else
  echo -e "\e[91mSonar Scanner CLI requires JRE or JDK version 8 or newer. None has been detected, CLI may not work properly.\e[0m"
fi

SONAR_WARPPER_CMD=$BITRISE_SOURCE_DIR/build-wrapper-macosx-x86/build-wrapper-macosx-x86
if [ ! -f $SONAR_WARPPER_CMD ]; then
  pushd $BITRISE_SOURCE_DIR
  wget https://sonarcloud.io/static/cpp/build-wrapper-macosx-x86.zip
  unzip build-wrapper-macosx-x86.zip
  popd
fi

env NSUnbufferedIO=YES \
"${SONAR_WARPPER_CMD}" --out-dir bw-output xcodebuild \
-workspace "${xcodebuild_workspace}" \
-scheme "${xcodebuild_scheme}" \
-destination "${xcodebuild_destination}" \
-derivedDataPath derived_data_path \
"${xcodebuild_actions}" CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO | xcpretty

SONAR_SCANNER_CMD=$BITRISE_SOURCE_DIR/sonar-scanner-${scanner_version}/bin/sonar-scanner
if [ ! -f $SONAR_SCANNER_CMD ]
  pushd $BITRISE_SOURCE_DIR
  wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${scanner_version}.zip
  unzip sonar-scanner-cli-${scanner_version}.zip
  popd
fi

if [[ -z "${BITRISE_PULL_REQUEST}" ]]; then
  "${SONAR_SCANNER_CMD}" \
   -Dsonar.projectKey="${sonar_project_key}" \
   -Dsonar.organization="${sonar_orga_name}" \
   -Dsonar.host.url="${sonar_endpoint}" \
   -Dsonar.login="${sonar_token}" \
   -Dsonar.sources=./ \
   -Dsonar.cfamily.build-wrapper-output=./bw_output/
else 
   "${SONAR_SCANNER_CMD}" \
   -Dsonar.projectKey="${sonar_project_key}" \
   -Dsonar.organization="${sonar_orga_name}" \
   -Dsonar.host.url="${sonar_endpoint}" \
   -Dsonar.login="${sonar_token}" \
   -Dsonar.sources=./ \
   -Dsonar.cfamily.build-wrapper-output=./bw_output/
   -Dsonar.pullrequest.branch=$BITRISE_GIT_BRANCH \
   -Dsonar.pullrequest.key=$BITRISE_PULL_REQUEST
fi
