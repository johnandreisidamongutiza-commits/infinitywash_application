import 'package:flutter/material.dart';
import 'dart:io';
import '../../../theme/app_theme.dart';
import '../../../models/order.dart';
import 'create_order_flow.dart';
import 'order_status_screen.dart';
import '../../../services/mock_data_service.dart';

class OrdersScreen extends StatefulWidget {
  final int initialTab;
  const OrdersScreen({super.key, this.initialTab = 1});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestCount = MockDataService().pendingRequests.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.accentBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textLight,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              dividerHeight: 0,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Requests'),
                      if (requestCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$requestCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Active'),
                const Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRequestsTab(),
          _buildActiveTab(),
          _buildHistoryTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateOrderFlow()),
          );
          setState(() {});
        },
        backgroundColor: AppTheme.accentBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // ========== REQUESTS TAB ==========

  Widget _buildRequestsTab() {
    final requests = MockDataService().pendingRequests;

    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.online_prediction, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No pending online requests', style: TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 8),
            Text(
              'New requests from customers will appear here.',
              style: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: requests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildRequestCard(requests[index]),
    );
  }

  Widget _buildRequestCard(LaundryOrder request) {
    final bool hasPhotos = request.laundryPhotoUrls != null && request.laundryPhotoUrls!.isNotEmpty;
    final bool isExpired = request.expiresAt != null && DateTime.now().isAfter(request.expiresAt!);
    final bool isUnderReview = request.underReviewBy != null;
    final Duration? timeRemaining = request.expiresAt?.difference(DateTime.now());
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration.copyWith(
        border: Border.all(
          color: isExpired ? Colors.red.withValues(alpha: 0.3) : 
                 isUnderReview ? Colors.orange.withValues(alpha: 0.3) : 
                 AppTheme.borderGray,
          width: isExpired || isUnderReview ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with ID and badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  request.id,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                ),
              ),
              Row(
                children: [
                  _buildBadge(request.collectionText, AppTheme.accentBlue),
                  const SizedBox(width: 6),
                  _buildBadge(request.returnText, Colors.green),
                ],
              ),
            ],
          ),
          
          // Expiration/Review status
          if (isExpired || isUnderReview || timeRemaining != null) ...[
            const SizedBox(height: 8),
            if (isExpired)
              _buildWarningBanner('⏰ EXPIRED - Review Required', Colors.red)
            else if (isUnderReview)
              _buildWarningBanner('👤 Under review by ${request.underReviewBy}', Colors.orange)
            else if (timeRemaining != null && timeRemaining.inHours < 6)
              _buildWarningBanner(
                '⏳ Expires in ${timeRemaining.inHours}h ${timeRemaining.inMinutes.remainder(60)}m',
                timeRemaining.inHours < 2 ? Colors.red : Colors.orange,
              ),
          ],
          
          const SizedBox(height: 12),
          
          // Customer info
          Text(request.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
          if (request.customerPhone != null) ...[
            const SizedBox(height: 4),
            Text('📱 ${request.customerPhone}', style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
          ],
          if (request.deliveryAddress != null) ...[
            const SizedBox(height: 4),
            Text('📍 ${request.deliveryAddress}', style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
            if (request.deliveryLandmark != null)
              Text('   ${request.deliveryLandmark}', style: const TextStyle(fontSize: 11, color: AppTheme.textLight, fontStyle: FontStyle.italic)),
          ],
          
          // Photos section (if available)
          if (hasPhotos) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.photo_library, size: 16, color: AppTheme.accentBlue),
                const SizedBox(width: 6),
                Text(
                  'PHOTOS (${request.laundryPhotoUrls!.length})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                ),
                const Spacer(),
                if (request.laundryPhotoUrls!.length > 1)
                  TextButton(
                    onPressed: () => _showPhotoGallery(context, request.laundryPhotoUrls!, 0),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View All', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildPhotoLayout(request.laundryPhotoUrls!),
          ],
          
          // Customer description
          if (request.customerDescription != null && request.customerDescription!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 14, color: AppTheme.textLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.customerDescription!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textDark, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Instructions/notes (old field)
          if (request.instructions != null && request.instructions!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Note: ${request.instructions}',
              style: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          
          const SizedBox(height: 16),
          
          // Action button
          if (isUnderReview)
            OutlinedButton(
              onPressed: null,
              child: const Text('Under Review by Another Staff'),
            )
          else
            ElevatedButton(
              onPressed: () => _showPhotoReviewModal(request),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
              child: const Text('REVIEW REQUEST'),
            ),
        ],
      ),
    );
  }
  
  Widget _buildWarningBanner(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPhotoThumbnail(String photoPath, double size) {
    // Handle infinity or NaN sizes
    final validSize = (size.isInfinite || size.isNaN) ? null : size;
    
    // For now, use mock images from assets
    // Later can switch to Image.network() for cloud URLs
    if (photoPath.startsWith('assets/')) {
      return Image.asset(
        photoPath,
        width: validSize,
        height: validSize,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPhotoPlaceholder(size),
      );
    } else if (photoPath.startsWith('http')) {
      return Image.network(
        photoPath,
        width: validSize,
        height: validSize,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPhotoPlaceholder(size),
      );
    } else {
      // Local file path (for real implementation)
      return Image.file(
        File(photoPath),
        width: validSize,
        height: validSize,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPhotoPlaceholder(size),
      );
    }
  }
  
  Widget _buildPhotoLayout(List<String> photos) {
    final photoCount = photos.length;
    
    if (photoCount == 1) {
      // Single photo - large display
      return GestureDetector(
        onTap: () => _showPhotoGallery(context, photos, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _buildPhotoThumbnail(photos[0], double.infinity),
        ),
      );
    } else if (photoCount == 2) {
      // Two photos - side by side
      return Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _showPhotoGallery(context, photos, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _buildPhotoThumbnail(photos[0], double.infinity),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _showPhotoGallery(context, photos, 1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _buildPhotoThumbnail(photos[1], double.infinity),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      // Three or more photos - grid layout
      return Column(
        children: [
          // First row - 2 photos
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showPhotoGallery(context, photos, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _buildPhotoThumbnail(photos[0], double.infinity),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showPhotoGallery(context, photos, 1),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _buildPhotoThumbnail(photos[1], double.infinity),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Second row - remaining photo(s)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showPhotoGallery(context, photos, 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: photoCount > 3
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildPhotoThumbnail(photos[2], double.infinity),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '+${photoCount - 2}\nmore',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _buildPhotoThumbnail(photos[2], double.infinity),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()), // Empty space for symmetry
            ],
          ),
        ],
      );
    }
  }
  
  Widget _buildPhotoPlaceholder(double size) {
    // Handle infinity or NaN sizes
    final validSize = (size.isInfinite || size.isNaN) ? null : size;
    
    return Container(
      width: validSize,
      height: validSize,
      color: AppTheme.softGray,
      child: const Icon(Icons.image_not_supported, color: AppTheme.textLight),
    );
  }

  void _showPhotoReviewModal(LaundryOrder request) {
    // Lock this request to current staff
    final String currentStaff = 'Staff User'; // TODO: Get from auth/session
    MockDataService().lockRequestForReview(request.id, currentStaff);
    setState(() {}); // Refresh UI to show lock
    
    int currentPhotoIndex = 0;
    final photos = request.laundryPhotoUrls ?? [];
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.accentBlue, AppTheme.accentBlue.withValues(alpha: 0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.photo_library, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Review Request',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              request.id,
                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          MockDataService().unlockRequest(request.id);
                          Navigator.pop(context);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer Details Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.softGray,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person_outline, size: 18, color: AppTheme.accentBlue),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Customer Details',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildDetailRow('Name', request.customerName),
                              if (request.customerPhone != null)
                                _buildDetailRow('Phone', request.customerPhone!),
                              if (request.deliveryAddress != null)
                                _buildDetailRow('Address', request.deliveryAddress!),
                              if (request.deliveryLandmark != null)
                                _buildDetailRow('Landmark', request.deliveryLandmark!),
                              _buildDetailRow('Service', '${request.collectionText} → ${request.returnText}'),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Photos Section
                        if (photos.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.photo_camera, size: 18, color: AppTheme.accentBlue),
                              const SizedBox(width: 8),
                              const Text(
                                'Laundry Photos',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                              ),
                              const Spacer(),
                              if (photos.length > 1)
                                Text(
                                  '${currentPhotoIndex + 1}/${photos.length}',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => _showPhotoGallery(context, photos, currentPhotoIndex),
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.borderGray),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    _buildPhotoThumbnail(photos[currentPhotoIndex], 200),
                                    Positioned(
                                      bottom: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.zoom_in, size: 14, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text('Tap to enlarge', style: TextStyle(color: Colors.white, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (photos.length > 1) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.arrow_back_ios,
                                    size: 16,
                                    color: currentPhotoIndex > 0 ? AppTheme.accentBlue : AppTheme.textLight,
                                  ),
                                  onPressed: currentPhotoIndex > 0
                                      ? () => setModalState(() => currentPhotoIndex--)
                                      : null,
                                ),
                                ...List.generate(
                                  photos.length > 5 ? 5 : photos.length,
                                  (index) => Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: index == currentPhotoIndex ? 24 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: index == currentPhotoIndex ? AppTheme.accentBlue : AppTheme.borderGray,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                if (photos.length > 5)
                                  Text(' +${photos.length - 5}', style: const TextStyle(fontSize: 10, color: AppTheme.textLight)),
                                IconButton(
                                  icon: Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: currentPhotoIndex < photos.length - 1 ? AppTheme.accentBlue : AppTheme.textLight,
                                  ),
                                  onPressed: currentPhotoIndex < photos.length - 1
                                      ? () => setModalState(() => currentPhotoIndex++)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],
                        
                        // Customer Description
                        if (request.customerDescription != null && request.customerDescription!.isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.chat_bubble_outline, size: 18, color: AppTheme.accentBlue),
                              const SizedBox(width: 8),
                              const Text(
                                'Customer Description',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textDark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              request.customerDescription!,
                              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppTheme.textDark),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Action Buttons
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.softGray,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showRejectionModal(context, request),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red, width: 2),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.close, size: 20),
                          label: const Text('Reject', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => _approveRequest(context, request),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.check_circle, size: 20),
                          label: const Text('Approve', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
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
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showPhotoGallery(BuildContext context, List<String> photos, int initialIndex) {
    int currentIndex = initialIndex;
    
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => StatefulBuilder(
        builder: (context, setGalleryState) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              // Photo viewer with swipe
              Center(
                child: PageView.builder(
                  itemCount: photos.length,
                  controller: PageController(initialPage: initialIndex),
                  onPageChanged: (index) => setGalleryState(() => currentIndex = index),
                  itemBuilder: (context, index) => Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: _buildPhotoThumbnail(photos[index], double.infinity),
                    ),
                  ),
                ),
              ),
              
              // Top bar with counter and close button
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${currentIndex + 1} / ${photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Navigation arrows (if multiple photos)
              if (photos.length > 1) ...[
                // Left arrow
                if (currentIndex > 0)
                  Positioned(
                    left: 20,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 24),
                        ),
                        onPressed: () {
                          if (currentIndex > 0) {
                            setGalleryState(() => currentIndex--);
                            // Animate to previous page
                          }
                        },
                      ),
                    ),
                  ),
                
                // Right arrow
                if (currentIndex < photos.length - 1)
                  Positioned(
                    right: 20,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 24),
                        ),
                        onPressed: () {
                          if (currentIndex < photos.length - 1) {
                            setGalleryState(() => currentIndex++);
                            // Animate to next page
                          }
                        },
                      ),
                    ),
                  ),
              ],
              
              // Bottom instruction
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      photos.length > 1 ? 'Swipe or use arrows to navigate • Pinch to zoom' : 'Pinch to zoom',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
  void _approveRequest(BuildContext context, LaundryOrder request) {
    // Approve without load estimation - loads will be determined at pickup
    MockDataService().approvePhotoRequest(request.id, 0, null); // 0 loads = TBD at pickup
    Navigator.pop(context); // Close modal
    setState(() {}); // Refresh list
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Request approved! Moved to Active Orders.'),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  void _showRejectionModal(BuildContext parentContext, LaundryOrder request) {
    String selectedReason = 'Below 2-load minimum';
    final messageController = TextEditingController(
      text: 'Your laundry appears to be about 1 load (8-10kg). We require minimum 2 loads for pickup/delivery service. You can drop it off at our shop anytime for 1-load service! Thank you for understanding.',
    );
    
    final reasons = [
      'Below 2-load minimum',
      'Photos unclear - cannot estimate volume',
      'Cannot service this area currently',
      'Special handling items not accepted',
      'Other reason (specify in message)',
    ];
    
    showDialog(
      context: parentContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('❌ Reject Request', style: TextStyle(fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request: ${request.id}', style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
                const SizedBox(height: 16),
                const Text('Reason for Rejection:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // ignore: deprecated_member_use
                Column(
                  children: reasons.map((reason) => InkWell(
                    onTap: () => setModalState(() {
                      selectedReason = reason;
                      // Update default message based on reason
                      if (reason == 'Below 2-load minimum') {
                        messageController.text = 'Your laundry appears to be about 1 load (8-10kg). We require minimum 2 loads for pickup/delivery service. You can drop it off at our shop anytime for 1-load service!';
                      } else if (reason == 'Photos unclear - cannot estimate volume') {
                        messageController.text = 'We cannot accurately estimate your laundry volume from the photos. Please take clearer photos showing all items or visit our shop for in-person assessment.';
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // ignore: deprecated_member_use
                          Radio<String>(
                            value: reason,
                            // ignore: deprecated_member_use
                            groupValue: selectedReason,
                            // ignore: deprecated_member_use
                            onChanged: (val) => setModalState(() {
                              selectedReason = val!;
                              // Update default message based on reason  
                              if (val == 'Below 2-load minimum') {
                                messageController.text = 'Your laundry appears to be about 1 load (8-10kg). We require minimum 2 loads for pickup/delivery service. You can drop it off at our shop anytime for 1-load service!';
                              } else if (val == 'Photos unclear - cannot estimate volume') {
                                messageController.text = 'We cannot accurately estimate your laundry volume from the photos. Please take clearer photos showing all items or visit our shop for in-person assessment.';
                              }
                            }),
                          ),
                          Expanded(
                            child: Text(reason, style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Message to Customer (Required):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    hintText: 'Explain why the request is being rejected...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: messageController.text.trim().isEmpty
                  ? null
                  : () {
                      MockDataService().rejectRequest(request.id, selectedReason, messageController.text.trim());
                      Navigator.pop(context); // Close rejection modal
                      Navigator.pop(parentContext); // Close review modal
                      setState(() {}); // Refresh list
                      
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(
                          content: Text('Request rejected and customer notified'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('CONFIRM REJECTION', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ========== ACTIVE TAB ==========

  Widget _buildActiveTab() {
    final orders = MockDataService().activeOrders;

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No active orders', style: TextStyle(color: AppTheme.textLight)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildOrderCard(orders[index]),
    );
  }

  Widget _buildOrderCard(LaundryOrder order) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OrderStatusScreen(order: order)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentBlue)),
                _buildStatusBadge(order.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20, color: AppTheme.textLight),
                const SizedBox(width: 8),
                Expanded(child: Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(order.weightDisplay, style: AppTheme.lightTheme.textTheme.bodyMedium),
                    if (order.hasMultipleLoads) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${order.totalLoads} loads',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                        ),
                      ),
                    ],
                    if (order.rfidTag != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.nfc_outlined, size: 14, color: AppTheme.accentBlue.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text(
                        order.rfidTag!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.accentBlue, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
                Text(
                  order.paymentStatus == PaymentStatus.paid ? 'PAID' : 'UNPAID',
                  style: TextStyle(
                    color: order.paymentStatus == PaymentStatus.paid ? Colors.green : AppTheme.errorRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            // Show load statuses for multi-load orders
            if (order.hasMultipleLoads) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.softGray,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: order.loads.map((load) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          children: [
                            Text(
                              load.statusIcon,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'L${load.loadNumber}',
                              style: const TextStyle(fontSize: 9, color: AppTheme.textLight, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ========== HISTORY TAB ==========

  Widget _buildHistoryTab() {
    // Mock completed orders
    final List<LaundryOrder> history = [
      LaundryOrder(
        id: 'IW-999',
        customerName: 'Jane Smith',
        channel: OrderChannel.walkIn,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        loads: [
          OrderLoad(
            loadNumber: 1,
            category: 'Regular Clothing',
            weight: 4.0,
            categoryLimit: 8.0,
            unit: 'kg',
            description: 'T-shirts, shorts, sleeveless, socks, underwear',
            isOverLimit: false,
            loadStatus: LoadStatus.folded,
          ),
        ],
        rfidTag: 'RFID-002',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      LaundryOrder(
        id: 'IW-998',
        customerName: 'Bob Brown',
        channel: OrderChannel.online,
        collectionMethod: CollectionMethod.riderPickup,
        returnMethod: ReturnMethod.delivery,
        status: OrderStatus.completed,
        paymentStatus: PaymentStatus.paid,
        loads: [
          OrderLoad(
            loadNumber: 1,
            category: 'Heavy Clothing',
            weight: 7.2,
            categoryLimit: 6.0,
            unit: 'kg',
            description: 'Jeans, cargo, jackets, sweaters, corduroy',
            isOverLimit: true,
            loadStatus: LoadStatus.folded,
          ),
        ],
        rfidTag: 'RFID-004',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: AppTheme.textLight.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            const Text('No completed orders yet', style: TextStyle(color: AppTheme.textLight)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: history.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final order = history[index];
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: AppStyles.cardDecoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.green),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.customerName, style: AppTheme.lightTheme.textTheme.titleMedium),
                    Text('Order ${order.id} • ${order.weightDisplay}', style: AppTheme.lightTheme.textTheme.bodyMedium),
                  ],
                ),
              ),
              Text(
                '₱${order.basePrice.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }

  // ========== SHARED WIDGETS ==========

  Widget _buildStatusBadge(OrderStatus status) {
    Color color;
    switch (status) {
      case OrderStatus.pending_approval: color = Colors.grey; break;
      case OrderStatus.rejected: color = Colors.red; break;
      case OrderStatus.pending_pickup: color = Colors.amber; break;
      case OrderStatus.processing: color = Colors.blue; break;
      case OrderStatus.ready: color = AppTheme.errorRed; break;
      case OrderStatus.out_for_delivery: color = Colors.cyan; break;
      case OrderStatus.completed: color = Colors.green; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}
