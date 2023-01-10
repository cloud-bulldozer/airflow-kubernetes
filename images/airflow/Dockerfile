ARG AIRFLOW_IMAGE_TAG=latest
FROM apache/airflow:${AIRFLOW_IMAGE_TAG} 
USER root

RUN curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl
RUN ln -s /bin/bash /usr/bin/bash

RUN apt update -y
RUN apt install jq git build-essential uuid-runtime gettext-base xz-utils sshpass -y

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6

RUN curl -L https://github.com/cloud-bulldozer/kube-burner/releases/download/v1.1/kube-burner-1.1-Linux-x86_64.tar.gz | tar xz -C /usr/bin kube-burner
RUN curl -L https://github.com/jtaleric/k8s-netperf/releases/download/v0.0.7/k8s-netperf_0.0.7_linux_amd64.tar.gz  | tar xz -C /usr/bin k8s-netperf
USER airflow
RUN pip install prometheus-api-client elasticsearch apache-airflow-providers-elasticsearch apache-airflow-providers-cncf-kubernetes --upgrade
