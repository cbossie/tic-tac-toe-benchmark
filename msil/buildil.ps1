# Builds the hand-written MSIL version (TicTacToe.il) into TicTacToeIL.dll, then run it with:
#   dotnet TicTacToeIL.dll
# The .NET SDK has no IL assembler, so the first run downloads Microsoft's ILAsm package from
# nuget.org (about 450 KB) into .ilasm\ next to this script. Set $env:ILASM to use your own ilasm.exe.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$ilasmVersion = '10.0.13'

$ilasm = if ($env:ILASM) { $env:ILASM } else { Join-Path $PSScriptRoot '.ilasm\runtimes\win-x64\native\ilasm.exe' }
if (-not (Test-Path $ilasm)) {
    Write-Host "Downloading ILAsm $ilasmVersion from nuget.org..."
    $package = 'runtime.win-x64.microsoft.netcore.ilasm'
    $zip = Join-Path $PSScriptRoot '.ilasm\ilasm.zip'
    New-Item -ItemType Directory -Force (Split-Path $zip) | Out-Null
    Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/$package/$ilasmVersion/$package.$ilasmVersion.nupkg" -OutFile $zip
    Expand-Archive $zip -DestinationPath (Split-Path $zip) -Force
    Remove-Item $zip
}

& $ilasm -nologo -quiet -exe '-output=TicTacToeIL.dll' TicTacToe.il
if ($LASTEXITCODE -ne 0) { throw "ilasm failed (exit code $LASTEXITCODE)" }

# dotnet needs a runtimeconfig next to the dll to know which runtime to start.
Set-Content TicTacToeIL.runtimeconfig.json '{ "runtimeOptions": { "tfm": "net10.0", "framework": { "name": "Microsoft.NETCore.App", "version": "10.0.0" } } }'
Write-Host 'Built TicTacToeIL.dll. Run: dotnet TicTacToeIL.dll'
