ARG BASE_IMAGE=quay.io/cloud-bulldozer/airflow:2.3.0
FROM ${BASE_IMAGE}
USER root
RUN apt install bc
USER airflow
RUN yes | pip install ansible netaddr
