# argo-gitops
GitOps with ArgoCD

## bootstrap a cluster
### installation via kubectl
```
# ref https://argoproj.github.io/argo-cd/getting_started/
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

