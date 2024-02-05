#Requires -Modules 'InvokeBuild','PSScriptAnalyzer','Pester'

# Define variables
# [string]$ModuleName = 'PSSecretScanner'
[string] $moduleSourcePath = "$PSScriptRoot\CachedCommand"


# Define task aliases (. = default task)
task . Lint, Test
task Lint RunPSScriptAnalyzer
task Test Clean, RunPester

task Clean {
    Remove-Item -Path "$PSScriptRoot/Output" -Recurse -Force -ErrorAction SilentlyContinue
}

# Define tasks
task RunPSScriptAnalyzer {
    Invoke-ScriptAnalyzer -Path $moduleSourcePath -Recurse -Severity 'Error', 'Warning' -EnableExit
}

task RunPester {
    $codeCoveragePaths = Get-ChildItem -Path $moduleSourcePath\*.ps*1 -Recurse -File # | Where-Object { $_.FullName -notlike "$($PSScriptRoot)*" } | Select-Object -ExpandProperty FullName

    $pesterConfig = @{
        CodeCoverage = @{
            CoveragePercentTarget = 90
            Enabled               = $true
            OutputPath            = "$PSScriptRoot/Output/coverage.xml"
            OutputFormat          = 'CoverageGutters'
            Path                  = $codeCoveragePaths
        }
        Output       = @{ 
            Verbosity = 'Detailed'
        }
        Run          = @{
            Exit     = $true
            PassThru = $true
        }
        TestResult   = @{
            Enabled = $true
            OutputPath = "$PSScriptRoot/Output/testResults.xml"
        }
    }

    Invoke-Pester -Configuration $pesterConfig
}
