
.PHONY: create-github-pat-secret deploy-arc-runner install-cert-manager-crds install-cert-manager arc-deps
# Install cert-manager CRDs
install-cert-manager-crds:
	kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.crds.yaml

# Install cert-manager via Helm
install-cert-manager: install-cert-manager-crds
	kubectl create namespace cert-manager || true
	helm repo add jetstack https://charts.jetstack.io || true
	helm repo update
	helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.14.4

# Install all ARC dependencies
arc-deps: install-cert-manager

# Create Kubernetes secret for GitHub PAT (named controller-manager)
create-github-pat-secret:
	kubectl create ns arc-system || true
	kubectl delete secret controller-manager --namespace=arc-system || true
	kubectl create secret generic controller-manager --from-literal=github_token=$$GITHUB_PAT --namespace=arc-system

# Deploy a sample ARC RunnerDeployment
deploy-arc-runner:
	kubectl apply -f arc-runnerdeployment.yaml
# Makefile for local GitOps demo with Minikube, ARC, JFrog, ArgoCD, Kargo

MINIKUBE_PROFILE ?= gitops-demo
K8S_NAMESPACE ?= gitops-demo
DEMO_IMAGE ?= demo-app:latest
DOCKER_REGISTRY ?= localhost:5000

.PHONY: minikube-up minikube-down deploy-arc deploy-jfrog deploy-argocd deploy-kargo deploy-all demo-build demo-push

minikube-up:
	minikube start -p $(MINIKUBE_PROFILE) --driver=docker --cpus=4 --memory=6g --addons=ingress

minikube-down:
	minikube delete -p $(MINIKUBE_PROFILE)

deploy-arc: arc-deps
	kubectl create ns arc-system || true
	# Install GitHub Actions Runner Controller (ARC)
	helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
	helm repo update
	helm upgrade --install arc actions-runner-controller/actions-runner-controller \
	  --namespace arc-system --set syncPeriod=1m

deploy-jfrog:
	kubectl create ns jfrog || true
	# Install JFrog Artifactory OSS (for demo, using Helm)
	helm repo add jfrog https://charts.jfrog.io
	helm repo update
	helm upgrade --install artifactory jfrog/artifactory-oss \
	  --namespace jfrog --set artifactory.service.type=ClusterIP

deploy-argocd:
	kubectl create ns argocd || true
	# Install ArgoCD
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	# Patch ArgoCD server to use Ingress
	kubectl apply -f ../argocd-ingress.yaml

deploy-kargo:
	kubectl create ns kargo || true
	# Install Kargo (assuming Helm chart is available)
	helm repo add kargo https://charts.kargo.com
	helm repo update
	helm upgrade --install kargo kargo/kargo --namespace kargo

deploy-all: minikube-up deploy-arc deploy-jfrog deploy-argocd deploy-kargo

# Demo app build and push

demo-build:
	docker build -t $(DEMO_IMAGE) ./demo-app

demo-push:
	# Make sure local registry is running (e.g., via Minikube or Docker)
	docker tag $(DEMO_IMAGE) $(DOCKER_REGISTRY)/$(DEMO_IMAGE)
	docker push $(DOCKER_REGISTRY)/$(DEMO_IMAGE)
