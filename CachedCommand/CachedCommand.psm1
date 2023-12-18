# Store module root
$moduleRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

# Instantiate hashtable used to store caches
$Script:CachedCommandCaches = @{}

#region LocalizedData
$culture = 'en-US'
if ( ($null -ne $PSUICulture) -and ('' -ne $PSUICulture) ) {
    if (Test-Path -Path (Join-Path -Path $moduleRoot -ChildPath $PSUICulture) -PathType Container) {
        $culture = $PSUICulture
    }
}
$importLocalizedDataParams = @{
    BindingVariable = 'localized'
    Filename        = 'localized.psd1'
    BaseDirectory   = $moduleRoot
    UICulture       = $culture
}

Import-LocalizedData @importLocalizedDataParams
#endregion LocalizedData


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
        [long] $MaxHits = 0
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
        $writeVerbose = $VerbosePreference -ne [System.Management.Automation.ActionPreference]::SilentlyContinue

        # Always get the current time as we need it either when invoking
        # the scriptblock, or when comparing cache age etc.
        $timeStamp = [datetime]::UtcNow

        # Get hashcode of scriptblock
        $scriptBlockHashCode = $ScriptBlock.ToString().Trim().GetHashCode()

        # Create cache if it does not exist
        if ( -not $Script:CachedCommandCaches.ContainsKey($Cache) ) {
            $Script:CachedCommandCaches[$Cache] = @{}
        }

        # Get the cache data
        $cacheData = $Script:CachedCommandCaches[$Cache]

        $invokeScriptBlock = $false

        if (-not $Force.IsPresent) {
            # Get cached value from the cache
            $cachedValue = $cacheData[$Label]

            if (-not $cachedValue) {
                $invokeScriptBlock = $true
            } else {
                if ($cachedValue.ScriptBlockHashCode -ne $scriptBlockHashCode) {
                    if ($writeVerbose) {
                        Write-Verbose -Message $localized.ScriptBlockChanged
                    }
                    $invokeScriptBlock = $true
                } elseif ( $PSBoundParameters.ContainsKey('AbsoluteExpiration') -and ($timeStamp - $cachedValue.CreationTimeUtc) -gt $AbsoluteExpiration ) {
                    if ($writeVerbose) {
                        Write-Verbose -Message $localized.AbsoluteExpirationExceeded
                    }
                    $invokeScriptBlock = $true
                } elseif ( $PSBoundParameters.ContainsKey('SlidingExpiration') -and ($timeStamp - $cachedValue.LastAccessTimeUtc) -gt $SlidingExpiration ) {
                    if ($writeVerbose) {
                        Write-Verbose -Message $localized.SlidingExpirationExceeded
                    }
                    $invokeScriptBlock = $true
                } elseif ( $PSBoundParameters.ContainsKey('MaxHits') -and ($cachedValue.Hits -ge $MaxHits) ) {
                    if ($writeVerbose) {
                        Write-Verbose -Message $localized.MaxHitsExceeded
                    }
                    $invokeScriptBlock = $true
                }
            }
        } else {
            if ($writeVerbose) {
                Write-Verbose -Message $localized.ForceSpecified
            }
        }

        # Invoke the scriptblock
        if ($invokeScriptBlock -or $Force.IsPresent) {
            if ($writeVerbose) {
                Write-Verbose -Message $localized.InvokingScriptBlock
            }

            try {
                $value = $ScriptBlock.Invoke()
            } catch {
                throw $_.Exception.InnerException
            }

            $cachedValue = [pscustomobject]@{
                Value               = $value
                ScriptBlockHashCode = $scriptBlockHashCode
                CreationTimeUtc     = $timeStamp
                LastAccessTimeUtc   = $timeStamp
                Hits                = [long]0
            }

            if ($value -or (-not $value -and -not $SkipNullValues.IsPresent)) {
                $cacheData[$Label] = $cachedValue
            }
        } else {
            if ($writeVerbose) {
                Write-Verbose -Message $localized.ReturningCachedValue
            }
        }

        $cachedValue.LastAccessTimeUtc = $timeStamp
        $cachedValue.Hits += 1
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
            if ( $Script:CachedCommandCaches.ContainsKey($Cache) ) {
                $cacheData = $Script:CachedCommandCaches[$Cache]

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
                $Script:CachedCommandCaches[$Cache].Remove($Label)
                break
            }

            'AllLabels' {
                $Script:CachedCommandCaches.Remove($Cache)
                break
            }

            'AllCaches' {
                $Script:CachedCommandCaches.Clear()
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
    )

    if ($PSBoundParameters.ContainsKey('Cache')) {
        $cacheKeys = $Script:CachedCommandCaches.get_Keys().Where({ $Cache -contains $_ })
    } else {
        $cacheKeys = $Script:CachedCommandCaches.get_Keys()
    }

    foreach ($cacheKey in $cacheKeys | Sort-Object) {

        $cacheData = $Script:CachedCommandCaches[$cacheKey]

        if ($PSBoundParameters.ContainsKey('Label')) {
            $labelKeys = $cacheData.get_Keys().Where({ $Label -contains $_ })
        } else {
            $labelKeys = $cacheData.get_Keys()
        }

        foreach ($labelKey in $labelKeys | Sort-Object) {

            [pscustomobject]@{
                Cache = $cacheKey
                Label = $labelKey
                Value = $cacheData[$labelKey].Value
            }
        }
    }
}
#endregion
