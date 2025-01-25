# argo-gitops
GitOps with ArgoCD

## What is this for
This is the repository I used to manage my home lab built with Kubernetes running on old laptops
and gaming PCs. In the beginning this is just a pile of YAMLs and Helm templates. Gradually it's
getting better organised and trasitioned to newer technologies such as Istio, ArgoCD Application Set,
Jsonnet and Tanka. This repo is an example of Continuous Delivery using ArgoCD and git-ops pattern.

I host [my own blog](https://raynix.info) along with some other tools and stuff I built in my
home lab.

## To bootstrap a cluster
### installation via kubectl
```
# ref https://argoproj.github.io/argo-cd/getting_started/
kubectl create namespace argocd

# install argo
kubectl apply -k ./argocd

# check if ArgoCD is ready
kubectl get pods -n argocd

# access to ArgoCD UI via localhost before gateway setup
kubectl port-forward -n argocd argocd-server-xxxx 8080:8080
```
