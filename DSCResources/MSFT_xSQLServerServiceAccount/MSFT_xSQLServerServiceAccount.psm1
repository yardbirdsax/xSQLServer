Import-Module -Name (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) `
        -ChildPath 'xSQLServerHelper.psm1')

Import-Module -Name (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) `
        -ChildPath 'CommonResourceHelper.psm1')

$script:localizedData = Get-LocalizedData -ResourceName 'MSFT_xSQLServerServiceAccount'

<#
    .SYNOPSIS
        Gets the service account for the specified instance.

    .PARAMETER SQLServer
        Host name of the SQL Server to manage.

    .PARAMETER SQLInstanceName
        Name of the SQL instance.

    .PARAMETER ServiceType
        Type of service to be managed. Must be one of the following:
        DatabaseEngine, SQLServerAgent, Search, IntegrationServices, AnalysisServices, ReportingServices, SQLServerBrowser, NotificationServices.

    .PARAMETER ServiceAccount
        ** Not used in this function **
         Credential of the service account that should be used.

    .EXAMPLE
        Get-TargetResource -SQLServer $env:COMPUTERNAME -SQLInstanceName MSSQLSERVER -ServiceType SqlServer -ServiceAccount $account
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLServer,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLInstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('DatabaseEngine', 'SQLServerAgent', 'Search', 'IntegrationServices', 'AnalysisServices', 'ReportingServices', 'SQLServerBrowser', 'NotificationServices')]
        [System.String]
        $ServiceType,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $ServiceAccount
    )

    # Get the SMO Service object instance
    $serviceObject = Get-ServiceObject -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName -ServiceType $ServiceType

    # If no service was found, throw an exception
    if (-not $serviceObject)
    {
        $errorMessage = $script:localizedData.ServiceNotFound -f $ServiceType, $SQLServer, $SQLInstanceName
        New-ObjectNotFoundException -Message $errorMessage
    }

    # Local accounts will start with a '.'
    # Replace a domain of '.' with the value for $SQLServer
    $serviceAccountName = $serviceObject.ServiceAccount -ireplace '^([\.])\\(.*)$', "$SQLServer\`$2"

    # Return a hashtable with the service information
    return @{
        SQLServer = $SQLServer
        SQLInstanceName = $SQLInstanceName
        ServiceType = $serviceObject.Type
        ServiceAccount = $serviceAccountName
    }
}

<#
    .SYNOPSIS
        Tests whether the specified instance's service account is correctly configured.

    .PARAMETER SQLServer
        Host name of the SQL Server to manage.

    .PARAMETER SQLInstanceName
        Name of the SQL instance.

    .PARAMETER ServiceType
        Type of service to be managed. Must be one of the following:
        DatabaseEngine, SQLServerAgent, Search, IntegrationServices, AnalysisServices, ReportingServices, SQLServerBrowser, NotificationServices.

    .PARAMETER ServiceAccount
        Credential of the service account that should be used.

    .PARAMETER RestartService
        Determines whether the service is automatically restarted.

    .PARAMETER Force
        Forces the service account to be updated.

    .EXAMPLE
        Test-TargetResource -SQLServer $env:COMPUTERNAME -SQLInstaneName MSSQLSERVER -ServiceType SqlServer -ServiceAccount $account

#>
function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLServer,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLInstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('DatabaseEngine', 'SQLServerAgent', 'Search', 'IntegrationServices', 'AnalysisServices', 'ReportingServices', 'SQLServerBrowser', 'NotificationServices')]
        [System.String]
        $ServiceType,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter()]
        [System.Boolean]
        $RestartService,

        [Parameter()]
        [System.Boolean]
        $Force
    )

    if ($Force)
    {
        New-VerboseMessage -Message $script:localizedData.ForceServiceAccountUpdate
        return $false
    }

    # Get the current state
    $currentState = Get-TargetResource -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName -ServiceType $ServiceType -ServiceAccount $ServiceAccount
    New-VerboseMessage -Message ($script:localizedData.CurrentServiceAccount -f $currentState.ServiceAccount, $SQLServer, $SQLInstanceName)

    return ($currentState.ServiceAccount -ieq $ServiceAccount.UserName)
}

