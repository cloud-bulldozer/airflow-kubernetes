#!/bin/bash
set -ex

create_login_secrets(){
    echo {{ params.KUBEUSER }}; echo {{ params.KUBEPASSWORD }}; echo {{ params.KUBEURL }};
    ls ~/.kube/
    rm -f ~/.kube/config 

    oc login -u {{ params.KUBEUSER }} -p {{ params.KUBEPASSWORD }} {{ params.KUBEURL }}
    ls ~/.kube/
}

