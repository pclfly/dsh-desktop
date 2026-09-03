@echo off
rem 本文件为 GBK(936) 编码，请勿另存为 UTF-8，否则中文提示会乱码
rem DSH Desktop Windows 一键打包脚本
rem 双击运行：选择正式包或开发包，自动检查环境并打包，完成后打开产物目录。

rem ---- 切到脚本所在目录（仓库根），保证双击运行时路径正确 ----
cd /d "%~dp0"

title DSH Desktop 一键打包

echo.
echo ================================================
echo            DSH Desktop Windows 一键打包
echo ================================================
echo.

rem ---- 环境检查：node / npm ----
where node >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 node。请先安装 Node.js 22 或更高版本：
    echo        https://nodejs.org/ 或使用 nvm-windows / conda 安装。
    goto :fail
)
where npm >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 npm。请确认 Node.js 安装完整（npm 随 Node 一起安装）。
    goto :fail
)

rem ---- 版本检查：Node 主版本必须 >= 22 ----
set "NODE_VERSION="
for /f "delims=" %%v in ('node -v 2^>nul') do set "NODE_VERSION=%%v"
if not defined NODE_VERSION (
    echo [错误] 无法读取 node 版本。
    goto :fail
)
set "NODE_VERSION=%NODE_VERSION:v=%"
set "NODE_MAJOR="
for /f "delims=. tokens=1" %%n in ("%NODE_VERSION%") do set "NODE_MAJOR=%%n"
if not defined NODE_MAJOR (
    echo [错误] 无法解析 node 版本号：%NODE_VERSION%
    goto :fail
)
set /a NODE_MAJOR=%NODE_MAJOR% 2>nul
if %NODE_MAJOR% LSS 22 (
    echo [错误] 当前 Node 版本为 %NODE_VERSION%，本仓库要求 Node 22 或更高版本。
    goto :fail
)
for /f "delims=" %%v in ('npm -v 2^>nul') do set "NPM_VERSION=%%v"
echo [环境] Node %NODE_VERSION%  /  npm %NPM_VERSION%
echo.

rem ---- 依赖检查：node_modules 缺失时自动安装 ----
if not exist "node_modules\" (
    echo [依赖] 未检测到 node_modules，开始安装依赖（含 patch-package 补丁与 Electron 下载）...
    echo        首次安装耗时较长，请耐心等待。
    echo.
    call npm ci
    if errorlevel 1 (
        echo.
        echo [错误] npm ci 安装依赖失败。请检查网络后重试，或手动运行: npm ci
        goto :fail
    )
    echo.
    echo [依赖] 依赖安装完成。
    echo.
)

rem ---- 菜单：选择打包目标，5 秒不选默认开发包 ----
echo 请选择要打包的版本：
echo    [1] 正式包    输出到 dist\           （DSH Desktop，正式安装器）
echo    [2] 开发包    输出到 dist-dev\       （DSH Desktop Dev，数据隔离，适合日常自用）
echo.
choice /c 12 /n /m "请按键选择 [1/2]，5 秒后默认打包开发包: " /d 2 /t 5
if errorlevel 3 goto :fail
if errorlevel 2 (
    set "PKG_SCRIPT=package:dev:win"
    set "PKG_LABEL=开发包"
    set "PKG_DIR=dist-dev"
    set "PKG_UNPACKED_EXE=dist-dev\win-unpacked\DSH Desktop Dev.exe"
    set "PKG_NODE_EXE=dist-dev\win-unpacked\resources\app\node_modules\node\bin\node.exe"
    set "PKG_INSTALLER=dist-dev\dsh-desktop-dev-windows-x64-setup.exe"
    goto :run_package
)
if errorlevel 1 (
    set "PKG_SCRIPT=package:win"
    set "PKG_LABEL=正式包"
    set "PKG_DIR=dist"
    set "PKG_UNPACKED_EXE=dist\win-unpacked\DSH Desktop.exe"
    set "PKG_NODE_EXE=dist\win-unpacked\resources\app\node_modules\node\bin\node.exe"
    set "PKG_INSTALLER=dist\dsh-desktop-windows-x64-setup.exe"
    goto :run_package
)
goto :fail

:run_package
echo.
echo ================================================
echo  开始打包：%PKG_LABEL%（npm run %PKG_SCRIPT%）
echo  包含：market 构建 → electron-vite 构建 → NSIS 安装器
echo  预计需要几分钟，请勿关闭本窗口。
echo ================================================
echo.
call npm run %PKG_SCRIPT%
if errorlevel 1 (
    echo.
    echo [错误] 打包失败。请向上滚动查看 electron-builder / npm 的错误输出。
    goto :fail
)

rem ---- 产物自检 ----
echo.
echo [自检] 检查打包产物...
set "SELF_CHECK_FAIL="
if not exist "%PKG_INSTALLER%"    (echo     缺失 %PKG_INSTALLER% & set "SELF_CHECK_FAIL=1")
if not exist "%PKG_UNPACKED_EXE%" (echo     缺失 %PKG_UNPACKED_EXE% & set "SELF_CHECK_FAIL=1")
if not exist "%PKG_NODE_EXE%"     (echo     缺失 %PKG_NODE_EXE%（内置 Harness Node 运行时） & set "SELF_CHECK_FAIL=1")
if defined SELF_CHECK_FAIL (
    echo.
    echo [错误] 打包命令已结束，但以上产物缺失，打包可能不完整，请查看上方日志。
    goto :fail
)
echo [自检] 全部通过。

rem ---- 成功：打开产物目录并选中安装器 ----
echo.
echo ================================================
echo  打包成功！
echo  安装器：%CD%\%PKG_INSTALLER%
echo ================================================
start "" explorer /select,"%CD%\%PKG_INSTALLER%"
echo.
echo 按任意键关闭窗口...
pause >nul
endlocal
exit /b 0

:fail
echo.
echo 打包未完成。按任意键关闭窗口...
pause >nul
endlocal
exit /b 1
