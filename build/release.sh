#!/bin/bash

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function usage() {
  printf "usage: release.sh [OPTIONS]\n\n"
  printf "builds and releases vinyldns artifacts\n\n"
  printf "options:\n"
  printf "\t-b, --branch: the branch of tag to use for the build; default is master\n"
  printf "\t-c, --clean: indicates a fresh build or attempt to work with existing images; default is off\n"
  printf "\t-p, --push: indicates docker will push to the repository; default is off\n"
  printf "\t-r, --repository [REPOSITORY]: the docker repository where this image will be pushed; default is docker.io\n"
  printf "\t-t, --tag [TAG]: sets the qualifier for the semver version; default is -SNAPSHOT\n"
}

# Default the build to -SNAPSHOT if not set
BUILD_TAG="-SNAPSHOT"
REPOSITORY="docker.io"
DOCKER_PUSH=0
DO_BUILD=0
BRANCH="master"

while [ "$1" != "" ]; do
  case "$1" in
  -b | --branch)
    BRANCH="$2"
    shift 2
    ;;
  -c | --clean)
    DO_BUILD=1
    shift
    ;;
  -p | --push)
    DOCKER_PUSH=1
    shift
    ;;
  -r | --repository)
    REPOSITORY="$2"
    shift 2
    ;;
  -t | --tag)
    BUILD_TAG="-b$2"
    shift 2
    ;;
  *)
    usage
    exit
    ;;
  esac
done

BASEDIR=$CURDIR/../

# Clear out our target
rm -rf $CURDIR/target && mkdir -p $CURDIR/target

# Download just the version.sbt file from the branch specified, we use this to calculate the version
wget "https://raw.githubusercontent.com/vinyldns/vinyldns/${BRANCH}/version.sbt" -P "${CURDIR}/target"

# Calculate the version by using version.sbt, this will pull out something like 0.9.4
V=$(find $CURDIR/target -name "version.sbt" | head -n1 | xargs grep "[ \\t]*version in ThisBuild :=" | head -n1 | sed 's/.*"\(.*\)".*/\1/')
echo "VERSION ON BRANCH ${BRANCH} IS ${V}"
if [[ "$V" == *-SNAPSHOT ]]; then
  export VINYLDNS_VERSION="${V%?????????}${BUILD_TAG}"
else
  export VINYLDNS_VERSION="$V${BUILD_TAG}"
fi

if [ $DO_BUILD -eq 1 ]; then
  docker-compose -f $CURDIR/docker/docker-compose.yml build \
    --no-cache \
    --parallel \
    --build-arg VINYLDNS_VERSION="${VINYLDNS_VERSION}" \
    --build-arg BRANCH="${BRANCH}"

  if [ $? -eq 0 ]; then
    # Runs smoke tests to make sure the new images are sound
    docker-compose -f $CURDIR/docker/docker-compose.yml --log-level ERROR up --exit-code-from functest
  fi

  if [ $? -eq 0 ]; then
    docker tag vinyldns/test-bind9:$VINYLDNS_VERSION $REPOSITORY/vinyldns/test-bind9:$VINYLDNS_VERSION
    docker tag vinyldns/test:$VINYLDNS_VERSION $REPOSITORY/vinyldns/test:$VINYLDNS_VERSION
    docker tag vinyldns/api:$VINYLDNS_VERSION $REPOSITORY/vinyldns/api:$VINYLDNS_VERSION
    docker tag vinyldns/portal:$VINYLDNS_VERSION $REPOSITORY/vinyldns/portal:$VINYLDNS_VERSION
  fi
fi

if [ $DOCKER_PUSH -eq 1 ]; then
  docker push $REPOSITORY/vinyldns/test-bind9:$VINYLDNS_VERSION
  docker push $REPOSITORY/vinyldns/test:$VINYLDNS_VERSION
  docker push $REPOSITORY/vinyldns/api:$VINYLDNS_VERSION
  docker push $REPOSITORY/vinyldns/portal:$VINYLDNS_VERSION
fi
