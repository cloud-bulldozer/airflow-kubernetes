FROM apache/airflow:latest 
USER root

RUN apt update
RUN apt install -y ansible git

USER airflow