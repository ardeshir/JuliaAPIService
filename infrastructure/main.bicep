param environmentType string
param location string
param storageAccountSku string
param vnetIntegrationSubnetId string

/*
This module contains the IaC for deploying the Premium function app
*/

/// Just a single minimum instance to start with and max scaling of 3 for dev, 5 for prd ///
var minimumElasticSize = 1
var maximumElasticSize = ((environmentType == 'prod') ? 5 : 3)
var name = 'nlp'
var functionAppName = 'function-app-${name}-${environmentType}'

/// Storage account for service ///
resource functionAppStorage 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: 'st4functionapp${name}${environmentType}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    allowBlobPublicAccess: false
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

/// Premium app plan for the service ///
resource servicePlanfunctionApp 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: 'plan-${name}-function-app-${environmentType}'
  location: location
  kind: 'linux'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
  }
  properties: {
    reserved: true
    targetWorkerCount: minimumElasticSize
    maximumElasticWorkerCount: maximumElasticSize
    elasticScaleEnabled: true
    isSpot: false
    zoneRedundant: ((environmentType == 'prd') ? true : false)
  }
}

// Create log analytics workspace
resource logAnalyticsWorkspacefunctionApp 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: '${name}-functionapp-loganalytics-workspace-${environmentType}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // Standard
    }
  }
}

/// Log analytics workspace insights ///
resource applicationInsightsfunctionApp 'Microsoft.Insights/components@2020-02-02' = {
  name: 'application-insights-${name}-function-${environmentType}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    Request_Source: 'rest'
    RetentionInDays: 30
    WorkspaceResourceId: logAnalyticsWorkspacefunctionApp.id
  }
}

// App service containing the workflow runtime ///
resource sitefunctionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    clientAffinityEnabled: false
    httpsOnly: true
    serverFarmId: servicePlanfunctionApp.id
    siteConfig: {
      linuxFxVersion: 'python|3.9'
      minTlsVersion: '1.2'
      pythonVersion: '3.9'
      use32BitWorkerProcess: true
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionAppStorage.name};AccountKey=${listKeys(functionAppStorage.id, '2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionAppStorage.name};AccountKey=${listKeys(functionAppStorage.id, '2019-06-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: 'app-${toLower(name)}-functionservice-${toLower(environmentType)}a6e9'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsightsfunctionApp.properties.InstrumentationKey
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~2'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsfunctionApp.properties.ConnectionString
        }
        {
          name: 'ENV'
          value: toUpper(environmentType)
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }

  /// VNET integration so flows can access storage and queue accounts ///
  resource vnetIntegration 'networkConfig@2022-03-01' = {
    name: 'virtualNetwork'
    properties: {
      subnetResourceId: vnetIntegrationSubnetId
      swiftSupported: true
    }
  }
}

/// Outputs for creating access policies ///
output functionAppName string = sitefunctionApp.name
output functionAppManagedIdentityId string = sitefunctionApp.identity.principalId
