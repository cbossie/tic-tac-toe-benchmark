# Builds the x64 assembly version (TicTacToeTable.asm) into TicTacToeAsmTable.exe.
# Needs the "Desktop development with C++" Visual Studio workload (for ml64 and link).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$install = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $install) { throw 'Visual Studio with the C++ build tools was not found.' }
$vcvars = Join-Path $install 'VC\Auxiliary\Build\vcvars64.bat'

# vcvars64.bat puts ml64 and link on PATH (and sets LIB); copy its environment into this session.
cmd /c "`"$vcvars`" >nul 2>nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { Set-Item "Env:$($Matches[1])" $Matches[2] }
}

ml64 /nologo /c /Fo TicTacToeAsmTable.obj TicTacToeTable.asm
if ($LASTEXITCODE -ne 0) { throw "ml64 failed (exit code $LASTEXITCODE)" }
link /nologo /SUBSYSTEM:CONSOLE /ENTRY:main /NODEFAULTLIB /OUT:TicTacToeAsmTable.exe TicTacToeAsmTable.obj kernel32.lib
if ($LASTEXITCODE -ne 0) { throw "link failed (exit code $LASTEXITCODE)" }
Remove-Item TicTacToeAsmTable.obj
Write-Host 'Built TicTacToeAsmTable.exe'
