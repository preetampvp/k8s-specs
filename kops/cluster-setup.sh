# TODO: Convert env. vars to arguments

if [[ -z "${BUCKET_NAME}" ]]; then
    export BUCKET_NAME=devops23-$(date +%s)
fi

BUCKET_NAME_FROM_AWS=$(aws s3api list-buckets | jq ".Buckets[] | select(.Name == \"$BUCKET_NAME\") | .Name")
if [[ -z "${BUCKET_NAME_FROM_AWS}" ]]; then
    echo "Creating an S3 bucket $BUCKET_NAME"
    aws s3api create-bucket --bucket $BUCKET_NAME --create-bucket-configuration LocationConstraint=$AWS_DEFAULT_REGION
fi

export KOPS_STATE_STORE=s3://$BUCKET_NAME

machine=$(uname)

if ! [[ "$machine" == "Linux" || "$machine" == "Darwin" ]]; then
    alias kops="docker run -it --rm \
        -v $PWD/devops23.pub:/devops23.pub \
        -v $PWD/config:/config \
        -e KUBECONFIG=/config/kubecfg.yaml \
        -e NAME=$NAME -e ZONES=$ZONES \
        -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
        -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
        -e KOPS_STATE_STORE=$KOPS_STATE_STORE \
        vfarcic/kops"
fi

extra_args=""

kops create cluster \
  --name ${NAME:-devops23.k8s.local} \
  --master-count ${MASTER_COUNT:-3} \
  --node-count ${NODE_COUNT:-1} \
  --master-size ${MASTER_SIZE:-t2.small} \
  --node-size ${NODE_SIZE:-t2.small} \
  --zones $ZONES \
  --master-zones $ZONES \
  --ssh-public-key ${SSH_PUBLIC_KEY:-cluster/devops23.pub} \
  --networking kubenet \
  --authorization RBAC \
  --yes

until kops validate cluster
do
    echo "Cluster is not yet ready. Sleeping for a while..."
    sleep 30
done

if ! [[ "$machine" == "Linux" || "$machine" == "Darwin" ]]; then
    kops export kubecfg --name ${NAME}
    export KUBECONFIG=$PWD/config/kubecfg.yaml
fi

kubectl create -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/ingress-nginx/v1.6.0.yaml

kubectl -n kube-ingress rollout status deployment ingress-nginx

if [[ ! -z "${USE_HELM}" ]]; then
    kubectl create -f helm/tiller-rbac.yml --record --save-config
    helm init --service-account tiller
    kubectl -n kube-system rollout status deploy tiller-deploy
fi

echo ""
echo "------------------------------------------"
echo ""
echo "The cluster is ready. Please execute the commands that follow to create the environment variables."
echo ""
echo "export NAME=$NAME"
echo "export BUCKET_NAME=$BUCKET_NAME"
echo "export KOPS_STATE_STORE=$KOPS_STATE_STORE"
if ! [[ "$machine" == "Linux" || "$machine" == "Darwin" ]]; then
    echo "export KUBECONFIG=$KUBECONFIG"
fi