#!/bin/sh
# Runs INSIDE the "EC2" container (CodeDeploy hook). Floci skips bundle download, so we fetch the WAR here.
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://host.docker.internal:4566}"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
KEY=$(cat /scripts/war-key.txt)
/opt/tomcat/bin/shutdown.sh >/dev/null 2>&1; sleep 2
rm -rf /opt/tomcat/webapps/ROOT /opt/tomcat/webapps/ROOT.war
aws s3 cp "s3://nextwork-artifacts/$KEY" /opt/tomcat/webapps/ROOT.war || exit 1
export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
/opt/tomcat/bin/startup.sh
