# Caches are stored in this hashtable.
# The key is the cache name, and the value is another hashtable.
# The inner hashtable has the label as key, and the cached value as value.
$Script:CachedCommandCacheStore = @{}


$moduleFolderPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent


$culture = 'en-US'
if ( $PSUICulture -and ($PSUICulture -ne '') ) {
    $localizationFolderPath = Join-Path -Path $moduleFolderPath -ChildPath $PSUICulture
    $localizationFilePath = Join-Path -Path $localizationFolderPath -ChildPath 'localized.psd1'

    if (Test-Path -Path $localizationFilePath -PathType Leaf) {
        $culture = $PSUICulture
    }
}
$importLocalizedDataParams = @{
    BindingVariable = 'localized'
    Filename        = 'localized.psd1'
    BaseDirectory   = $moduleFolderPath
    UICulture       = $culture
}
Import-LocalizedData @importLocalizedDataParams


function Invoke-CachedCommand {
    [CmdletBinding(DefaultParametersetName = 'NoExpiration')]
    param(
        [Parameter(Mandatory)]
        [string] $Cache
        ,
        [Parameter(Mandatory)]
        [string] $Label
        ,
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
        ,
        [Parameter(ParameterSetName = 'Expiration')]
        [timespan] $AbsoluteExpiration = 0
        ,
        [Parameter(ParameterSetName = 'Expiration')]
        [timespan] $SlidingExpiration = 0
        ,
        [Parameter(ParameterSetName = 'Expiration')]
        [long] $MaxHitCount = 0
        ,
        [switch] $SkipNullValues
        ,
        [switch] $Force
    )

    try {
        $callerErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        # From a performance perspective calls to Write-Verbose are expensive
        # Creating a boolean to use for testing if we can skip the calls
        $shouldWriteVerbose = $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue

        # Always get the current time as we need it either when invoking
        # the scriptblock, or when comparing cache age etc.
        $timeStamp = [datetime]::UtcNow

        # Get hashcode of scriptblock
        $scriptBlockHashCode = $ScriptBlock.ToString().Trim().GetHashCode()

        # Create cache if it does not exist
        if ( -not $Script:CachedCommandCacheStore.ContainsKey($Cache) ) {
            $Script:CachedCommandCacheStore[$Cache] = @{}
        }

        $cacheData = $Script:CachedCommandCacheStore[$Cache]
        $ShouldInvokeScriptBlock = $false

        if ($Force.IsPresent) {
            $ShouldInvokeScriptBlock = $true
            if ($shouldWriteVerbose) { Write-Verbose -Message $localized.ForceSpecified }
        } else {
            $cachedValue = $cacheData[$Label]

            $cachedValueNotFound = $null -eq $cachedValue

            if ($cachedValueNotFound) {
                $ShouldInvokeScriptBlock = $true
            } else {
                switch ($cachedValue) {
                    { $cachedValue.ScriptBlockHashCode -ne $scriptBlockHashCode } {
                        $ShouldInvokeScriptBlock = $true
                        if ($shouldWriteVerbose) { Write-Verbose -Message $localized.ScriptBlockChanged }
                        break
                    }

                    { $PSBoundParameters.ContainsKey('AbsoluteExpiration') -and ($timeStamp - $cachedValue.CreationTimeUtc) -gt $AbsoluteExpiration } {
                        $ShouldInvokeScriptBlock = $true
                        if ($shouldWriteVerbose) { Write-Verbose -Message $localized.AbsoluteExpirationExceeded }
                        break
                    }

                    { $PSBoundParameters.ContainsKey('SlidingExpiration') -and ($timeStamp - $cachedValue.LastAccessTimeUtc) -gt $SlidingExpiration } {
                        $ShouldInvokeScriptBlock = $true
                        if ($shouldWriteVerbose) { Write-Verbose -Message $localized.SlidingExpirationExceeded }
                        break
                    }

                    { $PSBoundParameters.ContainsKey('MaxHitCount') -and ($cachedValue.HitCount -ge $MaxHitCount) } {
                        $ShouldInvokeScriptBlock = $true
                        if ($shouldWriteVerbose) { Write-Verbose -Message $localized.MaxHitCountExceeded }
                        break
                    }
                }
            }
        }

        if ($ShouldInvokeScriptBlock) {
            if ($shouldWriteVerbose) { Write-Verbose -Message $localized.InvokingScriptBlock }

            try {
                $scriptBlockOutput = $ScriptBlock.Invoke()
            } catch {
                throw $_.Exception.InnerException
            }

            $cachedValue = [pscustomobject]@{
                Value               = $scriptBlockOutput
                ScriptBlockHashCode = $scriptBlockHashCode
                CreationTimeUtc     = $timeStamp
                LastAccessTimeUtc   = $timeStamp
                HitCount            = [long]0
            }

            $cacheNullValues = $SkipNullValues.IsPresent -eq $false
            if ($scriptBlockOutput -or $cacheNullValues) {
                $cacheData[$Label] = $cachedValue
            }
        } else {
            if ($shouldWriteVerbose) { Write-Verbose -Message $localized.ReturningCachedValue }
        }

        $cachedValue.LastAccessTimeUtc = $timeStamp
        $cachedValue.HitCount++
        $cachedValue.Value
    } catch {
        Write-Error -ErrorRecord $_ -ErrorAction $callerErrorActionPreference
    }
}


