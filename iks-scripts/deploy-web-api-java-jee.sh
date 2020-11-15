#!/bin/bash

root_folder=$(cd $(dirname $0); cd ..; pwd)

CFG_FILE=${root_folder}/local.env
# Check if config file exists
if [ ! -f $CFG_FILE ]; then
     _out Config file local.env is missing! Check our instructions!
     exit 1
fi  
source $CFG_FILE

# Login to IBM Cloud Image Registry
ibmcloud cr region-set $IBM_CLOUD_REGION
ibmcloud cr login

exec 3>&1

function _out() {
  echo "$(date +'%F %H:%M:%S') $@"
}

function setup() {
  _out Deploying web-api-java-jee v1
  
  cd ${root_folder}/web-api-java-jee
  kubectl delete -f deployment/kubernetes-service.yaml --ignore-not-found
  kubectl delete -f deployment/kubernetes-deployment-v1.yaml --ignore-not-found
  kubectl delete -f deployment/kubernetes-deployment-v2.yaml --ignore-not-found
  kubectl delete -f deployment/istio-service-v2.yaml --ignore-not-found

  file="${root_folder}/web-api-java-jee/liberty-opentracing-zipkintracer-1.3-sample.zip"
  if [ -f "$file" ]
  then
	  echo "$file found"
  else
	  curl -L -o $file https://github.com/WASdev/sample.opentracing.zipkintracer/releases/download/1.3/liberty-opentracing-zipkintracer-1.3-sample.zip
  fi
  unzip -o liberty-opentracing-zipkintracer-1.3-sample.zip -d liberty-opentracing-zipkintracer/

  sed 's/10/5/' src/main/java/com/ibm/webapi/business/Service.java > src/main/java/com/ibm/webapi/business/Service2.java
  rm src/main/java/com/ibm/webapi/business/Service.java
  mv src/main/java/com/ibm/webapi/business/Service2.java src/main/java/com/ibm/webapi/business/Service.java

  # docker build for ICR  
  docker build -f Dockerfile.nojava --tag $REGISTRY/$REGISTRY_NAMESPACE/web-api:1 .
  docker push $REGISTRY/$REGISTRY_NAMESPACE/web-api:1
  
  kubectl apply -f deployment/kubernetes-service.yaml

  # Add ICR tags to K8s deployment.yaml  
  sed "s+web-api:1+$REGISTRY/$REGISTRY_NAMESPACE/web-api:1+g" deployment/kubernetes-deployment-v1.yaml > deployment/IKS-kubernetes-deployment-v1.yaml
  kubectl apply -f deployment/IKS-kubernetes-deployment-v1.yaml

  ##kubectl apply -f deployment/istio-ingress.yaml
  kubectl apply -f deployment/istio-service-v1.yaml

  clusterip=$(ibmcloud ks workers --cluster $CLUSTER_NAME | awk '/Ready/ {print $2;exit;}')
  nodeport=$(kubectl get svc web-api --output 'jsonpath={.spec.ports[*].nodePort}')
  _out Cluster IP: ${clusterip}
  _out NodePort: ${nodeport}
  
  _out Done deploying web-api-java-jee v1
  _out Wait until the pod has been started. Check with these commands: 
  _out "kubectl get pod --watch | grep web-api"
  _out Open the OpenAPI explorer: http://${clusterip}:${nodeport}/openapi/ui/
}

setup