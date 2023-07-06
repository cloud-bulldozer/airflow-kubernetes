ARG BASE_IMAGE=quay.io/cloud-bulldozer/airflow:latest
# Hypershift Compilation
FROM golang:1.19 AS hypershift
RUN git clone --single-branch --branch main https://github.com/openshift/hypershift --depth=1
WORKDIR hypershift
RUN make build
# Runtime image
FROM ${BASE_IMAGE} as runtime
USER root
RUN curl -L https://go.dev/dl/go1.18.2.linux-amd64.tar.gz -o go1.18.2.linux-amd64.tar.gz
RUN tar -C /usr/local -xzf go1.18.2.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin
RUN apt update -y
RUN env ACCEPT_EULA=Y apt upgrade -y
RUN apt install jq unzip bsdmainutils build-essential libncurses5-dev zlib1g-dev libnss3-dev libgdbm-dev libssl-dev libsqlite3-dev libffi-dev libreadline-dev curl libbz2-dev -y
RUN curl -L $(curl -s https://api.github.com/repos/openshift/rosa/releases/latest | jq -r ".assets[] | select(.name == \"rosa-linux-amd64\") | .browser_download_url") --output /usr/local/bin/rosa
RUN curl -L $(curl -s https://api.github.com/repos/openshift-online/ocm-cli/releases/latest | jq -r ".assets[] | select(.name == \"ocm-linux-amd64\") | .browser_download_url") --output /usr/local/bin/ocm
RUN chmod +x /usr/local/bin/rosa && chmod +x /usr/local/bin/ocm
RUN /usr/local/bin/rosa download openshift-client
RUN tar xzvf openshift-client-linux.tar.gz
RUN mv oc kubectl /usr/local/bin/
RUN echo "export CLOUDSDK_PYTHON=python3.9" >> /home/airflow/.bashrc
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg  add - && apt-get update -y && apt-get install google-cloud-sdk -y
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash
RUN echo "airflow ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
COPY --from=hypershift /go/hypershift/bin/hypershift /go/hypershift/bin/hypershift-operator /go/hypershift/bin/control-plane-operator /usr/local/bin/
RUN cd /usr/local/bin && ln -s control-plane-operator ignition-server && ln -s control-plane-operator konnectivity-socks5-proxy && ln -s control-plane-operator availability-prober && ln -s control-plane-operator token-minter
WORKDIR /opt/airflow/
USER airflow
RUN python3 -m pip install --upgrade pip || true
RUN yes | pip3 install openshift --upgrade || true
