IMAGE_NAME=airflow
IMAGE_TAG=latest
QUAY_ACCOUNT=quay.io/keithwhitley4
IMAGE_BUILDER=podman

.PHONY: all
all: build push

.PHONY: build
build:
	$(IMAGE_BUILDER) build . -t $(QUAY_ACCOUNT)/$(IMAGE_NAME):$(IMAGE_TAG)

push:
	$(IMAGE_BUILDER) push $(QUAY_ACCOUNT)/$(IMAGE_NAME):$(IMAGE_TAG)
