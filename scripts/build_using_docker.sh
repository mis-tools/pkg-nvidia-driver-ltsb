#!/usr/bin/env bash
set -ex
script_dir=$(dirname "$0")
cd ${script_dir}/..

docker_img_name=build-env_`basename $(git remote show -n origin | grep Fetch | cut -d: -f2-) .git`
echo "building docker image: ${docker_img_name}"
docker build -t ${docker_img_name} scripts/docker_build_environment
# added --net=host to avoid curl error because of wrong mtu - see: https://github.com/moby/moby/issues/22297
docker run -i --rm -u `id -u`:`id -g` -h ${HOSTNAME}-docker --net=host -v /etc/passwd:/etc/passwd:ro -v $(pwd):/builddir ${docker_img_name} /builddir/scripts/builddeb.sh $@
