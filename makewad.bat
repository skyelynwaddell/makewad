@echo off

REM Run the Ruby script with the specified arguments
.\makewad\makewad.rb textures palette.lmp wad\textures.wad

REM Check if the Ruby script ran successfully
if %ERRORLEVEL% neq 0 (
    echo Error: Ruby script failed!
    exit /b %ERRORLEVEL%
)

REM Optional: Print a message indicating completion
echo WAD file creation complete!

REM Pause the script so the window stays open
pause