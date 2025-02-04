param vmssName string
param extensionName string = 'LinuxCustomScriptExtension'
param forceUpdateTag int
param vmssExtensionCustomScriptUri string
param commandToExecute string = 'sh ./install.sh'

resource scriptExtension 'Microsoft.Compute/virtualMachineScaleSets/extensions@2020-06-01' = {
  name: '${vmssName}/${extensionName}'
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    forceUpdateTag: string(forceUpdateTag)
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      timestamp: forceUpdateTag
    }
    protectedSettings: {
      managedIdentity: {}
      fileUris: [
        '${vmssExtensionCustomScriptUri}/install.sh'
        '${vmssExtensionCustomScriptUri}/main'
      ]
      commandToExecute: commandToExecute
    }
  }
}
