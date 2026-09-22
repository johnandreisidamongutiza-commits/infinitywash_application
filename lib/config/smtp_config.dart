/// SMTP Configuration Guide
/// 
/// This file contains instructions for setting up SMTP with different email providers.
/// Copy the appropriate settings to smtp_service.dart
library;

class SmtpConfigGuide {
  // ============================================
  // GMAIL CONFIGURATION
  // ============================================
  // Host: smtp.gmail.com
  // Port: 587 (TLS) or 465 (SSL)
  // Username: your-email@gmail.com
  // Password: App Password (NOT your regular Gmail password)
  //
  // Setup Steps for Gmail:
  // 1. Go to Google Account Settings
  // 2. Enable 2-Factor Authentication
  // 3. Go to Security > App Passwords
  // 4. Generate a new App Password for "Mail"
  // 5. Use this 16-character password in smtp_service.dart
  //
  // Limits: ~500 emails per day

  // ============================================
  // OUTLOOK/HOTMAIL CONFIGURATION
  // ============================================
  // Host: smtp-mail.outlook.com or smtp.office365.com
  // Port: 587 (TLS)
  // Username: your-email@outlook.com or your-email@hotmail.com
  // Password: Your regular Outlook password
  //
  // Limits: ~300 emails per day for personal accounts

  // ============================================
  // YAHOO MAIL CONFIGURATION
  // ============================================
  // Host: smtp.mail.yahoo.com
  // Port: 587 (TLS) or 465 (SSL)
  // Username: your-email@yahoo.com
  // Password: App Password (NOT regular password)
  //
  // Setup Steps for Yahoo:
  // 1. Go to Account Security
  // 2. Turn on "Allow apps that use less secure sign in"
  // 3. Or generate an App Password
  //
  // Limits: ~500 emails per day

  // ============================================
  // CUSTOM SMTP SERVER (e.g., cPanel, Namecheap)
  // ============================================
  // Host: mail.yourdomain.com (provided by your hosting)
  // Port: 587 (TLS) or 465 (SSL)
  // Username: your-email@yourdomain.com
  // Password: Your email password
  //
  // Limits: Depends on your hosting plan (usually unlimited)

  // ============================================
  // AWS SES (Amazon Simple Email Service)
  // ============================================
  // Host: email-smtp.us-east-1.amazonaws.com (region-specific)
  // Port: 587 (TLS) or 465 (SSL)
  // Username: SMTP Username from AWS SES Console
  // Password: SMTP Password from AWS SES Console
  //
  // Setup Steps:
  // 1. Create AWS account and verify your domain/email
  // 2. Go to SES Console > SMTP Settings
  // 3. Create SMTP Credentials
  //
  // Limits: 62,000 emails per month FREE (if sending from EC2)

  // ============================================
  // SENDGRID (Commercial)
  // ============================================
  // Host: smtp.sendgrid.net
  // Port: 587
  // Username: apikey (literally the word "apikey")
  // Password: Your SendGrid API Key
  //
  // Limits: 100 emails per day FREE, then paid plans

  // ============================================
  // MAILGUN (Commercial)
  // ============================================
  // Host: smtp.mailgun.org
  // Port: 587
  // Username: postmaster@yourdomain.mailgun.org
  // Password: Your Mailgun SMTP password
  //
  // Limits: 5,000 emails per month FREE for 3 months

  // ============================================
  // SECURITY BEST PRACTICES
  // ============================================
  // 1. NEVER commit SMTP credentials to git
  // 2. Use environment variables or flutter_secure_storage
  // 3. Use App Passwords instead of regular passwords
  // 4. Enable 2FA on your email account
  // 5. Monitor your email sending limits
  // 6. Implement rate limiting in your app
  // 7. Use SSL/TLS encryption (port 465 or 587)

  // ============================================
  // RATE LIMITING RECOMMENDATIONS
  // ============================================
  // - Max 3 OTP requests per user per hour
  // - Cooldown: 60 seconds between requests
  // - Daily limit per user: 10 requests
  // - Log all email sending attempts
  // - Monitor bounce rates and spam complaints
}

/// Example Environment Variables Setup
/// 
/// Create a .env file (and add to .gitignore):
/// ```
/// SMTP_HOST=smtp.gmail.com
/// SMTP_PORT=587
/// SMTP_USERNAME=your-email@gmail.com
/// SMTP_PASSWORD=your-app-password
/// SMTP_SENDER_EMAIL=your-email@gmail.com
/// SMTP_SENDER_NAME=InfinityWash
/// ```
/// 
/// Then use flutter_dotenv package to load these values:
/// ```dart
/// import 'package:flutter_dotenv/flutter_dotenv.dart';
/// 
/// await dotenv.load(fileName: ".env");
/// final host = dotenv.env['SMTP_HOST'];
/// ```

/// Example using Flutter Secure Storage
/// 
/// ```dart
/// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
/// 
/// final storage = FlutterSecureStorage();
/// 
/// // Store credentials securely
/// await storage.write(key: 'smtp_host', value: 'smtp.gmail.com');
/// await storage.write(key: 'smtp_username', value: 'your-email@gmail.com');
/// await storage.write(key: 'smtp_password', value: 'your-app-password');
/// 
/// // Read credentials
/// final host = await storage.read(key: 'smtp_host');
/// final username = await storage.read(key: 'smtp_username');
/// final password = await storage.read(key: 'smtp_password');
/// ```