<#
    .SYNOPSIS
        Sets the SQL Server service account to the desired state.

    .PARAMETER SQLServer
        Host name of the SQL Server to manage.

    .PARAMETER SQLInstanceName
        Name of the SQL instance.

    .PARAMETER ServiceType
        Type of service to be managed. Must be one of the following:
        DatabaseEngine, SQLServerAgent, Search, IntegrationServices, AnalysisServices, ReportingServices, SQLServerBrowser, NotificationServices.

    .PARAMETER ServiceAccount
        Credential of the service account that should be used.

    .PARAMETER RestartService
        Determines whether the service is automatically restarted.

    .PARAMETER Force
        Forces the service account to be updated.

    .EXAMPLE
        Set-TargetResource -SQLServer $env:COMPUTERNAME -SQLInstaneName MSSQLSERVER -ServiceType SqlServer -ServiceAccount $account
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLServer,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLInstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('DatabaseEngine', 'SQLServerAgent', 'Search', 'IntegrationServices', 'AnalysisServices', 'ReportingServices', 'SQLServerBrowser', 'NotificationServices')]
        [System.String]
        $ServiceType,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $ServiceAccount,

        [Parameter()]
        [System.Boolean]
        $RestartService,

        [Parameter()]
        [System.Boolean]
        $Force
    )

    # Get the Service object
    $serviceObject = Get-ServiceObject -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName -ServiceType $ServiceType

    # If no service was found, throw an exception
    if (-not $serviceObject)
    {
        $errorMessage = $script:localizedData.ServiceNotFound -f $ServiceType, $SQLServer, $SQLInstanceName
        New-ObjectNotFoundException -Message $errorMessage
    }

    try
    {
        New-VerboseMessage -Message ($script:localizedData.UpdatingServiceAccount -f $ServiceAccount.UserName, $serviceObject.Name)
        $serviceObject.SetServiceAccount($ServiceAccount.UserName, $ServiceAccount.GetNetworkCredential().Password)
    }
    catch
    {
        $errorMessage = $script:localizedData.SetServiceAccountFailed -f $SQLServer, $SQLInstanceName, $_.Message
        New-InvalidOperationException -Message $errorMessage -ErrorRecord $_
    }

    if ($RestartService)
    {
        New-VerboseMessage -Message ($script:localizedData.RestartingService -f $SQLInstanceName)
        Restart-SqlService -SQLServer $SQLServer -SQLInstanceName $SQLInstanceName
    }
}

<#
    .SYNOPSIS
        Gets an SMO Service object instance for the requested service and type.

    .PARAMETER SQLServer
        Host name of the SQL Server to manage.

    .PARAMETER SQLInstanceName
        Name of the SQL instance.

    .PARAMETER ServiceType
        Type of service to be managed. Must be one of the following:
        DatabaseEngine, SQLServerAgent, Search, IntegrationServices, AnalysisServices, ReportingServices, SQLServerBrowser, NotificationServices.

    .EXAMPLE
        Get-ServiceObject -SQLServer $env:COMPUTERNAME -SQLInstanceName MSSQLSERVER -ServiceType SqlServer
#>
function Get-ServiceObject
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLServer,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SQLInstanceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('DatabaseEngine', 'SQLServerAgent', 'Search', 'IntegrationServices', 'AnalysisServices', 'ReportingServices', 'SQLServerBrowser', 'NotificationServices')]
        [System.String]
        $ServiceType
    )

    # Load the SMO libraries
    Import-SQLPSModule

    $verboseMessage = $script:localizedData.ConnectingToWmi -f $SQLServer
    New-VerboseMessage -Message $verboseMessage

    # Connect to SQL WMI
    $managedComputer = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $SQLServer

    # Change the regex pattern for a default instance
    if ($SQLInstanceName -ieq 'MSSQLServer')
    {
        $serviceNamePattern = '^MSSQLServer$'
    }
    else
    {
        $serviceNamePattern = ('\${0}$' -f $SQLInstanceName)
    }

    # Get the proper enum value
    $serviceTypeFilter = ConvertTo-ManagedServiceType -ServiceType $ServiceType

    # Get the Service object for the specified instance/type
    $serviceObject = $managedComputer.Services | Where-Object -FilterScript {
        ($_.Type -eq $serviceTypeFilter) -and ($_.Name -imatch $serviceNamePattern)
    }

    return $serviceObject
}

<#
    .SYNOPSIS
        Converts the project's standard SQL Service types to the appropriate ManagedServiceType value

    .PARAMETER ServiceType
        Type of service to be managed. Must be one of the following:
        DatabaseEngine, SQLServerAgent, Search, IntegrationServices, AnalysisServices, ReportingServices, SQLServerBrowser, NotificationServices.

    .EXAMPLE
        ConvertTo-ManagedServiceType -ServiceType 'DatabaseEngine'
#>
function ConvertTo-ManagedServiceType
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('DatabaseEngine', 'SQLServerAgent', 'Search', 'IntegrationServices', 'AnalysisServices', 'ReportingServices', 'SQLServerBrowser', 'NotificationServices')]
        [System.String]
        $ServiceType
    )

    # Map the project-specific ServiceType to a valid value from the ManagedServiceType enumeration
    switch ($ServiceType)
    {
        'DatabaseEngine'
        {
            $serviceTypeValue = 'SqlServer'
        }

        'SQLServerAgent'
        {
            $serviceTypeValue = 'SqlAgent'
        }

        'Search'
        {
            $serviceTypeValue = 'Search'
        }

        'IntegrationServices'
        {
            $serviceTypeValue = 'SqlServerIntegrationService'
        }

        'AnalysisServices'
        {
            $serviceTypeValue = 'AnalysisServer'
        }

        'ReportingServices'
        {
            $serviceTypeValue = 'ReportServer'
        }

        'SQLServerBrowser'
        {
            $serviceTypeValue = 'SqlBrowser'
        }

        'NotificationServices'
        {
            $serviceTypeValue = 'NotificationServer'
        }
    }

    return $serviceTypeValue -as [Microsoft.SqlServer.Management.Smo.Wmi.ManagedServiceType]
}