function Clear-CachedCommand {
    [CmdletBinding(DefaultParameterSetName = 'SingleLabel')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'AllLabels')]
        [Parameter(Mandatory, ParameterSetName = 'SingleLabel')]
        [string] $Cache
        ,
        [Parameter(Mandatory, ParameterSetName = 'SingleLabel')]
        [string] $Label
        ,
        [Parameter(Mandatory, ParameterSetName = 'AllLabels')]
        [switch] $AllLabels
        ,
        [Parameter(Mandatory, ParameterSetName = 'AllCaches')]
        [switch] $AllCaches
    )

    try {
        $callerErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        $throwCacheException = $false
        $throwLabelException = $false

        if ($PSBoundParameters.ContainsKey('Cache') ) {
            if ( $Script:CachedCommandCacheStore.ContainsKey($Cache) ) {
                $cacheData = $Script:CachedCommandCacheStore[$Cache]

                if ($PSBoundParameters.ContainsKey('Label') ) {
                    if ( -not $cacheData.ContainsKey($Label) ) {
                        $throwLabelException = $true
                    }
                }
            } else {
                $throwCacheException = $true
            }
        }

        if ($throwCacheException) {
            $message = $localized.CacheNotFoundException -f $Cache
            throw [System.Management.Automation.ItemNotFoundException]::new($message)
        }

        if ($throwLabelException) {
            $message = $localized.LabelNotFoundException -f $Label, $Cache
            throw [System.Management.Automation.ItemNotFoundException]::new($message)
        }

        switch ($PSCmdlet.ParameterSetName) {
            'SingleLabel' {
                $Script:CachedCommandCacheStore[$Cache].Remove($Label)
                break
            }

            'AllLabels' {
                $Script:CachedCommandCacheStore.Remove($Cache)
                break
            }

            'AllCaches' {
                $Script:CachedCommandCacheStore.Clear()
                break
            }
        }
    } catch {
        Write-Error -ErrorRecord $_ -ErrorAction $callerErrorActionPreference
    }
}


function Show-CachedCommand {
    param(
        [string[]] $Cache = ''
        ,
        [string[]] $Label = ''
        ,
        [switch] $ValueOnly
    )

    if ($PSBoundParameters.ContainsKey('Cache')) {
        $cacheKeys = $Script:CachedCommandCacheStore.get_Keys().Where({ $Cache -contains $_ })
    } else {
        $cacheKeys = $Script:CachedCommandCacheStore.get_Keys()
    }

    foreach ($cacheKey in $cacheKeys | Sort-Object) {

        $cacheData = $Script:CachedCommandCacheStore[$cacheKey]

        if ($PSBoundParameters.ContainsKey('Label')) {
            $labelKeys = $cacheData.get_Keys().Where({ $Label -contains $_ })
        } else {
            $labelKeys = $cacheData.get_Keys()
        }

        foreach ($labelKey in $labelKeys | Sort-Object) {
            if ($ValueOnly.IsPresent) {
                $cacheData[$labelKey].Value
            } else {
                [pscustomobject]@{
                    Cache = $cacheKey
                    Label = $labelKey
                    Value = $cacheData[$labelKey].Value
                }
            }
        }
    }
}
#endregion
