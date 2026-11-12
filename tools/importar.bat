@echo off
rem Importador de luchadores. Ejemplo: tools\importar.bat --sheet hoja.png --fighter id
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0importar.ps1" %*
