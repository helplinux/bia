#!/bin/bash

# Script de Rollback - Projeto BIA
# Reverte o serviço ECS para a versão anterior da task definition

set -e

CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"

echo "🔄 Iniciando rollback do serviço $SERVICE..."

# Obter versão atual
CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster $CLUSTER \
    --services $SERVICE \
    --query 'services[0].taskDefinition' \
    --output text)

CURRENT_VERSION=$(echo $CURRENT_TASK_DEF | grep -o '[0-9]*$')
PREVIOUS_VERSION=$((CURRENT_VERSION - 1))

if [ $PREVIOUS_VERSION -lt 1 ]; then
    echo "❌ Erro: Não há versão anterior para rollback (versão atual: $CURRENT_VERSION)"
    exit 1
fi

PREVIOUS_TASK_DEF="$TASK_FAMILY:$PREVIOUS_VERSION"

echo "📋 Versão atual: $TASK_FAMILY:$CURRENT_VERSION"
echo "📋 Fazendo rollback para: $PREVIOUS_TASK_DEF"

# Confirmar rollback
read -p "Confirma o rollback? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Rollback cancelado"
    exit 1
fi

# Executar rollback
echo "🚀 Executando rollback..."
aws ecs update-service \
    --cluster $CLUSTER \
    --service $SERVICE \
    --task-definition $PREVIOUS_TASK_DEF \
    --output table

echo "⏳ Aguardando deployment completar..."
aws ecs wait services-stable \
    --cluster $CLUSTER \
    --services $SERVICE

echo "✅ Rollback concluído com sucesso!"
echo "🔍 Verificando status do serviço..."

aws ecs describe-services \
    --cluster $CLUSTER \
    --services $SERVICE \
    --query 'services[0].{TaskDefinition:taskDefinition,RunningCount:runningCount,DesiredCount:desiredCount,Status:status}' \
    --output table
