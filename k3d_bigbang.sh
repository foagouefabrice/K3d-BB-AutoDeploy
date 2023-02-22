#!/bin/bash
#---------------------------------------------------------------------------------------------------------------------
# this will deploy a k3d single-node  kubernetes cluster in your virtual machine and spin out a demo Bigbang for quick 
# testing.
#---------------------------------------------------------------------------------------------------------------------
# Author: Fabrice F
# Date: Feb 2023

# requirements:
#  - 1 Virtual Machine with 32GB RAM, 8-Core CPU (t3a.2xlarge for AWS users), and 100GB of disk space should be sufficient.
#  - Ubuntu Server 20.04 LTS or latest (Ubuntu comes up slightly faster than CentOS, in reality any Linux distribution 
#    with Docker installed should work)
#  - connect to your Ubuntu server and get the sudo privilege 
#  - please make sure to use Ubuntu or Debian for this demo as most of the command follow ubuntu repo. 

# 1. install Prerequisite Software
      echo "Now we are going to install the required software, Please make sure you are running a Ubuntu server "

# a. install git
    echo "installing git"
      sudo apt install git -y
  
# b. install docker and all depedencies 
    echo "Now we are going to install docker"

    echo "Updating the apt package index and installing packages to allow apt to use a repository over HTTPS: "
    sudo apt-get update -y
    sudo apt-get install ca-certificates curl gnupg lsb-release -y 

    echo " Adding Docker’s official GPG key and repository setup"
    sudo rm -rf /etc/apt/keyrings/docker.gpg
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
         $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo " Updating the apt package index and installing docker engine"
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    sudo apt-get update -y
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

    echo " checking if docker is up and running"
    docker run hello-world > /dev/null
    if [ $? -eq 0 ]; then
    echo "docker is up and running"
    else
    echo "Command failed, please check docker installation"
    exit 1
    fi
# c. install k3d
    echo " Now installing k3d utility"
    wget -q -O - https://github.com/k3d-io/k3d/releases/download/v5.4.1/k3d-linux-amd64 > k3d
    echo 50f64747989dc1fcde5db5cb82f8ac132a174b607ca7dfdb13da2f0e509fda11 k3d | sha256sum -c | grep OK 
    if [ $? == 0 ]; then chmod +x k3d && sudo mv k3d /usr/local/bin/k3d; fi
    echo "you are running ${k3d --version}"

# d. install kubectl 
    echo " Now installing kubectl"
    wget -q -O - https://dl.k8s.io/release/v1.23.5/bin/linux/amd64/kubectl > kubectl
    echo 715da05c56aa4f8df09cb1f9d96a2aa2c33a1232f6fd195e3ffce6e98a50a879 kubectl | sha256sum -c | grep OK
    if [ $? == 0 ]; then chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl; fi
    sudo ln -s /usr/local/bin/kubectl /usr/local/bin/k

    echo "Verify kubectl installation "
    kubectl version --client > /dev/null
    if [ $? -eq 0 ]; then
    echo "kubectl is up and running"
    else
    echo "Command failed, please check kubectl installation"
    exit 1
    fi

# e. Install Kustomize
    echo "Now installing kustomize"
    wget -q -O - https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv4.5.4/kustomize_v4.5.4_linux_amd64.tar.gz > kustomize.tar.gz
    echo 1159c5c17c964257123b10e7d8864e9fe7f9a580d4124a388e746e4003added3 kustomize.tar.gz | sha256sum -c | grep OK
    if [ $? == 0 ]; then tar -xvf kustomize.tar.gz && chmod +x kustomize && sudo mv kustomize /usr/local/bin/kustomize && rm kustomize.tar.gz ; fi  

    echo " Verify Kustomize installation"
    kustomize version
    if [ $? -eq 0 ]; then
    echo "kustomize is up and running"
    else
    echo "Command failed, please check kustomize installation"
    exit 1
    fi

# f. Install Helm
    echo " Now installing Helm"
    wget -q -O - https://get.helm.sh/helm-v3.8.1-linux-amd64.tar.gz > helm.tar.gz
    echo d643f48fe28eeb47ff68a1a7a26fc5142f348d02c8bc38d699674016716f61cd helm.tar.gz | sha256sum -c | grep OK
    if [ $? == 0 ]; then tar -xvf helm.tar.gz && chmod +x linux-amd64/helm && sudo mv linux-amd64/helm /usr/local/bin/helm && rm -rf linux-amd64 && rm helm.tar.gz ; fi  

    echo " Verify Helm installation"
    helm version
    if [ $? -eq 0 ]; then
    echo "helm is up and running"
    else
    echo "Command failed, please check helm installation"
    exit 1
    fi

# g. Configure Host Operating System Prerequisites
    echo "Running Operating System Pre-configuration"
    # Needed for ECK to run correctly without OOM errors
    echo 'vm.max_map_count=524288' | sudo tee -a /etc/sysctl.d/vm-max_map_count.conf
    # Needed by Sonarqube
    echo 'fs.file-max=131072' | sudo tee -a /etc/sysctl.d/fs-file-max.conf
    ulimit -n 131072
    ulimit -u 8192
    # Load updated configuration
    sudo sysctl --load --system
    # Preload kernel modules, required by istio-init running on SELinux enforcing instances
    sudo modprobe xt_REDIRECT
    sudo modprobe xt_owner
    sudo modprobe xt_statistic
    # Persist kernel modules settings after reboots
    printf "xt_REDIRECT\nxt_owner\nxt_statistic\n" | sudo tee -a /etc/modules
    # Turn off all swap devices and files (won't last reboot)
    sudo swapoff -a

