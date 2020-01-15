#!/bin/bash

# Set hostname
hostname Jenkins

# Install and upgrade packages
yum update -y
yum install -y python-pip wget git docker
pip install --upgrade awscli

# Install Java and Maven
yum remove java-1.7.0* -y
yum install -y java-1.8.0*
wget -O /opt/apache-maven-3.6.3-bin.tar.gz https://www-us.apache.org/dist/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz
tar -xvzf /opt/apache-maven-3.6.3-bin.tar.gz -C /opt
mv /opt/apache-maven-3.6.3 /opt/maven
rm -f /opt/apache-maven-3.6.3-bin.tar.gz
java_version=$(find /usr/lib/jvm/java-1.8.0-openjdk-1.8* | head -n 1)

cat <<EOF >> /etc/profile
export JAVA_HOME=$java_version
export M2_HOME=/opt/maven
export M2=/opt/maven/bin
export PATH=\$PATH:\$JAVA_HOME:\$M2:\$M2_HOME
EOF
source /etc/profile

# Install Jenkins
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
yum install -y jenkins-2.204.1-1.1
sed -i -e 's|^JENKINS_JAVA_OPTIONS="-Djava.awt.headless=true"|JENKINS_JAVA_OPTIONS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"|' /etc/sysconfig/jenkins

# Start Jenkins
service jenkins start
chkconfig jenkins on

# Install Jenkins Plugins
until wget -O ~/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar; do
    echo "Downloading jenkins-cli.jar"
    sleep 5
done

aws s3 cp s3://${S3_BUCKET}/${PLUGINS_PATH} ~/${PLUGINS_PATH}
plugins=$(cat ~/${PLUGINS_PATH})
for plugin in $plugins;
do
    java -jar ~/jenkins-cli.jar -s http://localhost:8080/ install-plugin $plugin
done

java -jar ~/jenkins-cli.jar -s http://localhost:8080/ restart

# Configure Jenkins
until wget -O ~/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar; do
    echo "Downloading jenkins-cli.jar"
    sleep 5
done

for path in ${CSRF_PATH} ${DEFAULT_PATH} ${AGENT_SECURITY_PATH} ${CREATE_USER_PATH}
do
    aws s3 cp s3://${S3_BUCKET}/$path ~/$path
done

PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
sed -i -e 's|{{USERNAME}}|${USERNAME}|g' \
       -e 's|{{PASSWORD}}|${PASSWORD}|' ~/${CREATE_USER_PATH}
sed -i -e 's|{{JENKINS_EMAIL}}|${JENKINS_EMAIL}|' \
       -e 's|{{PUBLIC_IP}}|$PUBLIC_IP|' ~/${DEFAULT_PATH}

for path in ${CSRF_PATH} ${DEFAULT_PATH} ${AGENT_SECURITY_PATH} ${CREATE_USER_PATH}
do
    java -jar ~/jenkins-cli.jar -s http://localhost:8080/ groovy = < ~/$path
done

java -jar ~/jenkins-cli.jar -s http://localhost:8080/ -auth ${USERNAME}:${PASSWORD} safe-restart
rm -rf ~/jenkins