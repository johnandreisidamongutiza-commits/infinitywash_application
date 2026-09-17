@echo off
echo ========================================
echo Password Reset Email - Deployment
echo ========================================
echo.
echo This will deploy the email functions for password reset.
echo.

echo Step 1: Deploying reset-password function...
call supabase functions deploy reset-password
if %errorlevel% neq 0 (
    echo ERROR: Failed to deploy reset-password function
    echo Make sure Supabase CLI is installed and you're logged in
    pause
    exit /b 1
)
echo ✓ reset-password deployed
echo.

echo Step 2: Deploying send-reset-email function...
call supabase functions deploy send-reset-email
if %errorlevel% neq 0 (
    echo ERROR: Failed to deploy send-reset-email function
    pause
    exit /b 1
)
echo ✓ send-reset-email deployed
echo.

echo ========================================
echo Deployment Complete!
echo ========================================
echo.
echo NEXT STEPS:
echo 1. Sign up at resend.com (free - 100 emails/day)
echo 2. Get your API key (starts with "re_")
echo 3. Run: supabase secrets set RESEND_API_KEY=re_your_key_here
echo 4. Test password reset in your app
echo.
echo That's it! Users will receive beautiful emails with reset codes.
echo.
pause

