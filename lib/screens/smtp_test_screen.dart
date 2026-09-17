import 'package:flutter/material.dart';
import '../services/smtp_service.dart';
import '../services/rate_limit_service.dart';
import '../theme/app_theme.dart';

/// Debug screen to test SMTP functionality
/// Access this from your app to verify SMTP is working
class SmtpTestScreen extends StatefulWidget {
  const SmtpTestScreen({super.key});

  @override
  State<SmtpTestScreen> createState() => _SmtpTestScreenState();
}

class _SmtpTestScreenState extends State<SmtpTestScreen> {
  final _emailController = TextEditingController();
  final _smtpService = SmtpService();
  bool _isLoading = false;
  String? _lastResult;
  Color _resultColor = Colors.black;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _testSMTPConnection() async {
    setState(() {
      _isLoading = true;
      _lastResult = 'Testing SMTP connection...';
      _resultColor = Colors.orange;
    });

    try {
      final success = await _smtpService.testConnection();
      setState(() {
        _isLoading = false;
        if (success) {
          _lastResult = '✅ SMTP connection successful!\nCheck your inbox for test email.';
          _resultColor = Colors.green;
        } else {
          _lastResult = '❌ SMTP connection failed!\nCheck credentials and network.';
          _resultColor = Colors.red;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _lastResult = '❌ Error: ${e.toString()}';
        _resultColor = Colors.red;
      });
    }
  }

  Future<void> _sendTestOTP() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _lastResult = 'Sending test OTP...';
      _resultColor = Colors.orange;
    });

    try {
      final success = await _smtpService.sendPasswordResetEmail(
        recipientEmail: _emailController.text.trim(),
        recipientName: 'Test User',
        resetCode: 'ABC123',
      );

      setState(() {
        _isLoading = false;
        if (success) {
          _lastResult = '✅ Test OTP sent successfully!\nCheck ${_emailController.text} inbox.';
          _resultColor = Colors.green;
        } else {
          _lastResult = '❌ Failed to send test OTP.\nCheck SMTP settings.';
          _resultColor = Colors.red;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _lastResult = '❌ Error: ${e.toString()}';
        _resultColor = Colors.red;
      });
    }
  }

  Future<void> _checkRateLimit() async {
    if (_emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _lastResult = 'Checking rate limit...';
      _resultColor = Colors.orange;
    });

    try {
      final status = await RateLimitService.getStatus(_emailController.text.trim());
      final canSend = status['canSend'] as bool;
      final attempts = status['attempts'] as int;
      final attemptsLeft = status['attemptsLeft'] as int;

      setState(() {
        _isLoading = false;
        _lastResult = '''
📊 Rate Limit Status:
• Can send: ${canSend ? '✅ Yes' : '❌ No'}
• Attempts used: $attempts / ${status['maxAttempts']}
• Attempts left: $attemptsLeft
${canSend ? '' : '• Please wait before trying again'}
        ''';
        _resultColor = canSend ? Colors.green : Colors.orange;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _lastResult = '❌ Error: ${e.toString()}';
        _resultColor = Colors.red;
      });
    }
  }

  Future<void> _clearRateLimit() async {
    await RateLimitService.clearAll();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Rate limit data cleared!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMTP Debug & Testing'),
        backgroundColor: AppTheme.accentBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            const Text(
              'SMTP Configuration Test',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use this screen to verify your SMTP setup is working correctly.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // Current SMTP Config Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚙️ Current Configuration:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('• Host: smtp.gmail.com'),
                  Text('• Port: 587'),
                  Text('• Login: eksonmel018@gmail.com'),
                  Text('• Sender: eksonmel018@gmail.com'),
                  const SizedBox(height: 8),
                  const Text(
                    '✅ Sender matches login - simple setup!',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Test Email Input
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Test Email Address',
                hintText: 'Enter email to send test OTP',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),

            // Test Buttons
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testSMTPConnection,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('1. Test SMTP Connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _sendTestOTP,
              icon: const Icon(Icons.send),
              label: const Text('2. Send Test OTP Email'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _checkRateLimit,
              icon: const Icon(Icons.speed),
              label: const Text('3. Check Rate Limit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _clearRateLimit,
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Clear Rate Limit (Debug Only)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 32),

            // Loading Indicator
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),

            // Result Display
            if (_lastResult != null && !_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _resultColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _resultColor),
                ),
                child: Text(
                  _lastResult!,
                  style: TextStyle(
                    color: _resultColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // Troubleshooting Tips
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔧 Troubleshooting Tips:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('1. ✅ Make sure 2FA is enabled on Gmail'),
                  const Text('2. ✅ Generate App Password (not regular password)'),
                  const Text('3. ✅ Sender email must match username'),
                  const Text('4. ✅ Check internet connection'),
                  const Text('5. ✅ Disable antivirus/firewall temporarily'),
                  const Text('6. ✅ Check spam folder if email not received'),
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ Common Errors:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• "Username and Password not accepted" → Use App Password\n'
                    '• "Connection timeout" → Check network/firewall\n'
                    '• "Certificate error" → Update smtp_service.dart settings',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
