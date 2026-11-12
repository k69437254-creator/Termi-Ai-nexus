@echo off
setlocal
set "APP_HOME=%~dp0"
set "GRADLE_VERSION=8.13"
if "%GRADLE_USER_HOME%"=="" set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"
set "INSTALL_ROOT=%GRADLE_USER_HOME%\wrapper\dists\termai-gradle-%GRADLE_VERSION%"
set "GRADLE_BIN=%INSTALL_ROOT%\gradle-%GRADLE_VERSION%\bin\gradle.bat"
if not exist "%GRADLE_BIN%" (
  if not exist "%INSTALL_ROOT%" mkdir "%INSTALL_ROOT%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://services.gradle.org/distributions/gradle-%GRADLE_VERSION%-bin.zip' -OutFile '%INSTALL_ROOT%\gradle-%GRADLE_VERSION%-bin.zip'; Expand-Archive -Force '%INSTALL_ROOT%\gradle-%GRADLE_VERSION%-bin.zip' '%INSTALL_ROOT%'; Remove-Item '%INSTALL_ROOT%\gradle-%GRADLE_VERSION%-bin.zip'"
  if errorlevel 1 exit /b 1
)
call "%GRADLE_BIN%" -p "%APP_HOME%" %*
exit /b %ERRORLEVEL%
