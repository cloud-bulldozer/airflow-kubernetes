ARG AIRFLOW_VERSION=latest
FROM apache/airflow:${AIRFLOW_VERSION} 
USER root

RUN apt update -y
RUN apt install jq git uuid-runtime gettext-base xz-utils -y
RUN yes | pip install ansible


RUN curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl
RUN ln -s /bin/bash /usr/bin/bash

USER airflow
RUN yes | pip install ansible