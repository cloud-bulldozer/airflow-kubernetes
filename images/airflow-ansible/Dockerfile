ARG BASE_IMAGE=quay.io/cloud-bulldozer/airflow:latest
FROM ${BASE_IMAGE}
USER root
RUN apt install bc awscli -y
USER airflow
RUN yes | pip install ansible netaddr
