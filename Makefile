
# variables:
cluster = $(shell basename $$(kubectl config current-context))
account = $(shell aws sts get-caller-identity --query "Account" --output text)
version = 1.1
namespace = monitoring
region = us-east-1
include clusters/$(cluster)/config
kubectl := kubectl -n $(namespace)
aws := aws --region $(region)
repo = prometheus-docker-image
service = grafana



#placeholders:
replacements="\
s/NAMESPACE/$(namespace)/g;\
s/STORAGESIZE/$(storagesize)/g;\
s/CLUSTER/$(cluster)/g;\
s/VERSION/$(version)/g;\
s/REPO/$(repo)/g;\
s/ACCOUNT/$(account)/g;\
s/REGION/$(region)/g;\
s/SERVICE_NAME/$(service)/g;\
s/HOSTNAME/$(hostname)/g;\
s/RETENTIONPERIOD/$(retentionPeriod)/g\
"



#0. create ECR repository:
repo:
	aws ecr create-repository --repository-name $(repo) --image-tag-mutability IMMUTABLE

repo-del:
	aws ecr delete-repository --repository-name $(repo) --force




# 1. build and push prometheus image to AWS ECR:
build:
	docker build --platform linux/amd64 -t $(repo):$(version) .

login:
	aws ecr get-login-password | docker login --username AWS --password-stdin $(account).dkr.ecr.us-east-1.amazonaws.com

push: login
	docker tag $(repo):$(version) $(account).dkr.ecr.us-east-1.amazonaws.com/$(repo):$(version)
	docker push $(account).dkr.ecr.us-east-1.amazonaws.com/$(repo):$(version)



# 2. provision Prometheus:
namespace:
	@cat prometheus/namespace.yaml | sed $(replacements) | kubectl apply -f -

run2: namespace
	@cat prometheus/pvc.yaml | sed $(replacements) | kubectl apply -f -
	@cat prometheus/clusterrole.yaml | sed $(replacements) | kubectl apply -f -
	@cat prometheus/configmap.yaml | sed $(replacements) | kubectl apply -f -
	@cat prometheus/deployment.yaml | sed $(replacements) | kubectl apply -f -
	@cat prometheus/service.yaml | sed $(replacements) | kubectl apply -f -

# to port-forward Prometheus use this command:
forward-prometheus:
	@$(kubectl) port-forward $$(kubectl get pod -l app=prometheus-server -n $(namespace) -o=jsonpath="{.items[0].metadata.name}") 8080:9090
# then use this way to connect to prometheus: http://localhost:8080, in UI check Status - Target to see connected targets.

# to destroy Prometheus:
delete-prometheus: namespace
	@cat prometheus/deployment.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat prometheus/pvc.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat prometheus/configmap.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat prometheus/clusterrole.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat prometheus/service.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found



# 3. provision node-exporter:
run3:
	@cat node-exporter/daemonset.yaml | sed $(replacements) | kubectl apply -f -
	@cat node-exporter/service.yaml | sed $(replacements) | kubectl apply -f -

# to destroy node-exporter:
delete-node-exporter:
	@cat node-exporter/daemonset.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat node-exporter/service.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found



# 4. provision kube-state-metrics:
run4:
	@cat kube-state-metrics/clusterrole.yaml | sed $(replacements) | kubectl apply -f -
	@cat kube-state-metrics/sa.yaml | sed $(replacements) | kubectl apply -f -
	@cat kube-state-metrics/clusterrolebind.yaml | sed $(replacements) | kubectl apply -f -
	@cat kube-state-metrics/deployment.yaml | sed $(replacements) | kubectl apply -f -
	@cat kube-state-metrics/service.yaml | sed $(replacements) | kubectl apply -f -

# to destroy kube-state-metrics:
delete-kube-state-metrics:
	@cat kube-state-metrics/clusterrole.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat kube-state-metrics/clusterrolebind.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat kube-state-metrics/sa.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat kube-state-metrics/deployment.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat kube-state-metrics/service.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found


# 5. provision Grafana:
run5:
	@cat grafana/grafana-datasource-config.yaml | sed $(replacements) | kubectl apply -f -
	@cat grafana/deployment.yaml | sed $(replacements) | kubectl apply -f -
	@cat grafana/service.yaml | sed $(replacements) | kubectl apply -f -

# to port-forward Grafana use this command:
forward-grafana:
	@$(kubectl) port-forward $$(kubectl get pod -l app=grafana -n $(namespace) -o=jsonpath="{.items[0].metadata.name}") 3000
# then use this way to connect to grafana: http://localhost:3000, login with admin or another user.

#to delete Grafana:
delete-grafana:
	@cat grafana/grafana-datasource-config.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat grafana/deployment.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found
	@cat grafana/service.yaml | sed $(replacements) | kubectl delete -f - --ignore-not-found

# Grafana uses already created ingress controller, which is a MUST for ingress.
# incase you need to create ingress-controller:
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml



# 6. provision and manage secrets:
inject-secrets:
	@chamber-of-secrets/k8s-inject-secrets $(service) $(namespace) ./secrets

create-secrets:
	@chamber-of-secrets/k8s-create-secrets $(service) ./secrets

# update-secrets:
# 	@chamber-of-secrets/k8s-update-secrets $(service) ./secrets

get-secrets:
	aws secretsmanager get-secret-value --secret-id $(service)-user
	aws secretsmanager get-secret-value --secret-id $(service)-admin

# to delete secrets on aws and k8s:
delete-secrets:
	aws secretsmanager delete-secret --secret-id $(service)-user --force-delete-without-recovery --region $(region)
	aws secretsmanager delete-secret --secret-id $(service)-admin --force-delete-without-recovery --region $(region)
	kubectl delete secrets $(service)-admin -n $(namespace)
	kubectl delete secrets $(service)-admin -n $(namespace)


# 7. provision Alertmanager:
run7:
	@cat kubernetes-alert-manager/AlertManagerConfigmap.yaml | sed $(replacements) | kubectl apply -f -
	@cat kubernetes-alert-manager/AlertTemplateConfigMap.yaml | sed $(replacements) | kubectl apply -f -
	@cat kubernetes-alert-manager/Deployment.yaml | sed $(replacements) | kubectl apply -f -
	@cat kubernetes-alert-manager/Service.yaml | sed $(replacements) | kubectl apply -f -