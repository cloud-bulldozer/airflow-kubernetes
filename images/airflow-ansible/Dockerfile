FROM apache/airflow:latest 
USER root

RUN apt update
RUN apt install -y ansible git

COPY inventory.properties /inventory

USER airflow