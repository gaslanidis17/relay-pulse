@echo off
REM ============================================================================
REM  start.bat - Windows launcher for the Delivery Analytics Dashboard
REM ----------------------------------------------------------------------------
REM  Starts BOTH halves of the app, each in its OWN cmd window:
REM    - Backend : FastAPI / uvicorn on http://localhost:8000
REM    - Frontend: Vite dev server on http://localhost:5173
REM  On first run it creates the Python venv + installs backend requirements and
REM  runs `npm install` for the frontend. Close each window (or Ctrl+C in it) to
REM  stop that server.
REM
REM  Usage: double-click in Explorer, or run  start.bat  from a terminal.
REM
REM  NOTE: This is the Windows equivalent of start.command / run.sh and was
REM  written on macOS, so it is best-effort and could not be executed here.
REM  Windows-specific differences vs. the macOS/Linux scripts:
REM    * venv activation script is  backend\venv\Scripts\activate.bat
REM      (on macOS/Linux it is  backend/venv/bin/activate)
REM    * uses the `python` launcher rather than `python3`
REM    * `npm` is npm.cmd, so it must be invoked with `call npm ...` in a .bat
REM    * port auto-freeing is left commented out (Windows has no `lsof`; see the
REM      netstat/taskkill snippet near the bottom to enable it if desired).
REM ============================================================================

setlocal

REM cd to this script's own directory so it works no matter where it is launched
REM from. %~dp0 expands to this .bat's drive+path (with a trailing backslash).
cd /d "%~dp0"

REM --- .env required (Snowflake credentials) ---------------------------------
if not exist ".env" (
  echo ERROR: .env not found in "%cd%"
  echo Copy the template and fill in your Snowflake credentials, then re-run:
  echo     copy .env.example .env
  echo.
  pause
  exit /b 1
)

REM --- Optional: free stale ports BEFORE starting (uncomment to enable) -------
REM Windows lacks lsof; netstat + taskkill is the equivalent. Disabled by
REM default because closing each window already stops its server.
REM for /f "tokens=5" %%P in ('netstat -aon ^| findstr ":8000 " ^| findstr "LISTENING"') do taskkill /F /PID %%P >nul 2>&1
REM for /f "tokens=5" %%P in ('netstat -aon ^| findstr ":5173 " ^| findstr "LISTENING"') do taskkill /F /PID %%P >nul 2>&1

REM --- Backend: create venv + install deps on first run ----------------------
if not exist "backend\venv\Scripts\activate.bat" (
  echo First run: creating backend\venv and installing requirements...
  pushd backend
  python -m venv venv
  call venv\Scripts\activate.bat
  pip install -r requirements.txt
  popd
)

REM Open the backend in its own window. `cmd /k` keeps the window open so the
REM logs stay visible and you can Ctrl+C it. The new window inherits this repo
REM root as its working directory, so the relative `cd backend` works even if
REM the repo path contains spaces.
start "Dashboard Backend (:8000)" cmd /k "cd backend && call venv\Scripts\activate.bat && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload"

REM --- Frontend: npm install on first run, then start Vite -------------------
if not exist "frontend\node_modules" (
  echo First run: installing frontend deps ^(npm install^)...
  pushd frontend
  call npm install
  popd
)
start "Dashboard Frontend (:5173)" cmd /k "cd frontend && call npm run dev"

REM --- URLs -------------------------------------------------------------------
echo.
echo Dashboard starting in two new windows:
echo   Frontend:  http://localhost:5173
echo   Backend:   http://localhost:8000
echo   API docs:  http://localhost:8000/docs
echo.
echo Close each window ^(or press Ctrl+C in it^) to stop that server.
echo.

endlocal
