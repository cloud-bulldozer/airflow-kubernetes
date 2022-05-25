ARG BASE_IMAGE=quay.io/cloud-bulldozer/airflow:2.3.1
FROM ${BASE_IMAGE}
USER root
RUN apt install bc -y
USER airflow
RUN yes | pip install ansible netaddr
