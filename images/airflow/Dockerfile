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

RUN curl -L $(curl -s https://api.github.com/repos/cloud-bulldozer/kube-burner/releases/latest | jq -r '.assets | map(select(.name | test("linux-x86_64"))) | .[0].browser_download_url') | tar xz -C /usr/bin kube-burner 
RUN curl -L $(curl -s https://api.github.com/repos/cloud-bulldozer/k8s-netperf/releases/latest | jq -r '.assets | map(select(.name | test("Linux.*x86_64"))) | .[0].browser_download_url') | tar xz -C /usr/bin k8s-netperf
RUN curl -L $(curl -s https://api.github.com/repos/cloud-bulldozer/ingress-perf/releases/latest | jq -r '.assets | map(select(.name | test("Linux.*x86_64"))) | .[0].browser_download_url') | tar xz -C /usr/bin ingress-perf
USER airflow
