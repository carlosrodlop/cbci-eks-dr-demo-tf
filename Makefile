.DEFAULT_GOAL 	:= alpha_primary
SHELL         	:= /bin/bash
MAKEFLAGS     	+= --no-print-directory
DEBUG			:= true
DEBUG_FILE		:= terraform.logs
DIR_MAKE    	:= $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DIR_ENV			:= $(DIR_MAKE)/env
DIR_ROOT		:= $(DIR_MAKE)/root

BACKUP_SQUED_NAME:=cbci-dr
BACKUP_FREQ:=15m
BACKUP_TTL:=1h
BACKUP_EXCLUDE:=pods,events,events.events.k8s.io,targetgroupbindings.elbv2.k8s.aws

CI_NAMESPACE:=cbci
CI_OC_URL:=https://ci.dw22.pscbdemos.com/cjoc/
CLUSTER_PREFIX:=dw22-dr-velero

export KUBECONFIG=kubeconfig_file

ifeq ($(DEBUG),true)
	export TF_LOG=DEBUG
	export TF_LOG_PATH=$(DEBUG_FILE)
endif

define clean_debug_file
	@rm -rf $(DEBUG_FILE)
endef

define print_title
    @echo "===================================="
	@echo "$1"
	@echo "===================================="
endef

define tf_init
	$(call print_title,Init $1 Cluster)
	terraform -chdir=$(DIR_ROOT)/ci-$1 fmt
	terraform -chdir=$(DIR_ROOT)/ci-$1 init -upgrade=true
	terraform -chdir=$(DIR_ROOT)/ci-$1 validate
endef

define tf_apply_primary
	$(call clean_debug_file)
	$(call print_title,Apply Primary for Cluster $1)
	if [[ "$1" == "alpha" ]]; then terraform -chdir="$(DIR_ROOT)/ci-$1" plan -out="$(DIR_ROOT)/ci-$1/$1.primary.plan" -var primary_cluster=true -var s3_bucket_arn=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_arn) -var s3_bucket_id=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_id) -var s3_bucket_region=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_region) -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; else terraform -chdir="$(DIR_ROOT)/ci-$1" plan -out="$(DIR_ROOT)/ci-$1/$1.primary.plan" -var "primary_cluster=true" -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; fi
	terraform -chdir="$(DIR_ROOT)/ci-$1" apply "$(DIR_ROOT)/ci-$1/$1.primary.plan" 
endef

## Param: $1 = dr_cluster (alpha or beta)
define tf_apply_secondary
	$(call clean_debug_file)
	$(call print_title,Apply Secondary for Cluster $1)
	if [[ "$1" == "alpha" ]]; then terraform -chdir="$(DIR_ROOT)/ci-$1" plan -out="$(DIR_ROOT)/ci-$1/$1.secondary.plan" -var primary_cluster=false -var s3_bucket_arn=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_arn) -var s3_bucket_id=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_id) -var s3_bucket_region=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_region) -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; else terraform -chdir="$(DIR_ROOT)/ci-$1" plan -out="$(DIR_ROOT)/ci-$1/$1.secondary.plan" -var "primary_cluster=false" -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; fi
	terraform -chdir="$(DIR_ROOT)/ci-$1" apply "$(DIR_ROOT)/ci-$1/$1.secondary.plan"
endef

## Param: $1 = dr_cluster (alpha or beta)
define tf_destroy
	$(call clean_debug_file)
	$(call print_title,Destroy $1 Cluster)
	@echo "> TARGET: eks"
	if [[ "$1" == "alpha" ]]; then terraform -chdir="$(DIR_ROOT)/ci-$1" destroy -target=module.eks -var s3_bucket_arn=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_arn) -var s3_bucket_id=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_id) -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; else terraform -chdir=$(DIR_ROOT)/ci-$1 destroy -target=module.eks -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; fi
	@echo "> TARGET: vpc"
	if [[ "$1" == "alpha" ]]; then terraform -chdir="$(DIR_ROOT)/ci-$1" destroy -target=module.vpc -var s3_bucket_arn=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_arn) -var s3_bucket_id=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_id) -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; else terraform -chdir=$(DIR_ROOT)/ci-$1 destroy -target=module.vpc -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; fi
	@echo "> TARGET: REST"
	if [[ "$1" == "alpha" ]]; then terraform -chdir="$(DIR_ROOT)/ci-$1" destroy -var s3_bucket_arn=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_arn) -var s3_bucket_id=$(shell terraform -chdir=$(DIR_ROOT)/ci-beta output --raw s3_bucket_id) -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; else terraform -chdir=$(DIR_ROOT)/ci-$1 destroy -var-file="$(DIR_ENV)/ci-common.tfvars" -var-file="$(DIR_ENV)/ci-$1.tfvars" -input=false; fi
