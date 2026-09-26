@echo off
python "%~dp0nuget_cache_adapter.py" %*
exit /b %errorlevel%
