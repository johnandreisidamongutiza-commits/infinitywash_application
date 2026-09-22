import 'package:flutter/material.dart';
import '../services/smtp_service.dart';

/// Simple debug screen to test SMTP quickly
class DebugSmtpSimple extends StatefulWidget {
  const DebugSmtpSimple({super.key});

  @override
  State<DebugSmtpSimple> createState() => _DebugSmtpSimpleState();
}

class _DebugSmtpSimpleState extends State<DebugSmtpSimple> {
  final _emailController = TextEditingController();
  String _status = 'Ready to test';
  Color _statusColor = Colors.grey;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMTP Quick Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🧪 Quick SMTP Test',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Send a test OTP to verify SMTP is working',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            
            // Current config display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📋 Current Config:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Login: eksonmel018@gmail.com'),
                  Text('Sender: eksonmel018@gmail.com'),
                  Text('Password: svja blom vkcv lytv'),
                  SizedBox(height: 8),
                  Text('✅ Simple setup: sender = login', style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Email input
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'Test Email Address',
                hintText: 'Enter email to receive OTP',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),
            
            // Send button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _sendTestEmail,
              icon: _isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: const Text('Send Test OTP'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),
            
            // Status display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _statusColor),
              ),
              child: Text(
                _status,
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡 Instructions:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('1. Enter an email address above'),
                  Text('2. Tap "Send Test OTP"'),
                  Text('3. Check the inbox (and spam folder!)'),
                  Text('4. Watch this screen for status'),
                  SizedBox(height: 12),
                  Text('⚠️ If email not received:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  SizedBox(height: 4),
                  Text('• Check spam/junk folder'),
                  Text('• Verify "Send mail as" setup in Gmail'),
                  Text('• Check console logs for errors'),
                  Text('• Try using your own email first'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTestEmail() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _status = '❌ Please enter an email address';
        _statusColor = Colors.red;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '📤 Sending test OTP...';
      _statusColor = Colors.orange;
    });

    try {
      print('==============================================');
      print('🧪 SMTP TEST STARTING');
      print('==============================================');
      print('📧 Recipient: ${_emailController.text.trim()}');
      print('📤 Sender: eksonmel018@gmail.com');
      print('🔐 Login: eksonmel018@gmail.com');
      print('==============================================');

      final smtpService = SmtpService();
      final success = await smtpService.sendPasswordResetEmail(
        recipientEmail: _emailController.text.trim(),
        recipientName: 'Test User',
        resetCode: 'TEST123',
      );

      print('==============================================');
      if (success) {
        print('✅ EMAIL SENT SUCCESSFULLY!');
        print('📬 Check inbox: ${_emailController.text.trim()}');
        print('📂 Also check spam/junk folder');
      } else {
        print('❌ EMAIL SENDING FAILED!');
        print('💡 Check the error messages above');
      }
      print('==============================================');

      setState(() {
        _isLoading = false;
        if (success) {
          _status = '✅ Test OTP sent!\n\nCheck inbox at:\n${_emailController.text.trim()}\n\n(Also check spam folder!)';
          _statusColor = Colors.green;
        } else {
          _status = '❌ Failed to send email.\n\nCheck console logs for errors.\nMay need "Send mail as" setup.';
          _statusColor = Colors.red;
        }
      });
    } catch (e) {
      print('==============================================');
      print('❌ EXCEPTION OCCURRED:');
      print(e.toString());
      print('==============================================');

      setState(() {
        _isLoading = false;
        _status = '❌ Error: ${e.toString()}';
        _statusColor = Colors.red;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
