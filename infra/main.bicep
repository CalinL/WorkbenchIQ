targetScope = 'subscription'

// ──────────────────────────────────────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────────────────────────────────────

@minLength(1)
@maxLength(64)
@description('Name of the azd environment (used for resource naming).')
param environmentName string

@minLength(1)
@description('Primary Azure region for all resources.')
param location string

@description('Azure OpenAI model name to deploy.')
param openAiModelName string = 'gpt-4.1'

@description('Azure OpenAI model version.')
param openAiModelVersion string = '2025-04-14'

@description('Azure OpenAI model deployment capacity (thousands of tokens per minute).')
param openAiCapacity int = 30

@description('Embedding model name to deploy (used by app for RAG).')
param embeddingModelName string = 'text-embedding-3-small'

@description('Embedding model version.')
param embeddingModelVersion string = '1'

@description('Embedding model deployment capacity (thousands of tokens per minute).')
param embeddingCapacity int = 120

@description('App Service plan SKU.')
param appServiceSkuName string = 'P0v3'

@description('Azure region for App Service (may differ from primary location due to quota).')
param appServiceLocation string = 'canadacentral'

@description('Azure AD tenant ID for Easy Auth. Leave empty to skip Easy Auth setup.')
param authTenantId string = ''

// ──────────────────────────────────────────────────────────────────────────────
// Variables
// ──────────────────────────────────────────────────────────────────────────────

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
}

// ──────────────────────────────────────────────────────────────────────────────
// Resource Group
// ──────────────────────────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// Modules
// ──────────────────────────────────────────────────────────────────────────────

module monitoring './modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    appInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    tags: tags
  }
}

module aiServices './modules/ai-services.bicep' = {
  name: 'ai-services'
  scope: rg
  params: {
    location: location
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    modelName: openAiModelName
    modelVersion: openAiModelVersion
    modelCapacity: openAiCapacity
    embeddingModelName: embeddingModelName
    embeddingModelVersion: embeddingModelVersion
    embeddingCapacity: embeddingCapacity
    tags: tags
  }
}

module storage './modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    location: location
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    containerName: 'workbenchiq-data'
    tags: tags
  }
}

module appService './modules/app-service.bicep' = {
  name: 'app-service'
  scope: rg
  params: {
    location: appServiceLocation
    tags: tags
    appServicePlanName: '${abbrs.webServerFarms}${resourceToken}'
    skuName: appServiceSkuName
    // Backend
    backendAppName: '${abbrs.webSitesAppService}api-${resourceToken}'
    // Frontend
    frontendAppName: '${abbrs.webSitesAppService}web-${resourceToken}'
    // Resource names for key lookup via existing references
    aiServicesName: aiServices.outputs.name
    openAiDeploymentName: aiServices.outputs.deploymentName
    embeddingDeploymentName: aiServices.outputs.embeddingDeploymentName
    cuMiniDeploymentName: aiServices.outputs.cuMiniDeploymentName
    storageName: storage.outputs.name
    storageContainerName: 'workbenchiq-data'
    // Monitoring
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    // Easy Auth
    authTenantId: authTenantId
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RBAC: Grant backend Managed Identity → Cognitive Services User on AIServices
// ──────────────────────────────────────────────────────────────────────────────

module backendAiRoleAssignment './modules/role-assignment.bicep' = {
  name: 'backend-ai-role'
  scope: rg
  params: {
    principalId: appService.outputs.backendPrincipalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    principalType: 'ServicePrincipal'
    resourceId: aiServices.outputs.id
  }
}

module backendStorageRoleAssignment './modules/storage-role-assignment.bicep' = {
  name: 'backend-storage-role'
  scope: rg
  params: {
    principalId: appService.outputs.backendPrincipalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
    storageAccountName: storage.outputs.name
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Outputs (consumed by azd and hooks — no secrets here)
// ──────────────────────────────────────────────────────────────────────────────

output AZURE_CONTENT_UNDERSTANDING_ENDPOINT string = aiServices.outputs.endpoint
output AZURE_CONTENT_UNDERSTANDING_USE_AZURE_AD string = 'true'
output AZURE_OPENAI_ENDPOINT string = aiServices.outputs.endpoint
output SERVICE_API_URI string = appService.outputs.backendUri
output SERVICE_WEB_URI string = appService.outputs.frontendUri
output AZURE_RESOURCE_GROUP string = rg.name
