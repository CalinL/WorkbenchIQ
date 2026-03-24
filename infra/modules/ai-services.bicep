// Unified Azure AI Services (Foundry) resource.
// Provides Content Understanding + OpenAI APIs from a single endpoint.

@description('Azure region.')
param location string

@description('Resource name.')
param name string

@description('Resource tags.')
param tags object = {}

// ── OpenAI model deployment parameters ───────────────────────────────────────

@description('Chat/completion model name (e.g. gpt-4.1).')
param modelName string

@description('Chat/completion model version.')
param modelVersion string

@description('Chat/completion model capacity (TPM in thousands).')
param modelCapacity int

@description('Embedding model name (app RAG).')
param embeddingModelName string

@description('Embedding model version.')
param embeddingModelVersion string

@description('Embedding model capacity (TPM in thousands).')
param embeddingCapacity int

// ── Content Understanding model parameters (CU prebuilt analyzers) ───────────

@description('CU mini model name.')
param cuMiniModelName string = 'gpt-4.1-mini'

@description('CU mini model version.')
param cuMiniModelVersion string = '2025-04-14'

@description('CU mini model capacity (TPM in thousands).')
param cuMiniCapacity int = 30

@description('CU embedding model name (text-embedding-3-large required by CU).')
param cuEmbeddingModelName string = 'text-embedding-3-large'

@description('CU embedding model version.')
param cuEmbeddingModelVersion string = '1'

@description('CU embedding model capacity (TPM in thousands).')
param cuEmbeddingCapacity int = 120

// ── Resource ─────────────────────────────────────────────────────────────────

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  kind: 'AIServices'
  tags: tags
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    apiProperties: {}
  }
}

// ── OpenAI model deployments (on the same resource) ─────────────────────────

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: modelName
  sku: {
    name: 'Standard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: embeddingModelName
  dependsOn: [chatDeployment] // serialise to avoid concurrent deployment conflicts
  sku: {
    name: 'Standard'
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
  }
}

// ── Content Understanding model deployments ──────────────────────────────────

resource cuMiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: cuMiniModelName
  dependsOn: [embeddingDeployment]
  sku: {
    name: 'Standard'
    capacity: cuMiniCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: cuMiniModelName
      version: cuMiniModelVersion
    }
  }
}

resource cuEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: cuEmbeddingModelName
  dependsOn: [cuMiniDeployment]
  sku: {
    name: 'Standard'
    capacity: cuEmbeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: cuEmbeddingModelName
      version: cuEmbeddingModelVersion
    }
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────

output name string = aiServices.name
output endpoint string = aiServices.properties.endpoint
output id string = aiServices.id
output deploymentName string = chatDeployment.name
output embeddingDeploymentName string = embeddingDeployment.name
output cuMiniDeploymentName string = cuMiniDeployment.name
output cuEmbeddingDeploymentName string = cuEmbeddingDeployment.name