endef

define deleteBackupSchedule
	velero schedule delete $(BACKUP_SQUED_NAME) --confirm || echo "There is not an existing schedule $(BACKUP_SQUED_NAME)"
endef

define setK8sContext
	@eval $(shell terraform -chdir="$(DIR_ROOT)/ci-$1" output set_context)
endef

dr_init: beta_init beta_secondary alpha_init alpha_primary
dr_alpha_primary: beta_secondary ci_ctx_beta velero_remove_backup_schedule alpha_primary ci_ctx_alpha velero_set_backup_schedule check_availability
dr_beta_primary: alpha_secondary ci_ctx_alpha velero_remove_backup_schedule beta_primary ci_ctx_beta velero_restore_backup check_availability

define describe
	$(call setK8sContext,$1)
	$(call print_title, Terraform Outputs for $1)
	@terraform -chdir=$(DIR_ROOT)/ci-$1 output
	$(call print_title, K8s resources for $1)
	@kubectl get pod -A
	@kubectl get ing -n $(CI_NAMESPACE) cjoc 2>/dev/null || echo "====> There is not $(CI_NAMESPACE) namespace <===="
	$(call print_title, Velero Status for $1)
	@velero schedule get
	@velero backup get
endef

.PHONY: alpha_init
alpha_init: ## Init Alpha Cluster
alpha_init:
	$(call tf_init,alpha)

.PHONY: alpha_primary
alpha_primary: ## Set Alpha as Primary Cluster
alpha_primary:
	$(call tf_apply_primary,alpha)

.PHONY: alpha_secondary
alpha_secondary: ## Set Alpha as Secondary Cluster
alpha_secondary:
	$(call tf_apply_secondary,alpha)

.PHONY: alpha_destroy
alpha_destroy: ## Destroy Alpha Cluster
alpha_destroy:
	$(call tf_destroy,alpha)

.PHONY: beta_init
beta_init: ## Init Beta Cluster
beta_init:
	$(call tf_init,beta)

.PHONY: beta_primary
beta_primary: ## Set Beta as Primary Cluster
beta_primary:
	$(call tf_apply_primary,beta)

.PHONY: beta_secondary
beta_secondary: ## Set Beta as Secondary Cluster
beta_secondary:
	$(call tf_apply_secondary,beta)

.PHONY: beta_destroy
beta_destroy: ## Destroy Beta Cluster
beta_destroy:
	$(call tf_destroy,beta)

.PHONY: alpha_load_jobs
alpha_load_jobs: ## Load jobs
alpha_load_jobs:
	$(call setK8sContext,alpha)
	./scripts/load_jobs.sh

.PHONY: velero_set_backup_schedule
velero_set_backup_schedule: ## Create Backup Schedule for velero
velero_set_backup_schedule:

.PHONY: velero_remove_back
	$(deleteBackupSchedule)
	velero create schedule $(BACKUP_SQUED_NAME) --schedule='@every $(BACKUP_FREQ)' --ttl $(BACKUP_TTL) --include-namespaces $(CI_NAMESPACE) --exclude-resources $(BACKUP_EXCLUDE)

.PHONY: velero_remove_backup_schedule
velero_remove_backup_schedule: ## Remove exiting schedule for velero
velero_remove_backup_schedule:

	$(deleteBackupSchedule)

.PHONY: velero_trigger_backup
velero_trigger_backup: ## Create a puntual Backup from Schedule
velero_trigger_backup:

	$(call print_title, Velero Create Puntual Backup)
	velero backup create --from-schedule $(BACKUP_SQUED_NAME) --wait

.PHONY: velero_restore_backup
velero_restore_backup: ## Restore Backup Schedule for velero
velero_restore_backup:

	$(call print_title, Velrero Restore)
#Velero does not work to overwrite in place (https://github.com/vmware-tanzu/velero/issues/469). You have to delete everything first:
	kubectl delete --ignore-not-found --wait ns $(CI_NAMESPACE)
	velero restore create --from-schedule $(BACKUP_SQUED_NAME)

.PHONY: check_availability
check_availability:
check_availability: ## Check availability of the OC
	@until kubectl get ing -n $(CI_NAMESPACE) cjoc; do sleep 2 && echo "Waiting for ALB"; done
	@echo "ALB ready"
	@until curl -u admin:Willy -s $(CI_OC_URL)  > /dev/null; do sleep 10 && echo "Waiting for Operation Center"; done
	@echo "Operation center ready at $(CI_OC_URL)"

ci_ctx_alpha:

	$(call setK8sContext,alpha)

ci_ctx_beta:

	$(call setK8sContext,beta)

watch_alpha:

	$(call describe,alpha)

watch_beta:

	$(call describe,beta)

