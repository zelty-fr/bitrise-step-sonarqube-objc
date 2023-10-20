#!/bin/bash
set -exuo pipefail

echo "BITRISE_GIT_BRANCH=${BITRISE_GIT_BRANCH}"
echo "BITRISE_PULL_REQUEST=${BITRISE_PULL_REQUEST}"
echo "BITRISEIO_GIT_BRANCH_DEST=${BITRISEIO_GIT_BRANCH_DEST}"
echo "SONAR_WRAPPER=${SONAR_WRAPPER}"

BUILD_DIR=../BuildSonar
DEPLOY_DIR="${BITRISE_DEPLOY_DIR}"
mkdir -p $BUILD_DIR

JAVA_VERSION_MAJOR=$(java -version 2>&1 | grep -i version | sed 's/.*version ".*\.\(.*\)\..*"/\1/; 1q')
if [ ! -z "${JAVA_VERSION_MAJOR}" ]; then
  if [ "${JAVA_VERSION_MAJOR}" -lt "8" ]; then
    echo -e "\e[93mSonar Scanner CLI requires JRE or JDK version 8 or newer. Version \"${JAVA_VERSION_MAJOR}\" has been detected, CLI may not work properly.\e[0m"
  fi
else
  echo -e "\e[91mSonar Scanner CLI requires JRE or JDK version 8 or newer. None has been detected, CLI may not work properly.\e[0m"
fi

WRAPPER_ARGS=""

if [ "${SONAR_WRAPPER}" == "1" ]; then
	SONAR_WARPPER_CMD=$BUILD_DIR/build-wrapper-macosx-x86/build-wrapper-macosx-x86
	if [ ! -f $SONAR_WARPPER_CMD ]; then
	  pushd $BUILD_DIR
	  wget https://sonarcloud.io/static/cpp/build-wrapper-macosx-x86.zip
	  unzip build-wrapper-macosx-x86.zip
	  popd
	fi

	env NSUnbufferedIO=YES \
	"${SONAR_WARPPER_CMD}" --out-dir $BUILD_DIR/bw-output xcodebuild \
	-workspace "${xcodebuild_workspace}" \
	-scheme "${xcodebuild_scheme}" \
	-destination "${xcodebuild_destination}" \
	-derivedDataPath $BUILD_DIR/derived_data_path \
	${xcodebuild_actions} ${xcodebuild_args} CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO | xcpretty -r json-compilation-database

	WRAPPER_ARGS="-Dsonar.cfamily.build-wrapper-output=$BUILD_DIR/bw-output/"
else
	env NSUnbufferedIO=YES \
	xcodebuild \
	-workspace "${xcodebuild_workspace}" \
	-scheme "${xcodebuild_scheme}" \
	-destination "${xcodebuild_destination}" \
	-derivedDataPath $BUILD_DIR/derived_data_path \
	${xcodebuild_actions} ${xcodebuild_args} CODE_SIGNING_REQUIRED=NO COMPILER_INDEX_STORE_ENABLE=NO | xcpretty -r json-compilation-database
fi

SONAR_XCCOV_CMD=$BUILD_DIR/xccov-to-sonarqube-generic.sh
if [ ! -f $SONAR_XCCOV_CMD ]; then
	pushd $BUILD_DIR
	curl https://raw.githubusercontent.com/SonarSource/sonar-scanning-examples/master/swift-coverage/swift-coverage-example/xccov-to-sonarqube-generic.sh | sed 's/xcrun --show-sdk-version/xcrun --show-sdk-version --sdk macosx/g' > $SONAR_XCCOV_CMD
	popd
fi
SONAR_COV_REPORT=$DEPLOY_DIR/sonarqube-generic-coverage.xml
bash $SONAR_XCCOV_CMD $BUILD_DIR/derived_data_path/Logs/Test/*.xcresult/ | sed "s#$(realpath `pwd`)/##g" > "${SONAR_COV_REPORT}"

SONAR_SCANNER_CMD=$BUILD_DIR/sonar-scanner-${scanner_version}/bin/sonar-scanner
if [ ! -f $SONAR_SCANNER_CMD ]; then
  pushd $BUILD_DIR
  wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${scanner_version}.zip
  unzip sonar-scanner-cli-${scanner_version}.zip
  popd
fi

SWIFTLINT_REPORT=$DEPLOY_DIR/swiftlint.json
Pods/SwiftLint/swiftlint lint --reporter json > $SWIFTLINT_REPORT || echo "Failure..."

PR_ARGS=""
if [ ! -z "${BITRISE_PULL_REQUEST}" ]; then
  PR_ARGS="${PR_ARGS} -Dsonar.pullrequest.branch=${BITRISE_GIT_BRANCH} -Dsonar.pullrequest.key=${BITRISE_PULL_REQUEST}"
  if [ ! -z "${BITRISEIO_GIT_BRANCH_DEST}" ]; then
    PR_ARGS="${PR_ARGS} -Dsonar.pullrequest.base=${BITRISEIO_GIT_BRANCH_DEST}"
  fi
else
  PR_ARGS="-Dsonar.branch.name=${BITRISE_GIT_BRANCH}"
fi

"${SONAR_SCANNER_CMD}" ${PR_ARGS} ${WRAPPER_ARGS} \
 -Dsonar.cfamily.threads=${sonar_cfamily_threads} \
 -Dsonar.projectKey="${sonar_project_key}" \
 -Dsonar.organization="${sonar_orga_name}" \
 -Dsonar.host.url="${sonar_endpoint}" \
 -Dsonar.token="${sonar_token}" \
 -Dsonar.sources=./ \
 -Dsonar.swift.swiftLint.reportPaths="${SWIFTLINT_REPORT}" \
 -Dsonar.coverageReportPaths="${SONAR_COV_REPORT}" \
 -Dsonar.cfamily.compile-commands=build/reports/compilation_db.json
