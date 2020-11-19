FROM apache/airflow:latest 
USER root

RUN apt update
RUN apt install git
RUN yes | pip install ansible

USER airflow