# 2. Create a k3d Cluster
    echo "Now we are going to create a k3d Cluster"

# b. create a k3d cluster
    echo "checking for existing k3d cluster"
    k3d cluster delete
    SERVER_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
    echo $SERVER_IP
    export K3D_FIX_DNS=1
    IMAGE_CACHE=${HOME}/.k3d-container-image-cache
    mkdir -p ${IMAGE_CACHE}
    echo "Now we are launching the cluster"
    k3d cluster create \
    --k3s-arg "--tls-san=$SERVER_IP@server:0" \
    --volume /etc/machine-id:/etc/machine-id \
    --volume ${IMAGE_CACHE}:/var/lib/rancher/k3s/agent/containerd/io.containerd.content.v1.content \
    --k3s-arg "--disable=traefik@server:0" \
    --port 80:80@loadbalancer \
    --port 443:443@loadbalancer \
    --api-port 6443
    sleep 5
    echo
    echo "==========================================================================================================="
    echo "====================== CONGRATULATION K3D CLUSTER DEPLOYMENT FINISHED ====================================="
    echo "================================ NOW LET DEPLOY BIGBANG ==================================================="

# 3. Deploy Bigbang
# a. set your environment variable, replace each value by your registry1 credential or use the default value
    registry1_username="YOUR REGISTRY1USERNAME"
    registry1_password="YOUR REGISTRYONESECRET"
    echo "setting environment variable"
    export REGISTRY1_USERNAME=$registry1_username
    export REGISTRY1_PASSWORD=$registry1_password
    echo $REGISTRY1_PASSWORD | docker login registry1.dso.mil --username $REGISTRY1_USERNAME --password-stdin

# b. clone the latest BB release in your home directory
    cd ~
    rm -rf bigbang
    git clone https://repo1.dso.mil/platform-one/big-bang/bigbang.git
    cd ~/bigbang

# c. install flux
 echo "now deploying flux"
 $HOME/bigbang/scripts/install_flux.sh -u $REGISTRY1_USERNAME -p $REGISTRY1_PASSWORD

# d. Create Helm Values .yaml Files To Act as Input Variables for the Big Bang Helm Chart
# the selected value is just for testing purpose, you can add and customize these value 
cat << EOF > ~/ib_creds.yaml
registryCredentials:
  registry: registry1.dso.mil
  username: "$REGISTRY1_USERNAME"
  password: "$REGISTRY1_PASSWORD"
EOF


cat << EOF > ~/demo_values.yaml
logging:
  values:
    kibana:
      count: 1
      resources:
        requests:
          cpu: 400m
          memory: 1Gi
        limits:
          cpu: null  # nonexistent cpu limit results in faster spin up
          memory: null
    elasticsearch:
      master:
        count: 1
        resources:
          requests:
            cpu: 400m
            memory: 2Gi
          limits:
            cpu: null
            memory: null
      data:
        count: 1
        resources:
          requests:
            cpu: 400m
            memory: 2Gi
          limits:
            cpu: null
            memory: null

clusterAuditor:
  values:
    resources:
      requests:
        cpu: 400m
        memory: 2Gi
      limits:
        cpu: null
        memory: null

gatekeeper:
  enabled: false
  values:
    replicas: 1
    controllerManager:
      resources:
        requests:
          cpu: 100m
          memory: 512Mi
        limits:
          cpu: null
          memory: null
    audit:
      resources:
        requests:
          cpu: 400m
          memory: 768Mi
        limits:
          cpu: null
          memory: null
    violations:
      allowedDockerRegistries:
        enforcementAction: dryrun

istio:
  values:
    values: # possible values found here https://istio.io/v1.5/docs/reference/config/installation-options (ignore 1.5, latest docs point here)
      global: # global istio operator values
        proxy: # mutating webhook injected istio sidecar proxy's values
          resources:
            requests:
              cpu: 0m # null get ignored if used here
              memory: 0Mi
            limits:
              cpu: 0m
              memory: 0Mi

twistlock:
  enabled: false # twistlock requires a license to work, so we're disabling it
EOF

# e. Install Big Bang Using the Local Development Workflow
    echo "now we are going to deployed Bigbang"
    helm upgrade --install bigbang $HOME/bigbang/chart \
    --values https://repo1.dso.mil/platform-one/big-bang/bigbang/-/raw/master/chart/ingress-certs.yaml \
    --values $HOME/ib_creds.yaml \
    --values $HOME/demo_values.yaml \
    --namespace=bigbang --create-namespace

    echo "======================================================================================================="
    echo "========================== CONGRATULATION BIGBANG IS NOW DEPLOYED ====================================="
    echo "================================ NOW LET CHECK THE RESOURCES  ========================================="
    echo "Please get yourself a cup of cafe while we deploying the resources, this can take more than 2 minutes"
    sleep 120
    kubectl get gitrepositories,kustomizations,hr,po -A
