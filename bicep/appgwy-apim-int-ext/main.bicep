param apiHostName string
param portalHostName string
param domainName string
param virtualNetworks array
param tags object
param userObjectId string
param location string
param secrets array
param externalDnsResourceGroupName string = 'external-dns-zones-rg'

var suffix = uniqueString(resourceGroup().id)
var keyVaultName = 'kv-${suffix}'
var separatedAddressprefix = split(virtualNetworks[0].subnets[3].addressPrefix, '.')
var azFirewallPrivateIpAddress = '${separatedAddressprefix[0]}.${separatedAddressprefix[1]}.${separatedAddressprefix[2]}.4'

module keyVaultModule './modules/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    name: keyVaultName
    keyVaultUserObjectId: userObjectId
    location: location
    tenantId: subscription().tenantId
  }
}

resource keyVaultSecrets 'Microsoft.KeyVault/vaults/secrets@2021-04-01-preview' = [for secret in secrets: {
  parent: keyVaultModule
  name: '${keyVaultName}/${secret.CertName}'
  properties: {
    contentType: 'application/x-pkcs12'
    value: secret.CertValue
  }
}]

module networkSecurityGroupModule './modules/nsg.bicep' = {
  name: 'nsgDeployment'
  params: {
    location: location
    appGatewayPublicIpAddress: '1.1.1.1'
    suffix: suffix
  }
}

module hubVirtualNetworkModule './modules/vnets.bicep' = {
  name: 'hubVNetDeployment'
  dependsOn: [
    userDefinedRouteModule
  ]
  params: {
    location: location
    suffix: suffix
    tags: tags
    vNet: virtualNetworks[0]
  }
}

module spokeVirtualNetworkModule './modules/vnets.bicep' = {
  name: 'spokeVNetDeployment'
  dependsOn: [
    userDefinedRouteModule
  ]
  params: {
    location: location
    suffix: suffix
    tags: tags
    vNet: virtualNetworks[1]
  }
}

module virtualNetworkPeeringModule './modules/peerings.bicep' = {
  dependsOn: [
    hubVirtualNetworkModule
    spokeVirtualNetworkModule
  ]
  name: 'vNetPeeringDeployment'
  params: {
    suffix: suffix
    vNets: virtualNetworks
  }
}

module userDefinedRouteModule './modules/udr.bicep' = {
  name: 'udrDeployment'
  params: {
    suffix: suffix
    azureFirewallPrivateIpAddress: azFirewallPrivateIpAddress
  }
}

module azureFirewallModule './modules/azfirewall.bicep' = {
  name: 'azureFirewallDeployment'
  params: {
    suffix: suffix
    firewallSubnetRef: hubVirtualNetworkModule.outputs.subnetRefs[3].id
    sourceAddressRangePrefix: [
      '10.0.0.0/8'
      '192.168.88.0/24'
    ]
  }
}

module bastionModule './modules/bastion.bicep' = {
  dependsOn: [
    azureFirewallModule
  ]
  name: 'bastionDeployment'
  params: {
    location: location
    subnetId: hubVirtualNetworkModule.outputs.subnetRefs[4].id
    suffix: suffix
  }
}

module vmModule './modules/winvm.bicep' = {
  dependsOn: [
    bastionModule
  ]
  name: 'vmDeployment'
  params: {
    adminPassword: 'M1cr0soft1234567890'
    adminUserName: 'localadmin'
    location: location
    subnetId: hubVirtualNetworkModule.outputs.subnetRefs[2].id
    suffix: suffix
    vmSize: 'Standard_D2_v3'
    windowsOSVersion: '2019-Datacenter'
  }
}

/* module appSvcModule './modules/appsvc.bicep' = {
  name: 'appSvcDeployment'
  params: {
    containerName: 'belstarr/go-web-api:v1.0'
    hubVnetId: hubVirtualNetworkModule.outputs.vnetRef
    spokeVnetId: spokeVirtualNetworkModule.outputs.vnetRef
    privateEndpointSubnetId: spokeVirtualNetworkModule.outputs.subnetRefs[3].id
    vnetIntegrationSubnetId: spokeVirtualNetworkModule.outputs.subnetRefs[2].id
    skuName: 'P3v2'
    tags: tags
  }
} */

