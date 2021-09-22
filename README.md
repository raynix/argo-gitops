# argo-gitops
GitOps with ArgoCD

## bootstrap a cluster
### installation via kubectl
```
# ref https://argoproj.github.io/argo-cd/getting_started/
kubectl create namespace argocd

# enable istio-injection
kubectl lable ns argocd istio-injection=enabled

# install argo
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

