// Scoped RBAC role assignment on a specific resource.

@description('Principal (identity) to assign the role to.')
param principalId string

@description('Built-in role definition ID (GUID only, not full resource ID).')
param roleDefinitionId string

@description('Principal type.')
@allowed(['ServicePrincipal', 'User', 'Group'])
param principalType string = 'ServicePrincipal'

@description('Target resource ID to scope the assignment to.')
param resourceId string

// Scope the assignment to the specific resource
resource targetResource 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: last(split(resourceId, '/'))
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(targetResource.id, principalId, roleDefinitionId)
  scope: targetResource
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: principalType
  }
}
