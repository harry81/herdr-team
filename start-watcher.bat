@echo off
rem Root convenience wrapper: real implementation is windows\start-watcher.bat
rem 루트 편의 래퍼: 실제 구현은 windows\start-watcher.bat
call "%~dp0windows\start-watcher.bat" %*
