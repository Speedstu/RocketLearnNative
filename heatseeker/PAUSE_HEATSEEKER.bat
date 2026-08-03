@echo off
powershell -NoProfile -Command "$names=@('rocket-learn-supervisor.exe','rocket_learn_native.exe','rocket_learn_evaluator.exe'); Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.Name+'.exe' -in $names} | Stop-Process -Force"
echo Heatseeker trainer and evaluator paused. Checkpoints were preserved.