module funcAppModule './modules/func.bicep' = {
  name: 'funcAppModule'
  params: {
    appSvcPrivateDNSZoneName: 'azurewebsites.net'
    hubVnetId: hubVirtualNetworkModule.outputs.vnetRef
    location: location
    privateEndpointSubnetId: spokeVirtualNetworkModule.outputs.subnetRefs[3].id
    spokeVnetId: spokeVirtualNetworkModule.outputs.vnetRef
    sku: 'ElasticPremium'
    skuCode: 'EP1'
    suffix: suffix
    tags: tags
    vnetIntegrationSubnetId: spokeVirtualNetworkModule.outputs.subnetRefs[4].id
  }
}

module apiManagementModule './modules/apim.bicep' = {
  dependsOn: [
    azureFirewallModule
  ]
  name: 'apimDeployment'
  params: {
    tags: tags
    location: location
    apimPrivateDnsZoneName: domainName
    hubVnetId: hubVirtualNetworkModule.outputs.vnetRef
    spokeVnetId: spokeVirtualNetworkModule.outputs.vnetRef
    webAppUrl: 'https://${funcAppModule.outputs.funcAppUrl}'
    apimSku: {
      name: 'Developer'
      capacity: 1
    }
    deployCertificates: false
    gatewayHostName: '${apiHostName}.${domainName}'
    portalHostName: '${portalHostName}.${domainName}'
    subnetId: hubVirtualNetworkModule.outputs.subnetRefs[1].id
    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyVaultUri: keyVaultModule.outputs.keyVaultUri
  }
}

module apiManagementUpdateModule './modules/apim.bicep' = {
  dependsOn: [
    apiManagementModule
  ]
  name: 'apimDeploymentUpdate'
  params: {
    tags: tags
    location: location
    apimPrivateDnsZoneName: domainName
    hubVnetId: hubVirtualNetworkModule.outputs.vnetRef
    spokeVnetId: spokeVirtualNetworkModule.outputs.vnetRef
    webAppUrl: 'https://${funcAppModule.outputs.funcAppUrl}'
    apimSku: {
      name: 'Developer'
      capacity: 1
    }
    deployCertificates: true
    gatewayHostName: '${apiHostName}.${domainName}'
    portalHostName: '${portalHostName}.${domainName}'
    subnetId: hubVirtualNetworkModule.outputs.subnetRefs[1].id
    keyVaultName: keyVaultModule.outputs.keyVaultName
    keyVaultUri: keyVaultModule.outputs.keyVaultUri
  }
}

resource existingKeyVault 'Microsoft.KeyVault/vaults@2021-04-01-preview' existing = {
  name: keyVaultName
  scope: resourceGroup()
}

module applicationGatewayModule './modules/appgateway.bicep' = {
  name: 'applicationGatewayDeployment'
  params: {
    suffix: suffix
    apiHostName: '${apiHostName}.${domainName}'
    portalHostName: '${portalHostName}.${domainName}'
    apimGatewaySslCert: existingKeyVault.getSecret('api')
    apimPortalSslCert: existingKeyVault.getSecret('portal')
    frontEndPort: 443
    gatewaySku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: '1'
    }
    requestTimeOut: 180
    skuName: 'Standard'
    subnetId: hubVirtualNetworkModule.outputs.subnetRefs[0].id
  }
}

module networkSecurityGroupUpdateModule './modules/nsg.bicep' = {
  name: 'nsgUpdateDeployment'
  params: {
    location: location
    suffix: suffix
    appGatewayPublicIpAddress: applicationGatewayModule.outputs.appGwyPublicIpAddress
  }
}

/* module mySqlServer './modules/mysql.bicep' = {
  name: 'mySqlDeployment'
  params: {
    administratorLogin: 'dbadmin'
    administratorLoginPassword: 'P@ssword123'
    location: location
    suffix: suffix
  }
} */

module mySqlFlexServer './modules/mysql-flex-server.bicep' = {
  name: 'mySqlFlexServer'
  params: {
    administratorLogin: 'dbadmin'
    administratorLoginPassword: 'P@ssword123'
    mySqlDatabaseName: 'todolist'
    backupRetentionDays: 7
    location: location
    suffix: suffix
    subnetArmResourceId: spokeVirtualNetworkModule.outputs.subnetRefs[1].id
    tags: tags
  }
}

output appGwyName string = applicationGatewayModule.outputs.appGwyName
output appGwyId string = applicationGatewayModule.outputs.appGwyId
