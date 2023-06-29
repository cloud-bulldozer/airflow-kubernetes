ARG BASE_IMAGE
FROM ${BASE_IMAGE}
USER root
RUN apt install bc awscli -y
USER airflow
RUN yes | pip install ansible netaddr
