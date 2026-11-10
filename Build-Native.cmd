@echo off
setlocal
pushd "%~dp0"
if not defined VCToolsInstallDir (
  if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" (
    for /f "usebackq tokens=*" %%I in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "trmpVisualStudio=%%I"
  )
)
if not defined VCToolsInstallDir (
  if not defined trmpVisualStudio goto failed
  call "%trmpVisualStudio%\VC\Auxiliary\Build\vcvars64.bat" >nul
  if errorlevel 1 goto failed
)
cl /nologo /std:c++17 /EHsc /LD /MT /Fo"native\prototype_runtime.obj" native\prototype_runtime.cpp /link /OUT:"native\prototype_runtime.dll"
if errorlevel 1 goto failed
cl /nologo /std:c++17 /EHsc /LD /MT /Fo"native\prototype_input.obj" native\prototype_input.cpp /link User32.lib /OUT:"native\prototype_input.dll"
if errorlevel 1 goto failed
cl /nologo /std:c++17 /EHsc /LD /MT /Fo"native\steam_probe.obj" native\steam_probe.cpp /link /OUT:"native\steam_probe.dll"
if errorlevel 1 goto failed
cl /nologo /std:c++17 /EHsc /LD /MT /Fo"native\steam_lobby.obj" native\steam_lobby.cpp /link /OUT:"native\steam_lobby.dll"
if errorlevel 1 goto failed
if /i "%~1"=="diagnostics" (
  cl /nologo /std:c++17 /EHsc /LD /MT /Fo"native\socket_trace.obj" native\socket_trace.cpp /link Ws2_32.lib /OUT:"native\trmp_trace.dll"
  if errorlevel 1 goto failed
  cl /nologo /std:c++17 /EHsc /LD /MT /Fo"native\controller_guard.obj" native\controller_guard.cpp /link /OUT:"native\controller_guard.dll"
  if errorlevel 1 goto failed
)
if /i "%~1"=="tests" (
  if not exist runtime\native-lobby-tests mkdir runtime\native-lobby-tests
  cl /nologo /std:c++17 /EHsc /MT /Fo"runtime\native-lobby-tests\steam_lobby_test.obj" tests\steam_lobby_test.cpp /link /OUT:"runtime\native-lobby-tests\steam_lobby_test.exe"
  if errorlevel 1 goto failed
  pushd runtime\native-lobby-tests
  steam_lobby_test.exe
  if errorlevel 1 goto failed
  popd
)
popd
exit /b 0
:failed
echo Build failed. Install Visual Studio C++ x64 build tools or use an x64 developer prompt.
popd
exit /b 1
