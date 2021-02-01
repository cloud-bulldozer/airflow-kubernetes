IMAGE_NAME=airflow-ansible
QUAY_ACCOUNT=quay.io/keithwhitley4
IMAGE_BUILDER ?= podman
AIRFLOW_VERSION ?= latest
IMAGE_TAG ?= $(AIRFLOW_VERSION)

.PHONY: all
all: build push

.PHONY: build
build:
	$(IMAGE_BUILDER) build images/airflow-ansible --build-arg AIRFLOW_VERSION=$(AIRFLOW_VERSION) -t $(QUAY_ACCOUNT)/$(IMAGE_NAME):$(IMAGE_TAG)

push:
	$(IMAGE_BUILDER) push $(QUAY_ACCOUNT)/$(IMAGE_NAME):$(IMAGE_TAG)
