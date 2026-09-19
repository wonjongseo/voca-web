@echo off
setlocal
set "PROJECT_ROOT=%~dp0.."
for %%I in ("%PROJECT_ROOT%\..") do set "REPO_ROOT=%%~fI"
set "TOOLS_ROOT=%REPO_ROOT%\.tools"
set "APPDATA=%TOOLS_ROOT%"
set "PUB_CACHE=%TOOLS_ROOT%\pub-cache"
set "FLUTTER=%TOOLS_ROOT%\flutter\bin\flutter.bat"
if not exist "%FLUTTER%" (
  echo Flutter SDK was not found at "%FLUTTER%"
  exit /b 1
)
"%FLUTTER%" %*
exit /b %ERRORLEVEL%
