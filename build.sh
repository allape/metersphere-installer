#!/bin/bash

# Ubuntu 22.04.3 AMD64

# mvnw 代理
# https://docs.oracle.com/javase/8/docs/technotes/guides/net/proxies.html
# vim mvnw
#   "-Dhttp.proxyHost=..." \
#   "-Dhttp.proxyPort=..." \
#   "-Dhttps.proxyHost=..." \
#   "-Dhttps.proxyPort=..." \

# mvn 代理
# vim /usr/share/maven/conf/settings.xml # search for proxy

# export http_proxy=http://...
# export https_proxy=http://...
# export HTTP_PROXY=http://...
# export HTTPS_PROXY=http://...

# npm config -g set proxy http://... # mvn 设置代理后可以不用设置这个
# git config --global http.proxy http://...
# git config --global https.proxy http://...

# Install the dependencies
sudo apt-get update
sudo apt-get install -y git openjdk-17-jdk docker.io docker-compose maven npm

# Install nvm, v18 is required for building for frontend projects
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
source ~/.bashrc
nvm install 18
nvm use 18

# Pull the main project
git clone --depth 1 -b v2.10.8-lts https://github.com/metersphere/metersphere.git v2.10.8-lts
cd v2.10.8-lts

REVISION="2_10_8"
TAG_NAME="latest"
IMAGE_PREFIX='registry.cn-qingdao.aliyuncs.com/metersphere'

# Ubuntu or debian based system
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
export CLASSPATH=$JAVA_HOME/lib:$CLASSPATH
export PATH=$JAVA_HOME/bin:/usr/share/maven/bin:$PATH

# ./mvnw install -N
# ./mvnw clean install -pl framework,framework/sdk-parent,framework/sdk-parent/domain,framework/sdk-parent/sdk,framework/sdk-parent/xpack-interface,framework/sdk-parent/jmeter
# ./mvnw clean package install

# Install dependencies for the main project
mvn install -N -Drevision=${REVISION}
# Build java projects
mvn clean install -Drevision=${REVISION} -pl framework,framework/sdk-parent,framework/sdk-parent/domain,framework/sdk-parent/sdk,framework/sdk-parent/xpack-interface,framework/sdk-parent/jmeter
# Build frontend projects
mvn clean package -Drevision=${REVISION}

# Unzip jars, copied from Jenkinsfile
frameworks=('framework/eureka' 'framework/gateway')
for library in "${frameworks[@]}";
do
    mkdir -p $library/target/dependency && (cd $library/target/dependency; jar -xf ../*.jar)
done

LOCAL_REPOSITORY=$(mvn help:evaluate -Dexpression=settings.localRepository -q -DforceStdout)

libraries=('api-test' 'performance-test' 'project-management' 'system-setting' 'test-track' 'report-stat' 'workstation')
for library in "${libraries[@]}";
do
    # Modified, because there is no file named 'metersphere-xpack' in ~/.m2/repository/io/metersphere/
    mkdir -p $library/backend/target/dependency && (cd $library/backend/target/dependency; jar -xf ../*.jar; cp $LOCAL_REPOSITORY/io/metersphere/xpack-interface/${REVISION}/xpack-interface-${REVISION}.jar ./BOOT-INF/lib/)
done

# Make a dummy worker.js file in framework/gateway/src/main/resources/static/,
# because the framework/gateway/Dockerfile requires it
mkdir -p framework/gateway/src/main/resources/static/
echo "console.log('dummy~');" > framework/gateway/src/main/resources/static/dummy.worker.js

# docker pull registry.cn-qingdao.aliyuncs.com/metersphere/alpine-openjdk17-jre:latest
docker pull metersphere/alpine-openjdk17-jre:latest
docker image tag metersphere/alpine-openjdk17-jre:latest ${IMAGE_PREFIX}/metersphere/alpine-openjdk17-jre:latest

# docker pull registry.cn-qingdao.aliyuncs.com/metersphere/jmeter-master:5.5-ms7-jdk17
docker pull metersphere/jmeter-master:5.5-ms7-jdk17
docker image tag metersphere/jmeter-master:5.5-ms7-jdk17 ${IMAGE_PREFIX}/metersphere/jmeter-master:5.5-ms7-jdk17
docker pull metersphere/jmeter-master:5.4.1-ms3-jdk8
docker image tag metersphere/jmeter-master:5.4.1-ms3-jdk8 ${IMAGE_PREFIX}/metersphere/jmeter-master:5.4.1-ms3-jdk8

# Build the final images
libraries=('framework/eureka' 'framework/gateway' 'api-test' 'performance-test' 'project-management' 'report-stat' 'system-setting' 'test-track' 'workstation')
for library in "${libraries[@]}";
do
    IMAGE_NAME=${library#*/}
    docker build --build-arg MS_VERSION=${TAG_NAME} -t ${IMAGE_PREFIX}/${IMAGE_NAME}:${TAG_NAME} --platform linux/amd64 ./$library
done

cd ..

docker pull metersphere/node-controller:latest
docker image tag metersphere/node-controller:latest ${IMAGE_PREFIX}/node-controller:${TAG_NAME}

docker pull metersphere/data-streaming:latest
docker image tag metersphere/data-streaming:latest ${IMAGE_PREFIX}/data-streaming:${TAG_NAME}

docker pull redis:6.2.6
docker image tag redis:6.2.6 ${IMAGE_PREFIX}/redis:6.2.6

docker pull mysql:8.0.34
docker image tag mysql:8.0.34 ${IMAGE_PREFIX}/mysql:8.0.34

docker pull bitnami/kafka:3.5.1
docker image tag bitnami/kafka:3.5.1 ${IMAGE_PREFIX}/kafka:3.5.1

docker pull bitnami/prometheus:2.42.0
docker image tag bitnami/prometheus:2.42.0 ${IMAGE_PREFIX}/prometheus:v2.42.0

# # Install golang
# wget wget https://go.dev/dl/go1.21.4.linux-amd64.tar.gz
# sudo rm -rf /usr/local/go && tar -C /usr/local -xzf go1.21.4.linux-amd64.tar.gz
# export PATH=$PATH:/usr/local/go/bin
# # Build minio from source
# git clone --depth 1 -b RELEASE.2023-04-13T03-08-07Z https://github.com/minio/minio.git minio-RELEASE.2023-04-13T03-08-07Z
# cd minio-RELEASE.2023-04-13T03-08-07Z
# /usr/local/go/bin/go build
# docker build -t ${IMAGE_PREFIX}/minio:RELEASE.2023-04-13T03-08-07Z -f ./Dockerfile .
# cd ..

docker pull docker pull registry.cn-qingdao.aliyuncs.com/metersphere/minio:RELEASE.2023-04-13T03-08-07Z

# Not working, minio will NOT start up
# docker pull bitnami/minio:2023.4.20 # This is the nearest version from bitnami
# docker image tag bitnami/minio:2023.4.20 ${IMAGE_PREFIX}/minio:RELEASE.2023-04-13T03-08-07Z

./install.sh