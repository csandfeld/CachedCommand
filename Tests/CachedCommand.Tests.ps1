Describe 'CachedCommand' {
    BeforeAll {
        $pesterModulePath = (Resolve-Path -Path '.\CachedCommand\CachedCommand.psd1').Path
        # Suppress UseDeclaredVarsBeforeAssignment warning
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsBeforeAssignment', 'VariableNotDeclared', Scope = 'Script')]
        $pesterModuleName = (Get-Item -Path $pesterModulePath).BaseName
        Remove-Module -Name $pesterModuleName -ErrorAction SilentlyContinue
        Import-Module -Name $pesterModulePath -Force
    }

    AfterAll {
        Remove-Module -Name $pesterModuleName -ErrorAction SilentlyContinue
    }

    Context 'Invoke-CachedCommand' {

        AfterEach {
            # Remove created cache variables
            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches.Clear()
            }
        }

        It 'Caches the output of the command' {
            $commandOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() }
            $cachedOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() }

            $commandOutput | Should -BeOfType [guid]
            $cachedOutput | Should -BeOfType [guid]
            $cachedOutput | Should -Be $commandOutput
        }

        It 'Expires the cache when Force switch is used' {
            $commandOutput1 = Invoke-CachedCommand -Force -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() }
            $commandOutput2 = Invoke-CachedCommand -Force -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() }

            $commandOutput1 | Should -BeOfType [guid]
            $commandOutput2 | Should -BeOfType [guid]
            $commandOutput2 | Should -Not -Be $commandOutput1
        }

        It 'Expires the cache if MaxHits is reached' {
            $maxHits = 3
            $commandOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -Force

            $commandOutput | Should -BeOfType [guid]

            for ($i = 0; $i -lt $maxHits; $i++) {
                $cachedOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -MaxHits $maxHits

                $cachedOutput | Should -BeOfType [guid]
                if ($i -eq $maxHits - 1) {
                    $cachedOutput | Should -Not -Be $commandOutput
                } else {
                    $cachedOutput | Should -Be $commandOutput
                }
            }
        }

        It 'Expires the cache if AbsoluteExpiration is reached' {
            $milliseconds = 500
            $expiration = [timespan]::FromMilliseconds($milliseconds)

            $commandOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -Force
            $cachedOutput1 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -AbsoluteExpiration $expiration
            Start-Sleep -Milliseconds ($milliseconds * 1.1)
            $cachedOutput2 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -AbsoluteExpiration $expiration

            $commandOutput | Should -BeOfType [guid]
            $cachedOutput1 | Should -BeOfType [guid]
            $cachedOutput2 | Should -BeOfType [guid]

            $cachedOutput1 | Should -Be $commandOutput
            $cachedOutput2 | Should -Not -Be $commandOutput
        }

        It 'Expires the cache if SlidingExpiration is reached' {
            $milliseconds = 200
            $expiration = [timespan]::FromMilliseconds($milliseconds)

            $commandOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -Force

            $value = 4
            do {
                $sleepMilliseconds = [math]::Pow(2, $value)
                $value++
                # "Sleeping: $sleepMilliseconds ms" | Write-Host -ForegroundColor Yellow
                Start-Sleep -Milliseconds $sleepMilliseconds
                $cachedOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -SlidingExpiration $expiration

                if ($sleepMilliseconds -ge $milliseconds) {
                    $cachedOutput | Should -Not -Be $commandOutput
                } else {
                    $cachedOutput | Should -Be $commandOutput
                }
            } while ($sleepMilliseconds -lt $milliseconds)
        }

        It 'Expires the cache if the scriptblock has been changed' {
            $commandOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { [guid]::NewGuid() } -Force
            $changedOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock { $g = [guid]::NewGuid() ; $g }

            $commandOutput | Should -BeOfType [guid]
            $changedOutput | Should -BeOfType [guid]
            $changedOutput | Should -Not -Be $commandOutput
        }

        It 'Does not expire the cache if scriptblock leading or trailing whitespace has been changed' {
            $sb1 = [scriptblock]::Create(' [guid]::NewGuid() ')
            $sb2 = [scriptblock]::Create('   [guid]::NewGuid()   ')
            $commandOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock $sb1 -Force
            $changedOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NewGuid' -ScriptBlock $sb2

            $commandOutput | Should -BeOfType [guid]
            $changedOutput | Should -BeOfType [guid]
            $changedOutput | Should -Be $commandOutput
        }

        It 'Rethrows exception thrown in scripblock' {
            { Invoke-CachedCommand -Cache 'PesterTest' -Label 'ExceptionThrown' -ScriptBlock { throw 'Some Exception' } -Force -ErrorAction Stop } |
            Should -Throw -ExpectedMessage 'Some Exception'
        }

        It 'Does not set cache if exception thrown in scripblock' {
            { Invoke-CachedCommand  -Cache 'PesterTest' -Label 'ExceptionThrown' -ScriptBlock { throw 'Some Exception' } -Force -ErrorAction Stop } |
            Should -Throw

            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches['PesterTest'].Keys | Should -Not -Contain 'ExceptionThrown'
                $Script:CachedCommandCaches['PesterTest'].Keys | Should -BeNullOrEmpty
            }
        }

        It 'Does not cache NULL values when called with -SkipNullValues' {
            $inputValue = $null
            $null = Invoke-CachedCommand -Cache 'PesterTest' -Label 'SkipNull' -ScriptBlock { $inputValue } -SkipNull
            $inputValue = 1
            $cachedOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'SkipNull' -ScriptBlock { $inputValue } -SkipNull

            $cachedOutput | Should -Not -BeNullOrEmpty
        }

        It 'Does cache NULL values when called without -SkipNullValues' {
            $inputValue = $null
            $null = Invoke-CachedCommand -Cache 'PesterTest' -Label 'SkipNull' -ScriptBlock { $inputValue }
            $inputValue = 1
            $cachedOutput = Invoke-CachedCommand -Cache 'PesterTest' -Label 'SkipNull' -ScriptBlock { $inputValue }

            $cachedOutput | Should -BeNullOrEmpty
        }

        It 'Outputs to verbose stream when Verbose switch is used' {
            # When invoking scriptblock
            $verboseStream1 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NullValue' -ScriptBlock { $null } -Verbose 4>&1
            # When scriptblock has changed
            $verboseStream2 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NullValue' -ScriptBlock {} -Verbose 4>&1
            # When returning cached value
            $verboseStream3 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NullValue' -ScriptBlock {} -Verbose 4>&1
            # When using the -Force switch
            $verboseStream4 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NullValue' -ScriptBlock {} -Verbose -Force 4>&1
            # When using MaxHits
            $verboseStream5 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NullValue' -ScriptBlock {} -Verbose -MaxHits 0 4>&1
            # When using AbsoluteExpiration
            $verboseStream6 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NullValue' -ScriptBlock {} -Verbose -AbsoluteExpiration ([timespan]::FromMinutes(-10)) 4>&1
            # When using SlidingExpiration
            $verboseStream7 = Invoke-CachedCommand -Cache 'PesterTest' -Label 'NullValue' -ScriptBlock {} -Verbose -SlidingExpiration ([timespan]::FromMinutes(-10)) 4>&1

            $verboseStream1 | Should -Not -BeNullOrEmpty
            $verboseStream2 | Should -Not -BeNullOrEmpty
            $verboseStream3 | Should -Not -BeNullOrEmpty
            $verboseStream4 | Should -Not -BeNullOrEmpty
            $verboseStream5 | Should -Not -BeNullOrEmpty
            $verboseStream6 | Should -Not -BeNullOrEmpty
            $verboseStream7 | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Clear-CachedCommand' {
        BeforeEach {
            # Create sample cache variables
            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches['PesterTest'] = @{ 'Key1' = 'Value1'; 'Key2' = 'Value2' }
                $Script:CachedCommandCaches['PesterTest2'] = @{ 'Key1' = 'Value1'; 'Key2' = 'Value2' }
            }
        }

        AfterEach {
            # Remove created cache variables
            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches.Clear()
            }
        }

        It 'Removes the data labeled Key1 from the cache data' {
            Clear-CachedCommand -Cache 'PesterTest' -Label 'Key1'

            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches['PesterTest'].Key1 | Should -BeNullOrEmpty
                $Script:CachedCommandCaches['PesterTest'].Key2 | Should -Be 'Value2'
            }
        }

        It 'Removes the data labeled Key2 from the cache data' {
            Clear-CachedCommand -Cache 'PesterTest' -Label 'Key2'

            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches['PesterTest'].Key1 | Should -Be 'Value1'
                $Script:CachedCommandCaches['PesterTest'].Key2 | Should -BeNullOrEmpty
            }
        }

        It 'Clears all cache data labels if the AllLabels switch is used' {
            Clear-CachedCommand -Cache 'PesterTest' -AllLabels

            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches['PesterTest'].Key1 | Should -BeNullOrEmpty
                $Script:CachedCommandCaches['PesterTest'].Key2 | Should -BeNullOrEmpty
            }
        }

        It 'Clears all caches if the AllLabels switch is used' {
            Clear-CachedCommand -AllCaches

            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches.Keys | Should -BeNullOrEmpty
            }
        }

        It 'Throws when trying to clear a cache that does not exist' {
            { Clear-CachedCommand -Cache 'NoneExisting' -AllLabels -ErrorAction Stop } |
            Should -Throw
        }

        It 'Throws when trying to clear a data label in a cache that was never created' {
            { Clear-CachedCommand -Cache 'NoneExisting' -Label 'Dummy' -ErrorAction Stop } |
            Should -Throw -ExceptionType 'System.Management.Automation.ItemNotFoundException'
        }

        It 'Throws when trying to clear a data label that does not exist' {
            { Clear-CachedCommand -Cache 'PesterTest' -Label 'Dummy' -ErrorAction Stop } |
            Should -Throw -ExceptionType 'System.Management.Automation.ItemNotFoundException'
        }
    }

    Context 'Show-CachedCommand' {
        BeforeAll {
            # Create sample cache variables
            InModuleScope $pesterModuleName {
                $Script:CachedCommandCaches['Cache1'] = @{ 'Label1-1' = 'Value1-1' }
                $Script:CachedCommandCaches['Cache2'] = @{ 'Label2-1' = 'Value2-1'; 'Label2-2' = 'Value2-2' }
                $Script:CachedCommandCaches['Cache3'] = @{ 'Label3-1' = 'Value3-1'; 'Label3-2' = 'Value3-2'; 'Label3-3' = 'Value3-3' }
            }
        }

        It 'Shows data for all caches when called with no parameters' {

            $commandOutput = Show-CachedCommand

            $commandOutput.Cache | Should -Contain 'Cache1'
            $commandOutput.Cache | Should -Contain 'Cache2'
            $commandOutput.Cache | Should -Contain 'Cache3'
            $commandOutput.Where({ $_.Cache -eq 'Cache1' }).Count | Should -Be 1
            $commandOutput.Where({ $_.Cache -eq 'Cache2' }).Count | Should -Be 2
            $commandOutput.Where({ $_.Cache -eq 'Cache3' }).Count | Should -Be 3
        }

        It 'Shows data for selected caches when called with the -Cache parameter' {
            $commandOutput = Show-CachedCommand -Cache 'Cache1', 'Cache2'

            $commandOutput.Cache | Should -Contain 'Cache1'
            $commandOutput.Cache | Should -Contain 'Cache2'
            $commandOutput.Cache | Should -Not -Contain 'Cache3'
            $commandOutput.Where({ $_.Cache -eq 'Cache1' }).Count | Should -Be 1
            $commandOutput.Where({ $_.Cache -eq 'Cache2' }).Count | Should -Be 2
            $commandOutput.Where({ $_.Cache -eq 'Cache3' }).Count | Should -Be 0
        }

        It 'Shows data for selected labels when called with the -Label parameter' {
            $commandOutput = Show-CachedCommand -Cache 'Cache3' -Label 'Label3-1', 'Label3-3'

            $commandOutput.Cache | Should -Not -Contain 'Cache1'
            $commandOutput.Cache | Should -Not -Contain 'Cache2'
            $commandOutput.Cache | Should -Contain 'Cache3'
            $commandOutput.Label | Should -Contain 'Label3-1'
            $commandOutput.Label | Should -Not -Contain 'Label3-2'
            $commandOutput.Label | Should -Contain 'Label3-3'
        }
    }
}
