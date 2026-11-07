import 'package:flutter/material.dart';

/// Sweeps a soft highlight across its skeleton children while data loads.
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final begin = -2 + (_controller.value * 4);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [Color(0xFFE7EBEF), Color(0xFFF6F8FA), Color(0xFFE7EBEF)],
            begin: Alignment(begin, 0),
            end: Alignment(begin + 1, 0),
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Rounded placeholder used by the role dashboard loading states.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE7EBEF),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Scrollable list placeholder for order, payment, and request cards.
class SkeletonCardList extends StatelessWidget {
  const SkeletonCardList({
    super.key,
    this.itemCount = 4,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 100),
    this.spacing = 12,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (context, index) => SizedBox(height: spacing),
      itemBuilder: (context, index) => const SkeletonDataCard(),
    );
  }
}

/// Card-shaped skeleton for order and payment list items.
class SkeletonDataCard extends StatelessWidget {
  const SkeletonDataCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EBEF)),
      ),
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                SkeletonBlock(width: 42, height: 42, borderRadius: 12),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBlock(width: 120, height: 14),
                      SizedBox(height: 8),
                      SkeletonBlock(width: 90, height: 11),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                SkeletonBlock(width: 62, height: 22, borderRadius: 12),
              ],
            ),
            const SizedBox(height: 16),
            const SkeletonBlock(width: double.infinity, height: 10),
            const SizedBox(height: 9),
            const Row(
              children: [
                SkeletonBlock(width: 72, height: 10),
                Spacer(),
                SkeletonBlock(width: 92, height: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile-shaped placeholder for the customer, staff, and rider profile pages.
class ProfileScreenSkeleton extends StatelessWidget {
  const ProfileScreenSkeleton({super.key, required this.optionCount});

  final int optionCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: SkeletonShimmer(
        child: Column(
          children: [
            const SkeletonBlock(width: 120, height: 120, borderRadius: 60),
            const SizedBox(height: 24),
            const SkeletonBlock(width: 168, height: 22),
            const SizedBox(height: 10),
            const SkeletonBlock(width: 196, height: 14),
            const SizedBox(height: 40),
            ...List.generate(
              optionCount,
              (index) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE7EBEF)),
                ),
                child: Row(
                  children: const [
                    SkeletonBlock(width: 22, height: 22, borderRadius: 6),
                    SizedBox(width: 16),
                    Expanded(child: SkeletonBlock(height: 16)),
                    SizedBox(width: 12),
                    SkeletonBlock(width: 8, height: 12, borderRadius: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const SkeletonBlock(
              width: double.infinity,
              height: 48,
              borderRadius: 12,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Form-shaped placeholder for profile account details screens.
class AccountDetailsSkeleton extends StatelessWidget {
  const AccountDetailsSkeleton({super.key, this.showAddressSection = false});

  final bool showAddressSection;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Row(
                children: const [
                  SkeletonBlock(width: 60, height: 60, borderRadius: 30),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBlock(width: 148, height: 18),
                        SizedBox(height: 9),
                        SkeletonBlock(width: 112, height: 18, borderRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeading(),
            const SizedBox(height: 8),
            _buildInfoCard(4),
            if (showAddressSection) ...[
              const SizedBox(height: 24),
              _buildSectionHeading(),
              const SizedBox(height: 8),
              _buildInfoCard(3),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeading() {
    return Row(
      children: const [
        SkeletonBlock(width: 18, height: 18, borderRadius: 5),
        SizedBox(width: 8),
        Expanded(child: SkeletonBlock(height: 15)),
        SizedBox(width: 12),
        SkeletonBlock(width: 52, height: 24, borderRadius: 8),
      ],
    );
  }

  Widget _buildInfoCard(int rowCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: _cardDecoration(),
      child: Column(
        children: List.generate(
          rowCount,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: const [
                SkeletonBlock(width: 20, height: 20, borderRadius: 6),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBlock(width: 76, height: 10),
                      SizedBox(height: 7),
                      SkeletonBlock(width: 156, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EBEF)),
      );
}

/// Loyalty-card-shaped placeholder used while the linked card is fetched.
class LoyaltyCardScreenSkeleton extends StatelessWidget {
  const LoyaltyCardScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: SkeletonShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7EBEF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SkeletonBlock(width: 118, height: 13),
                      SkeletonBlock(width: 54, height: 22, borderRadius: 8),
                    ],
                  ),
                  SizedBox(height: 26),
                  SkeletonBlock(width: 104, height: 10),
                  SizedBox(height: 8),
                  SkeletonBlock(width: 88, height: 36),
                  SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SkeletonBlock(width: 112, height: 28),
                      SkeletonBlock(width: 84, height: 28),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SkeletonBlock(width: 152, height: 18),
            const SizedBox(height: 12),
            const SkeletonDataCard(),
            const SizedBox(height: 20),
            const SkeletonBlock(
              width: double.infinity,
              height: 48,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}
