# CachedCommand

A simple PowerShell module to cache command output.

While other more sofisticated modules like PSPolly (support caching, retries, circuit breakers etc.) exist, this module aims to implement a simple caching mechanism that can be used in any PowerShell script, without depending on third party libraries.

## Sources of inspiration

This module is inspired by the following posts and modules:

- [Blog: Looking up entries by property in large collections](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations#looking-up-entries-by-property-in-large-collections) by Microsoft
- [Blog: PowerShell Easy Caching](https://www.foxdeploy.com/blog/powershell-easy-caching.html) by Stephen Owen (FoxDeploy)
- [Module: PSPolly](https://www.powershellgallery.com/packages/PSPolly/) by Adam Driscoll
