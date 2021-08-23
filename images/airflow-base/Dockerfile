ARG AIRFLOW_IMAGE_TAG=latest
FROM apache/airflow:${AIRFLOW_IMAGE_TAG} 
USER root

RUN curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl
RUN ln -s /bin/bash /usr/bin/bash

RUN apt update -y
RUN apt install jq git build-essential uuid-runtime gettext-base xz-utils sshpass -y

USER airflow