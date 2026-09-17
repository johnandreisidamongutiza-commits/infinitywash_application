import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class SmtpService {
  // SMTP Configuration
  // TODO: Move these to environment variables or secure storage
  static const String _smtpHost = 'smtp.gmail.com'; // Change based on your provider
  static const int _smtpPort = 587; // 587 for TLS, 465 for SSL
  static const String _username = 'eksonmel018@gmail.com'; // Your Gmail account
  static const String _password = 'svja blom vkcv lytv'; // App password from eksonmel018@gmail.com
  static const String _senderEmail = 'eksonmel018@gmail.com'; // Same as username
  static const String _senderName = 'InfinityWash';

  /// Send password reset OTP email
  Future<bool> sendPasswordResetEmail({
    required String recipientEmail,
    required String recipientName,
    required String resetCode,
  }) async {
    try {
      print('📧 Preparing to send email to: $recipientEmail');

      // Create SMTP server configuration
      final smtpServer = SmtpServer(
        _smtpHost,
        port: _smtpPort,
        username: _username,
        password: _password,
        // Use STARTTLS (recommended for most providers)
        ignoreBadCertificate: false,
        ssl: false, // Set to true if using port 465
        allowInsecure: false,
      );

      // Create email message
      final message = Message()
        ..from = Address(_senderEmail, _senderName)
        ..recipients.add(recipientEmail)
        ..subject = 'Password Reset Code - InfinityWash'
        ..html = _buildPasswordResetEmailHtml(recipientName, resetCode)
        ..text = _buildPasswordResetEmailText(recipientName, resetCode);

      // Send the email
      print('📤 Sending email...');
      final sendReport = await send(message, smtpServer);
      
      print('✅ Email sent successfully!');
      print('📊 Send report: ${sendReport.toString()}');
      
      return true;
    } on MailerException catch (e) {
      print('❌ Mailer Error: ${e.toString()}');
      for (var p in e.problems) {
        print('Problem: ${p.code}: ${p.msg}');
      }
      return false;
    } catch (e) {
      print('❌ Unexpected error sending email: $e');
      return false;
    }
  }

  /// Send welcome email (optional - can be added later)
  Future<bool> sendWelcomeEmail({
    required String recipientEmail,
    required String recipientName,
  }) async {
    try {
      final smtpServer = SmtpServer(
        _smtpHost,
        port: _smtpPort,
        username: _username,
        password: _password,
        ignoreBadCertificate: false,
        ssl: false,
        allowInsecure: false,
      );

      final message = Message()
        ..from = Address(_senderEmail, _senderName)
        ..recipients.add(recipientEmail)
        ..subject = 'Welcome to InfinityWash!'
        ..html = _buildWelcomeEmailHtml(recipientName)
        ..text = 'Welcome to InfinityWash, $recipientName!';

      await send(message, smtpServer);
      print('✅ Welcome email sent to: $recipientEmail');
      return true;
    } catch (e) {
      print('❌ Failed to send welcome email: $e');
      return false;
    }
  }

  /// Build HTML email for password reset
  String _buildPasswordResetEmailHtml(String name, String code) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
    }
    .container {
      background-color: #f9f9f9;
      border-radius: 10px;
      padding: 30px;
      border: 1px solid #e0e0e0;
    }
    .header {
      text-align: center;
      margin-bottom: 30px;
    }
    .logo {
      font-size: 28px;
      font-weight: bold;
      color: #2196F3;
    }
    .code-box {
      background-color: #2196F3;
      color: white;
      font-size: 32px;
      font-weight: bold;
      text-align: center;
      padding: 20px;
      border-radius: 8px;
      margin: 30px 0;
      letter-spacing: 8px;
    }
    .warning {
      background-color: #fff3cd;
      border-left: 4px solid #ffc107;
      padding: 15px;
      margin: 20px 0;
      border-radius: 4px;
    }
    .footer {
      text-align: center;
      margin-top: 30px;
      font-size: 12px;
      color: #666;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">🌀 InfinityWash</div>
    </div>
    
    <h2>Password Reset Request</h2>
    <p>Hello ${name.isNotEmpty ? name : 'there'},</p>
    <p>We received a request to reset your password. Use the code below to complete your password reset:</p>
    
    <div class="code-box">$code</div>
    
    <div class="warning">
      <strong>⏱️ Important:</strong> This code will expire in <strong>15 minutes</strong>.
    </div>
    
    <p><strong>Security Tips:</strong></p>
    <ul>
      <li>Never share this code with anyone</li>
      <li>InfinityWash will never ask for your code via phone or email</li>
      <li>If you didn't request this reset, please ignore this email</li>
    </ul>
    
    <div class="footer">
      <p>This is an automated message from InfinityWash.</p>
      <p>If you have questions, please contact our support team.</p>
    </div>
  </div>
</body>
</html>
''';
  }

  /// Build plain text email for password reset (fallback)
  String _buildPasswordResetEmailText(String name, String code) {
    return '''
Password Reset Request - InfinityWash

Hello ${name.isNotEmpty ? name : 'there'},

We received a request to reset your password. Use the code below to complete your password reset:

YOUR RESET CODE: $code

IMPORTANT: This code will expire in 15 minutes.

Security Tips:
- Never share this code with anyone
- InfinityWash will never ask for your code via phone or email
- If you didn't request this reset, please ignore this email

---
This is an automated message from InfinityWash.
If you have questions, please contact our support team.
''';
  }

  /// Build HTML email for welcome message
  String _buildWelcomeEmailHtml(String name) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
    }
    .container {
      background-color: #f9f9f9;
      border-radius: 10px;
      padding: 30px;
      border: 1px solid #e0e0e0;
    }
    .header {
      text-align: center;
      margin-bottom: 30px;
    }
    .logo {
      font-size: 32px;
      font-weight: bold;
      color: #2196F3;
    }
    .button {
      display: inline-block;
      background-color: #2196F3;
      color: white;
      padding: 12px 30px;
      text-decoration: none;
      border-radius: 5px;
      margin: 20px 0;
    }
    .footer {
      text-align: center;
      margin-top: 30px;
      font-size: 12px;
      color: #666;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">🌀 InfinityWash</div>
    </div>
    
    <h2>Welcome to InfinityWash!</h2>
    <p>Hello ${name.isNotEmpty ? name : 'there'},</p>
    <p>Thank you for joining InfinityWash. We're excited to have you on board!</p>
    
    <p>With InfinityWash, you can:</p>
    <ul>
      <li>Schedule laundry pickups at your convenience</li>
      <li>Track your orders in real-time</li>
      <li>Enjoy professional cleaning services</li>
      <li>Manage your account easily</li>
    </ul>
    
    <div class="footer">
      <p>Need help? Contact our support team anytime.</p>
      <p>&copy; 2024 InfinityWash. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
''';
  }

  /// Test SMTP connection
  Future<bool> testConnection() async {
    try {
      print('🔌 Testing SMTP connection...');
      
      final smtpServer = SmtpServer(
        _smtpHost,
        port: _smtpPort,
        username: _username,
        password: _password,
        ignoreBadCertificate: false,
        ssl: false,
        allowInsecure: false,
      );

      // Try to create a connection
      final connection = PersistentConnection(smtpServer);
      await connection.send(Message()
        ..from = Address(_senderEmail, _senderName)
        ..recipients.add(_senderEmail) // Send test to self
        ..subject = 'SMTP Connection Test'
        ..text = 'This is a test email to verify SMTP configuration.');
      
      await connection.close();
      
      print('✅ SMTP connection successful!');
      return true;
    } catch (e) {
      print('❌ SMTP connection failed: $e');
      return false;
    }
  }
}
