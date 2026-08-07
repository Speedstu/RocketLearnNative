@echo off
setlocal
set "ROOT=%~dp0"
cd /d "%ROOT%"

if not exist "build-native\bin\Release\rocket_learn_evaluator.exe" call "%ROOT%BUILD_EVALUATOR.bat"
if errorlevel 1 exit /b 1
if not exist logs mkdir logs

start "RocketLearn Skill Evaluator" /min cmd /c "build-native\bin\Release\rocket_learn_evaluator.exe > logs\skill-evaluator.log 2>&1"
echo Native 2v2 TrueSkill evaluator started.
