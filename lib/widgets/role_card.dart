import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum RoleCardLayout { horizontal, vertical }

class RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget icon;
  final VoidCallback onTap;
  final bool isSelected;
  final RoleCardLayout layout;

  const RoleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isSelected = false,
    this.layout = RoleCardLayout.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: isSelected ? AppStyles.selectedCardDecoration : AppStyles.cardDecoration,
        padding: const EdgeInsets.all(20),
        child: Stack(
          children: [
            if (isSelected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppTheme.accentBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            layout == RoleCardLayout.horizontal ? _buildHorizontal() : _buildVertical(),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontal() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: title == 'Team Member' ? AppTheme.teamMemberOrange : AppTheme.lightBlue,
            shape: BoxShape.circle,
          ),
          child: Center(child: icon),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppTheme.lightTheme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTheme.lightTheme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const Icon(
          Icons.arrow_forward_ios,
          size: 20,
          color: AppTheme.textDark,
        ),
      ],
    );
  }

  Widget _buildVertical() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.lightBlue : AppTheme.softGray,
            shape: BoxShape.circle,
          ),
          child: Center(child: icon),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: AppTheme.lightTheme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: AppTheme.lightTheme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
