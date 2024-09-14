@echo off
REM Change to the directory where the batch file is located
cd /d "%~dp0\makewad"

REM Run bundle install
echo Installing MakeWad Dependencies...
bundle install

REM Pause to keep the command prompt open
echo Install Success!
pause