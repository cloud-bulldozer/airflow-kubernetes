#!/bin/bash
set -ex

create_login_secrets(){
    echo {{ params.KUBEUSER }}; echo {{ params.KUBEPASSWORD }}; echo {{ params.KUBEURL }};
    ls ~/.kube/
}

