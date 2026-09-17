PASSWORD RESET - QUICK SETUP
=============================

Your forgot password feature is ready. Just needs deployment:

DEPLOY (15 minutes):
-------------------
1. Run: deploy_email_function.bat
2. Sign up at resend.com (free)
3. Get API key
4. Run: supabase secrets set RESEND_API_KEY=re_your_key
5. Test in app

That's it!

WHAT IT DOES:
------------
- User enters email
- Gets 6-character code (e.g., "AbC123")
- Receives beautiful email
- Enters code
- Resets password

TROUBLESHOOTING:
---------------
- No email? Check spam folder
- Function error? Check: supabase functions logs send-reset-email
- API key issue? Run: supabase secrets list

COST: FREE (100 emails/day with Resend)
