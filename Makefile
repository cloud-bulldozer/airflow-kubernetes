QUAY_ACCOUNT=quay.io/keithwhitley4
IMAGE_BUILDER ?= podman
AIRFLOW_VERSION ?= 2.1.2
AIRFLOW_PYTHON_VERSION ?= python3.8
AIRFLOW_IMAGE_TAG ?= $(AIRFLOW_VERSION)-$(AIRFLOW_PYTHON_VERSION)
IMAGE_TAG ?= $(AIRFLOW_VERSION)

BASE_IMAGE ?= $(QUAY_ACCOUNT)/airflow-base:$(IMAGE_TAG)


.PHONY: all
all: build push


build-base-image: 
	$(IMAGE_BUILDER) build images/airflow-base --build-arg AIRFLOW_IMAGE_TAG=$(AIRFLOW_IMAGE_TAG) -t $(QUAY_ACCOUNT)/airflow-base:$(IMAGE_TAG)

build-executor-image:
	$(IMAGE_BUILDER) build images/$(image) --build-arg AIRFLOW_VERSION=$(AIRFLOW_VERSION) -t $(QUAY_ACCOUNT)/$(image):$(IMAGE_TAG)


.PHONY: build
build-images:
	$(IMAGE_BUILDER) build images/airflow-ansible --build-arg AIRFLOW_VERSION=$(AIRFLOW_VERSION) -t $(QUAY_ACCOUNT)/$(IMAGE_NAME):$(IMAGE_TAG)

push:
	$(IMAGE_BUILDER) push $(QUAY_ACCOUNT)/$(IMAGE_NAME):$(IMAGE_TAG)
