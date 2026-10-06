import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/input_formatters.dart';
import '../../../utils/validators.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _commentController = TextEditingController();
  int _rating = 0;
  bool _isSubmitted = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSubmitted) return _buildSuccessView();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Give Feedback'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.star_outline, size: 80, color: AppTheme.teamMemberIconOrange),
            const SizedBox(height: 24),
            Text('How was your experience?', style: AppTheme.lightTheme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text('Your feedback helps us improve our service.', textAlign: TextAlign.center),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  onPressed: () => setState(() => _rating = index + 1),
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: AppTheme.teamMemberIconOrange,
                    size: 40,
                  ),
                );
              }),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _commentController,
              maxLines: 5,
              inputFormatters:
                  InputFormatters.text(maxLength: Validators.notesMax),
              decoration: InputDecoration(
                hintText: 'Tell us more about our service...',
                hintStyle: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppTheme.softGray,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _rating == 0 ? null : () => setState(() => _isSubmitted = true),
              child: const Text('Confirm Feedback'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 100, color: Colors.green),
            const SizedBox(height: 24),
            Text('Successful!', style: AppTheme.lightTheme.textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('Thank you for your feedback!', textAlign: TextAlign.center),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => setState(() {
                _isSubmitted = false;
                _rating = 0;
              }),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
