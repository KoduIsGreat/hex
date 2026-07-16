@echo off
cd /d "%~dp0game"

rem MSVC link.exe can fail with LNK1000 outside a VS developer shell.
rem Odin's bundled LLD linker avoids that.
rem OpenGL backend: this game's cloud shaders are GLSL (D3D11 expects HLSL).
odin run . -linker:lld -define:KARL2D_RENDER_BACKEND=gl
exit /b %ERRORLEVEL%
