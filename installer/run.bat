@echo off
REM 启动后端（后台），再启动前端
cd /d "%~dp0"
start "" /B "%~dp0hyrwbz_backend.exe"
REM 等待后端就绪
timeout /t 1 /nobreak >nul
start "" "%~dp0frontend\hyrwbz_frontend.exe"
