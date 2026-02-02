#!/bin/bash

# Deploy Simples - Projeto BIA
# Rotina de deploy com versionamento baseado em commit hash
# Não sobrepõe o deploy-ecs.sh existente

set -e

# Configurações
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Obter commit hash
get_commit_hash() {
    git rev-parse --short=7 HEAD 2>/dev/null || error "Não é um repositório Git"
}

# Verificar pré-requisitos
check_prereqs() {
    command -v aws >/dev/null || error "AWS CLI não encontrado"
    command -v docker >/dev/null || error "Docker não encontrado"
    command -v jq >/dev/null || error "jq não encontrado"
}

# Deploy principal
deploy() {
    local commit_hash=$(get_commit_hash)
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local ecr_uri="$account_id.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"
    
    log "Iniciando deploy simples..."
    log "Commit: $commit_hash"
    log "ECR: $ecr_uri:$commit_hash"
    
    # Login ECR
    log "Login no ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $account_id.dkr.ecr.$REGION.amazonaws.com
    
    # Build
    log "Build da imagem..."
    docker build -t $ecr_uri:$commit_hash -t $ecr_uri:latest .
    
    # Push
    log "Push para ECR..."
    docker push $ecr_uri:$commit_hash
    docker push $ecr_uri:latest
    
    # Nova task definition
    log "Criando task definition..."
    local current_task=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition')
    
    local temp_file=$(mktemp)
    echo "$current_task" | jq --arg image "$ecr_uri:$commit_hash" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ' > "$temp_file"
    
    local revision=$(aws ecs register-task-definition --region $REGION --cli-input-json file://"$temp_file" --query 'taskDefinition.revision' --output text)
    rm -f "$temp_file"
    
    # Update service
    log "Atualizando serviço..."
    aws ecs update-service --region $REGION --cluster $CLUSTER --service $SERVICE --task-definition $TASK_FAMILY:$revision >/dev/null
    
    success "Deploy concluído!"
    success "Versão: $commit_hash"
    success "Task Definition: $TASK_FAMILY:$revision"
}

# Análise pré-deploy
analyze() {
    local commit_hash=$(get_commit_hash)
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    
    echo "=== ANÁLISE PRÉ-DEPLOY ==="
    echo "Commit Hash: $commit_hash"
    echo "ECR Repo: $account_id.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"
    echo "Cluster: $CLUSTER"
    echo "Service: $SERVICE"
    echo "Task Family: $TASK_FAMILY"
    echo ""
    
    # Verificar se ECR repo existe
    if aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION >/dev/null 2>&1; then
        success "ECR repository existe"
    else
        error "ECR repository '$ECR_REPO' não encontrado"
    fi
    
    # Verificar cluster
    if aws ecs describe-clusters --clusters $CLUSTER --region $REGION --query 'clusters[0].status' --output text | grep -q ACTIVE; then
        success "Cluster ECS ativo"
    else
        error "Cluster '$CLUSTER' não encontrado ou inativo"
    fi
    
    # Verificar service
    if aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].status' --output text | grep -q ACTIVE; then
        success "Service ECS ativo"
    else
        error "Service '$SERVICE' não encontrado ou inativo"
    fi
    
    # Verificar task definition
    if aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION >/dev/null 2>&1; then
        success "Task definition existe"
    else
        error "Task definition '$TASK_FAMILY' não encontrada"
    fi
    
    echo ""
    echo "✅ Tudo pronto para deploy!"
    echo "Execute: ./deploy-simple.sh deploy"
}

# Main
case "${1:-analyze}" in
    analyze)
        check_prereqs
        analyze
        ;;
    deploy)
        check_prereqs
        deploy
        ;;
    *)
        echo "Uso: $0 [analyze|deploy]"
        echo "  analyze - Analisa pré-requisitos (padrão)"
        echo "  deploy  - Executa o deploy"
        exit 1
        ;;
esac
