// App Service Plan + Backend (Python) + Frontend (Node.js) Web Apps
// All application settings are wired automatically from sibling resources.

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

// ── Plan ─────────────────────────────────────────────────────────────────────
@description('App Service Plan name.')
param appServicePlanName string

@description('App Service Plan SKU (e.g. B1, S1, P1v3).')
param skuName string

// ── App names ────────────────────────────────────────────────────────────────
@description('Backend Web App name.')
param backendAppName string

@description('Frontend Web App name.')
param frontendAppName string

// ── Sibling resource names (used via "existing" references for key lookup) ───
@description('Azure AI Services (Foundry) resource name — serves both CU and OpenAI APIs.')
param aiServicesName string

@description('OpenAI chat deployment name (on the AIServices resource).')
param openAiDeploymentName string

@description('OpenAI embedding deployment name (on the AIServices resource).')
param embeddingDeploymentName string

@description('CU mini model deployment name (gpt-4.1-mini, also used for Ask IQ chat).')
param cuMiniDeploymentName string

@description('Storage account name.')
param storageName string

@description('Blob container name.')
param storageContainerName string

// ── Monitoring ───────────────────────────────────────────────────────────────
@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Azure AD tenant ID for Easy Auth. Empty = no Easy Auth.')
param authTenantId string = ''

// ──────────────────────────────────────────────────────────────────────────────
// Existing resource references (for key retrieval — no secrets in outputs)
// ──────────────────────────────────────────────────────────────────────────────

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aiServicesName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

// ──────────────────────────────────────────────────────────────────────────────
// Computed URLs (predictable from resource names — no circular dependency)
// ──────────────────────────────────────────────────────────────────────────────

var backendUrl = 'https://${backendAppName}.azurewebsites.net'
var frontendUrl = 'https://${frontendAppName}.azurewebsites.net'

// ──────────────────────────────────────────────────────────────────────────────
// App Service Plan
// ──────────────────────────────────────────────────────────────────────────────

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true // Linux
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Backend Web App (Python / FastAPI)
// ──────────────────────────────────────────────────────────────────────────────

resource backendApp 'Microsoft.Web/sites@2023-12-01' = {
  name: backendAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'api' })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      alwaysOn: true
      appCommandLine: 'bash scripts/startup.sh'
      ftpsState: 'Disabled'
      appSettings: [
        // ── Azure AI Content Understanding (Azure AD auth via Managed Identity) ──
        { name: 'AZURE_CONTENT_UNDERSTANDING_ENDPOINT', value: aiServices.properties.endpoint }
        { name: 'AZURE_CONTENT_UNDERSTANDING_USE_AZURE_AD', value: 'true' }
        { name: 'AZURE_CONTENT_UNDERSTANDING_ANALYZER_ID', value: 'prebuilt-documentSearch' }
        { name: 'AZURE_CONTENT_UNDERSTANDING_API_VERSION', value: '2025-11-01' }
        // ── Azure OpenAI (same AIServices resource, Azure AD auth) ──
        { name: 'AZURE_OPENAI_ENDPOINT', value: aiServices.properties.endpoint }
        { name: 'AZURE_OPENAI_DEPLOYMENT_NAME', value: openAiDeploymentName }
        { name: 'AZURE_OPENAI_MODEL_NAME', value: 'gpt-4.1' }
        { name: 'AZURE_OPENAI_API_VERSION', value: '2024-10-21' }
        { name: 'AZURE_OPENAI_USE_AZURE_AD', value: 'true' }
        // ── Chat mini model (Ask IQ feature) ──
        { name: 'AZURE_OPENAI_CHAT_DEPLOYMENT_NAME', value: cuMiniDeploymentName }
        { name: 'AZURE_OPENAI_CHAT_MODEL_NAME', value: 'gpt-4.1-mini' }
        // ── Storage (Azure Blob via Managed Identity) ──
        { name: 'STORAGE_BACKEND', value: 'azure_blob' }
        { name: 'AZURE_STORAGE_ACCOUNT_NAME', value: storageAccount.name }
        { name: 'AZURE_STORAGE_USE_MANAGED_IDENTITY', value: 'true' }
        { name: 'AZURE_STORAGE_CONTAINER_NAME', value: storageContainerName }
        // ── Embedding (for RAG when enabled) ──
        { name: 'EMBEDDING_DEPLOYMENT', value: embeddingDeploymentName }
        { name: 'EMBEDDING_MODEL', value: 'text-embedding-3-small' }
        // ── CORS / Frontend ──
        { name: 'FRONTEND_URL', value: frontendUrl }
        { name: 'CORS_ORIGINS', value: frontendUrl }
        // ── Monitoring ──
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        // ── Build flag ──
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
      ]
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Frontend Web App (Node.js / Next.js standalone)
// ──────────────────────────────────────────────────────────────────────────────

resource frontendApp 'Microsoft.Web/sites@2023-12-01' = {
  name: frontendAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      alwaysOn: true
      appCommandLine: 'node server.js'
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'API_URL', value: backendUrl }
        { name: 'NEXT_PUBLIC_API_URL', value: backendUrl }
        { name: 'PORT', value: '8080' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
      ]
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Easy Auth is configured via the postprovision hook in azure.yaml using
// `az webapp auth` CLI commands, which auto-create the Entra app registration.
// Bicep authSettingsV2 requires a pre-existing clientId that can't be
// provisioned in Bicep alone.
// ──────────────────────────────────────────────────────────────────────────────

// ──────────────────────────────────────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────────────────────────────────────

output backendUri string = backendUrl
output frontendUri string = frontendUrl
output backendAppName string = backendApp.name
output backendPrincipalId string = backendApp.identity.principalId
output frontendAppName string = frontendApp.name
