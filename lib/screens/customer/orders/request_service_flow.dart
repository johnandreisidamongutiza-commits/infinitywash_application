import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'dart:io';
import 'dart:convert';
import '../../../theme/app_theme.dart';
import '../../../utils/app_error.dart';
import '../../../utils/input_formatters.dart';
import '../../../utils/permission_manager.dart';
import '../../../utils/validators.dart';
import '../../../widgets/address_input_widget.dart';
import '../../../models/order.dart';
import '../../../services/service_request_service.dart';
import '../../../services/customer_service.dart';
import '../../../services/photo_file_service.dart';
import '../../../widgets/in_app_camera_screen.dart';

class RequestServiceFlow extends StatefulWidget {
  const RequestServiceFlow({super.key});

  @override
  State<RequestServiceFlow> createState() => _RequestServiceFlowState();
}

class _RequestServiceFlowState extends State<RequestServiceFlow> {
  int _currentStep = 1;
  final CollectionMethod _selectedCollection = CollectionMethod.riderPickup;
  ReturnMethod _selectedReturn = ReturnMethod.delivery;
  String _selectedPaymentPreference = 'GCash';
  
  // Photo upload state
  final List<File> _laundryPhotos = [];
  final ImagePicker _imagePicker = ImagePicker();
  final int _maxPhotos = 3;
  
  // Add-ons state
  bool _addExtraFabCon = false;
  bool _addExtraDetergent = false;

  // Active details for this order - loaded from authenticated customer profile
  String _pickupAddress = '';
  String _landmark = '';
  Map<String, dynamic>? _currentCustomer;
  bool _isLoadingAddress = true;
  String? _loadError;

  // 3-part address controllers for inline address form
  final TextEditingController _formHouseStreetCtrl = TextEditingController();
  final TextEditingController _formCustomBarangayCtrl = TextEditingController();
  final TextEditingController _formLandmarkCtrl = TextEditingController();
  String? _formSelectedBarangay;

  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  double _calculateAddonsTotal() {
    double total = 0.0;
    if (_addExtraFabCon) total += 20.0;
    if (_addExtraDetergent) total += 20.0;
    return total;
  }

  @override
  void initState() {
    super.initState();
    _loadCustomerData();
  }

  Future<void> _loadCustomerData() async {
    setState(() {
      _isLoadingAddress = true;
      _loadError = null;
    });

    try {
      final customer = await CustomerService().getCurrentAuthenticatedCustomer();
      if (customer != null) {
        final addr = customer['address'] as String? ?? '';
        final lmark = customer['landmark'] as String? ?? '';
        setState(() {
          _currentCustomer = customer;
          _pickupAddress = addr;
          _landmark = lmark;
          _isLoadingAddress = false;
          if (addr.isNotEmpty) {
            AddressInputWidget.parseAndPopulate(
              address: addr,
              houseStreetController: _formHouseStreetCtrl,
              setBarangay: (b) => _formSelectedBarangay = b,
              customBarangayController: _formCustomBarangayCtrl,
            );
          }
          _formLandmarkCtrl.text = lmark;
        });
      } else {
        setState(() {
          _loadError = 'Unable to load customer profile. Please try again.';
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      setState(() {
        _loadError = mapErrorToMessage(e);
        _isLoadingAddress = false;
      });
    }
  }

  @override
  void dispose() {
    for (final photo in _laundryPhotos) {
      PhotoFileService.deleteTemporary(photo);
    }
    _formHouseStreetCtrl.dispose();
    _formCustomBarangayCtrl.dispose();
    _formLandmarkCtrl.dispose();
    _instructionsController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromCamera() async {
    if (!_canAddPhoto()) return;

    // Explain why the camera is needed before the OS prompt appears.
    if (!mounted) return;
    if (!await PermissionManager.confirmRationale(context, AppPermission.camera)) {
      return;
    }

    try {
      final photo = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => const InAppCameraScreen()),
      );
      if (photo != null && mounted) await _addPhoto(photo);
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (PermissionManager.isPickerPermissionCode(e.code)) {
        await PermissionManager.showDeniedDialog(context, AppPermission.camera);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error taking photo. Please try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error taking photo. Please try again.')),
      );
    }
  }

  Future<void> _pickImageFromGallery() async {
    if (!_canAddPhoto()) return;

    // Explain why the photo library is needed before the OS prompt appears.
    if (!mounted) return;
    if (!await PermissionManager.confirmRationale(context, AppPermission.photos)) {
      return;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );

      if (image != null) {
        await _addPhoto(File(image.path));
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (PermissionManager.isPickerPermissionCode(e.code)) {
        await PermissionManager.showDeniedDialog(context, AppPermission.photos);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error selecting photo. Please try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error selecting photo. Please try again.')),
      );
    }
  }

  bool _canAddPhoto() {
    if (_laundryPhotos.length < _maxPhotos) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Maximum $_maxPhotos photos allowed')),
    );
    return false;
  }

  Future<void> _addPhoto(File source) async {
    try {
      final prepared = await PhotoFileService.prepareForUpload(source);
      if (!mounted) {
        await PhotoFileService.deleteTemporary(prepared);
        return;
      }
      if (_laundryPhotos.length >= _maxPhotos) {
        await PhotoFileService.deleteTemporary(prepared);
        return;
      }
      setState(() => _laundryPhotos.add(prepared));
    } on PhotoTooLargeException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not prepare this photo. Please try another.')),
        );
      }
    }
  }

  void _removePhoto(int index) {
    final photo = _laundryPhotos[index];
    setState(() {
      _laundryPhotos.removeAt(index);
    });
    PhotoFileService.deleteTemporary(photo);
  }

  void _showPhotoSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppTheme.accentBlue),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImageFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppTheme.accentBlue),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImageFromGallery();
                },
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetToProfileAddress() {
    if (_currentCustomer != null) {
      final addr = _currentCustomer!['address'] as String? ?? '';
      final lmark = _currentCustomer!['landmark'] as String? ?? '';
      setState(() {
        _pickupAddress = addr;
        _landmark = lmark;
        if (addr.isNotEmpty) {
          AddressInputWidget.parseAndPopulate(
            address: addr,
            houseStreetController: _formHouseStreetCtrl,
            setBarangay: (b) => _formSelectedBarangay = b,
            customBarangayController: _formCustomBarangayCtrl,
          );
        } else {
          _formHouseStreetCtrl.clear();
          _formSelectedBarangay = null;
          _formCustomBarangayCtrl.clear();
        }
        _formLandmarkCtrl.text = lmark;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset to saved profile address.')),
      );
    }
  }

  void _showEditAddressModal() {
    final houseStreetCtrl = TextEditingController();
    final customBarangayCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController(text: _landmark);
    String? selectedBarangay;

    if (_pickupAddress.isNotEmpty) {
      AddressInputWidget.parseAndPopulate(
        address: _pickupAddress,
        houseStreetController: houseStreetCtrl,
        setBarangay: (b) => selectedBarangay = b,
        customBarangayController: customBarangayCtrl,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.borderGray,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Change Pick-up Details',
                        style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Update your pickup address for this request only.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 16),
                  AddressInputWidget(
                    houseStreetController: houseStreetCtrl,
                    customBarangayController: customBarangayCtrl,
                    landmarkController: landmarkCtrl,
                    selectedBarangay: selectedBarangay,
                    onBarangayChanged: (v) =>
                        setModalState(() => selectedBarangay = v),
                    fillColor: AppTheme.softGray,
                    borderRadius: 16,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final street = houseStreetCtrl.text.trim();
                      if (street.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter your house/unit/street number')),
                        );
                        return;
                      }
                      if (selectedBarangay == null || selectedBarangay!.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select your barangay')),
                        );
                        return;
                      }
                      final full = AddressInputWidget.buildFullAddress(
                        houseStreet: street,
                        selectedBarangay: selectedBarangay,
                        customBarangay: customBarangayCtrl.text.trim(),
                      );
                      setState(() {
                        _pickupAddress = full;
                        _landmark = landmarkCtrl.text.trim();
                        _formHouseStreetCtrl.text = street;
                        _formSelectedBarangay = selectedBarangay;
                        _formCustomBarangayCtrl.text = customBarangayCtrl.text;
                        _formLandmarkCtrl.text = _landmark;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Save for This Order'),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _resetToProfileAddress();
                      },
                      child: const Text(
                        'Use Saved Profile Address',
                        style: TextStyle(color: AppTheme.textLight, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_currentStep == 5 ? 'Request Status' : 'Request Service'),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(_currentStep > 1 && _currentStep < 5 ? Icons.arrow_back : Icons.close, color: AppTheme.textDark),
          onPressed: () {
            if (_currentStep > 1 && _currentStep < 5) {
              setState(() => _currentStep = _currentStep - 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          if (_currentStep < 5) _buildStepProgressBar(),
          Expanded(child: _buildStepContent()),
        ],
      ),
    );
  }

  Widget _buildStepProgressBar() {
    final stepLabels = [
      'Service Options',
      'Laundry Photos',
      'Add-on Services',
      'Address & Review',
    ];
    final currentLabel = _currentStep >= 1 && _currentStep <= 4
        ? stepLabels[_currentStep - 1]
        : '';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step $_currentStep of 4',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textLight,
                ),
              ),
              Text(
                currentLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(4, (index) {
              final isDoneOrCurrent = index < _currentStep;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(
                    left: index == 0 ? 0 : 3,
                    right: index == 3 ? 0 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDoneOrCurrent
                        ? AppTheme.primaryBlue
                        : AppTheme.softGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildServiceSelection();
      case 2:
        return _buildPhotoUpload();
      case 3:
        return _buildAddOnsStep();
      case 4:
        return _buildDetailsForm();
      case 5:
        return _buildWaitingApproval();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildServiceSelection() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collection Method',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Door-to-door laundry pickup from your location.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            _buildConfirmedCollectionCard(),
            const SizedBox(height: 28),
            Text(
              'Return Method',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose how you would like to receive your cleaned laundry.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            _buildReturnMethodCard(
              title: 'Rider Delivery',
              subtitle: 'We will deliver your clean laundry back to your doorstep.',
              badge: 'To Your Door',
              icon: Icons.local_shipping_outlined,
              isSelected: _selectedReturn == ReturnMethod.delivery,
              onTap: () => setState(() => _selectedReturn = ReturnMethod.delivery),
            ),
            const SizedBox(height: 12),
            _buildReturnMethodCard(
              title: 'Shop Pickup',
              subtitle: 'Pick up your fresh laundry directly at our shop counter.',
              badge: 'Self Collect',
              icon: Icons.storefront_outlined,
              isSelected: _selectedReturn == ReturnMethod.shopPickup,
              onTap: () => setState(() => _selectedReturn = ReturnMethod.shopPickup),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: () => setState(() => _currentStep = 2),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoUpload() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Show Us Your Laundry',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Take 1-3 photos of your laundry pile so our staff can estimate the volume and confirm it meets the 2-load minimum.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            
            // Tips Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lightbulb_outline, color: AppTheme.accentBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tips for best results:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildTip('Show all laundry in one pile'),
                  _buildTip('Include any bulky items separately'),
                  _buildTip('Make sure lighting is good'),
                  _buildTip('Use a reference object for scale'),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Photo Grid
            Text(
              'Photos (${_laundryPhotos.length}/$_maxPhotos)',
              style: AppTheme.lightTheme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: _laundryPhotos.length + (_laundryPhotos.length < _maxPhotos ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _laundryPhotos.length) {
                  // Show existing photo
                  return _buildPhotoCard(index);
                } else {
                  // Show add button
                  return _buildAddPhotoButton();
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            // Description field
            Text(
              'Description (Optional)',
              style: AppTheme.lightTheme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'e.g., Mostly regular clothes, 2 bed sheets, and 1 comforter',
                hintStyle: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppTheme.softGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Info note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Staff will review your photos and confirm if it meets the 2-load minimum requirement.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Continue button
            ElevatedButton(
              onPressed: _laundryPhotos.isEmpty ? null : () => setState(() => _currentStep = 3),
              child: const Text('Continue to Add-ons'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14, color: AppTheme.accentBlue)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: () => _showPreparedPhoto(index),
            child: Image.file(
              _laundryPhotos[index],
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddPhotoButton() {
    return GestureDetector(
      onTap: _showPhotoSourceSelector,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.softGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGray, width: 2, style: BorderStyle.solid),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate, color: AppTheme.accentBlue, size: 32),
            SizedBox(height: 4),
            Text(
              'Add Photo',
              style: TextStyle(fontSize: 11, color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreparedPhoto(int index) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.file(_laundryPhotos[index], fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await Gal.putImage(_laundryPhotos[index].path);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Photo saved to your gallery.')),
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not save the photo. Check gallery permission and try again.')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Save to gallery'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _removePhoto(index);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmedCollectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.two_wheeler_rounded,
                  color: AppTheme.primaryBlue,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Rider Pick-up',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Included with Request',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'A rider will be dispatched to your address for laundry collection.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.softGray,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.borderGray.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppTheme.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Minimum 2 loads required for rider collection.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnMethodCard({
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue.withValues(alpha: 0.03)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : AppTheme.borderGray.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppTheme.primaryBlue.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryBlue : AppTheme.softGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : AppTheme.textLight,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isSelected
                              ? AppTheme.primaryBlue
                              : AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                              : AppTheme.softGray,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? AppTheme.primaryBlue
                                : AppTheme.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected ? AppTheme.primaryBlue : AppTheme.borderGray,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOnsStep() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extra Services (Optional)',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Enhance your laundry experience with these add-ons.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            
            // Fabric Conditioner
            _buildAddOnCard(
              title: 'Extra Fabric Conditioner',
              description: 'Makes clothes softer and smell fresher',
              price: 20.0,
              icon: Icons.bubble_chart_outlined,
              value: _addExtraFabCon,
              onChanged: (val) => setState(() => _addExtraFabCon = val!),
            ),
            const SizedBox(height: 16),
            
            // Extra Detergent
            _buildAddOnCard(
              title: 'Extra Detergent',
              description: 'For heavily soiled or stained laundry',
              price: 20.0,
              icon: Icons.local_laundry_service_outlined,
              value: _addExtraDetergent,
              onChanged: (val) => setState(() => _addExtraDetergent = val!),
            ),
            const SizedBox(height: 24),
            
            // Price Summary
            if (_calculateAddonsTotal() > 0) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Add-ons Total:', 
                                     style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('₱${_calculateAddonsTotal().toStringAsFixed(2)}',
                             style: const TextStyle(fontWeight: FontWeight.bold, 
                                                   fontSize: 18, 
                                                   color: AppTheme.accentBlue)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppTheme.accentBlue),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Base price will be calculated after staff weighs your laundry',
                            style: TextStyle(fontSize: 11, color: AppTheme.textDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            
            // Continue Button
            ElevatedButton(
              onPressed: () => setState(() => _currentStep = 4),
              child: const Text('Continue to Details'),
            ),
            const SizedBox(height: 12),
            
            // Skip Button
            TextButton(
              onPressed: () => setState(() => _currentStep = 4),
              child: const Text('Skip Add-ons'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOnCard({
    required String title,
    required String description,
    required double price,
    required IconData icon,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? AppTheme.accentBlue : AppTheme.borderGray,
          width: value ? 2 : 1,
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: value 
                    ? AppTheme.accentBlue.withValues(alpha: 0.1) 
                    : AppTheme.softGray,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, 
                         color: value ? AppTheme.accentBlue : AppTheme.textLight, 
                         size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, 
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(description, 
                       style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
                ],
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 44, top: 4),
          child: Text(
            '₱${price.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: value ? AppTheme.accentBlue : AppTheme.textDark,
              fontSize: 14,
            ),
          ),
        ),
        activeColor: AppTheme.accentBlue,
        controlAffinity: ListTileControlAffinity.trailing,
      ),
    );
  }

  Widget _buildDetailsForm() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick-up & Contact Details',
              style: AppTheme.lightTheme.textTheme.headlineMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 6),
            Text(
              'Confirm where our rider should collect your laundry.',
              style: AppTheme.lightTheme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),

            // Saved Profile Location Card
            _buildSavedLocationCard(),

            const SizedBox(height: 20),

            // Service Summary Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, color: AppTheme.accentBlue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Selected Service',
                          style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                        ),
                        Text(
                          'Rider Pick-up  •  ${_selectedReturn == ReturnMethod.delivery ? 'Rider Delivery' : 'Shop Pickup'}  •  ${_laundryPhotos.length} photo${_laundryPhotos.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 2),
                        child: const Text(
                          'View Photos',
                          style: TextStyle(color: AppTheme.accentBlue, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Text('•', style: TextStyle(color: AppTheme.textLight)),
                      TextButton(
                        onPressed: () => setState(() => _currentStep = 1),
                        child: const Text(
                          'Change',
                          style: TextStyle(color: AppTheme.accentBlue, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Special Instructions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Special Instructions', style: AppTheme.lightTheme.textTheme.titleMedium),
                const Text('Optional', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionsController,
              maxLines: 3,
              inputFormatters:
                  InputFormatters.text(maxLength: Validators.notesMax),
              decoration: InputDecoration(
                hintText: 'e.g. Separate whites, delicate garments, ring doorbell twice...',
                hintStyle: TextStyle(color: AppTheme.textLight.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppTheme.softGray,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 24),

            // Payment Method Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Payment Method',
                    style: AppTheme.lightTheme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Pay After Weighing',
                    style: TextStyle(
                      color: AppTheme.accentBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Select your preferred way to pay once our staff verifies your laundry weight.',
              style: TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
            const SizedBox(height: 12),

            // GCash Option
            GestureDetector(
              onTap: () => setState(() => _selectedPaymentPreference = 'GCash'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedPaymentPreference == 'GCash' ? AppTheme.accentBlue : AppTheme.borderGray,
                    width: _selectedPaymentPreference == 'GCash' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _selectedPaymentPreference == 'GCash' ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.accentBlue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GCash / E-Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(height: 2),
                          Text('Pay via QR or number once weighed', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                        ],
                      ),
                    ),
                    Icon(
                      _selectedPaymentPreference == 'GCash' ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _selectedPaymentPreference == 'GCash' ? AppTheme.accentBlue : AppTheme.textLight,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Cash on Delivery Option
            GestureDetector(
              onTap: () => setState(() => _selectedPaymentPreference = 'Cash on Delivery'),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedPaymentPreference == 'Cash on Delivery' ? AppTheme.accentBlue : AppTheme.borderGray,
                    width: _selectedPaymentPreference == 'Cash on Delivery' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _selectedPaymentPreference == 'Cash on Delivery' ? AppTheme.accentBlue.withValues(alpha: 0.1) : AppTheme.softGray,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.payments_outlined, color: Colors.green, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cash on Delivery / Pickup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(height: 2),
                          Text('Pay cash to rider upon delivery', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                        ],
                      ),
                    ),
                    Icon(
                      _selectedPaymentPreference == 'Cash on Delivery' ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _selectedPaymentPreference == 'Cash on Delivery' ? AppTheme.accentBlue : AppTheme.textLight,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Official Pricing Card (₱170 Full Service)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_laundry_service_outlined, color: AppTheme.accentBlue, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'FULL SERVICE: Wash, Dry & Fold',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '₱170.00',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '✓ Detergent + Fab Con included with every full service load.',
                    style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Load limits: Regular 8kg • Heavy 6kg • Beddings 5kg • Comforter 1pc',
                    style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Submit Button
            ElevatedButton(
              onPressed: _isLoadingAddress ? null : () async {
                if (_currentCustomer == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Unable to submit: Customer profile not loaded')),
                  );
                  return;
                }

                // Validate address is not empty
                if (_pickupAddress.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter your pickup address')),
                  );
                  return;
                }

                final String fullNote = [
                  if (_landmark.isNotEmpty) 'Landmark: $_landmark',
                  if (_instructionsController.text.trim().isNotEmpty) _instructionsController.text.trim(),
                  'Payment: $_selectedPaymentPreference',
                ].join(' | ');

                try {
                  // Show loading indicator
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => const Center(child: CircularProgressIndicator()),
                  );

                  // Save address to customer profile if it's new or changed
                  final profileAddress = _currentCustomer?['address'] as String? ?? '';
                  final profileLandmark = _currentCustomer?['landmark'] as String? ?? '';
                  if (_pickupAddress != profileAddress || _landmark != profileLandmark) {
                    final customerId = _currentCustomer!['id'] as String;
                    await CustomerService().updateCustomer(
                      customerId: customerId,
                      address: _pickupAddress,
                      landmark: _landmark.isNotEmpty ? _landmark : null,
                    );
                    print('✅ Saved address to customer profile');
                  }

                  // Convert photos to base64 data URIs so they can be viewed across all devices
                  final photoDataUrls = <String>[];
                  for (final file in _laundryPhotos) {
                    try {
                      final bytes = await file.readAsBytes();
                      photoDataUrls.add('data:image/jpeg;base64,${base64Encode(bytes)}');
                    } catch (e) {
                      print('⚠️ Error encoding photo: $e');
                      photoDataUrls.add(file.path);
                    }
                  }

                  // Prepare add-ons list
                  final List<Map<String, dynamic>> addons = [];
                  if (_addExtraFabCon) {
                    addons.add({
                      'addon_code': 'extra-fabric-conditioner',
                      'quantity': 1,
                    });
                  }
                  if (_addExtraDetergent) {
                    addons.add({
                      'addon_code': 'extra-detergent',
                      'quantity': 1,
                    });
                  }

                  // Submit the request using authenticated method
                  await ServiceRequestService().submitAuthenticatedServiceRequest(
                    collectionMethod: _selectedCollection,
                    returnMethod: _selectedReturn,
                    pickupAddress: _pickupAddress,
                    landmark: _landmark.isNotEmpty ? _landmark : null,
                    instructions: 'Pickup Address: $_pickupAddress${fullNote.isNotEmpty ? ' ($fullNote)' : ''}',
                    paymentPreference: _selectedPaymentPreference,
                    photoUrls: photoDataUrls,
                    customerDescription: _descriptionController.text.trim().isNotEmpty 
                        ? _descriptionController.text.trim() 
                        : null,
                    addons: addons,
                  );

                  for (final photo in _laundryPhotos) {
                    await PhotoFileService.deleteTemporary(photo);
                  }

                  // Close loading dialog
                  if (!mounted) return;
                  Navigator.of(context).pop();

                  // Move to success screen
                  setState(() => _currentStep = 5);
                } catch (e) {
                  // Close loading dialog
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(mapErrorToMessage(e)),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Submit Request'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedLocationCard() {
    if (_isLoadingAddress) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: AppStyles.cardDecoration,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppStyles.cardDecoration,
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 48),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.errorRed),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadCustomerData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Get customer details from the map
    final firstName = _currentCustomer?['first_name'] as String? ?? '';
    final lastName = _currentCustomer?['last_name'] as String? ?? '';
    final customerName = lastName.isNotEmpty ? '$firstName $lastName' : firstName;
    final customerPhone = _currentCustomer?['phone'] as String? ?? 'N/A';
    
    final profileAddress = _currentCustomer?['address'] as String? ?? '';
    final profileLandmark = _currentCustomer?['landmark'] as String? ?? '';
    final isCustomAddress = _currentCustomer != null && 
        (_pickupAddress != profileAddress || _landmark != profileLandmark);

    // If no saved address, show form to collect it
    if (profileAddress.isEmpty && !isCustomAddress) {
      return _buildAddressForm();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isCustomAddress
                      ? AppTheme.teamMemberIconOrange.withValues(alpha: 0.12)
                      : AppTheme.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCustomAddress ? Icons.edit_location_alt : Icons.home_outlined,
                      size: 14,
                      color: isCustomAddress ? AppTheme.teamMemberIconOrange : AppTheme.accentBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isCustomAddress ? 'Custom Address (This Order)' : 'Saved Profile Address',
                      style: TextStyle(
                        color: isCustomAddress ? AppTheme.teamMemberIconOrange : AppTheme.accentBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _showEditAddressModal,
                icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.accentBlue),
                label: const Text(
                  'Change',
                  style: TextStyle(color: AppTheme.accentBlue, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Customer Name & Phone
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18, color: AppTheme.textLight),
              const SizedBox(width: 10),
              Text(
                customerName.isEmpty ? 'Unknown' : customerName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textDark),
              ),
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: AppTheme.textLight)),
              const SizedBox(width: 8),
              Text(
                customerPhone,
                style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Address
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.errorRed),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pickupAddress.isEmpty ? 'No address set' : _pickupAddress,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textDark),
                    ),
                    if (_landmark.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Landmark: $_landmark',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isCustomAddress) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _resetToProfileAddress,
                child: const Text(
                  'Reset to default profile address',
                  style: TextStyle(fontSize: 11, color: AppTheme.accentBlue, decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Set Your Pickup Address',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Please enter your address where our rider should pick up your laundry. This will be saved to your profile.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
          ),
          const SizedBox(height: 16),
          AddressInputWidget(
            houseStreetController: _formHouseStreetCtrl,
            customBarangayController: _formCustomBarangayCtrl,
            landmarkController: _formLandmarkCtrl,
            selectedBarangay: _formSelectedBarangay,
            onBarangayChanged: (v) =>
                setState(() => _formSelectedBarangay = v),
            fillColor: Colors.white,
            borderRadius: 16,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              final street = _formHouseStreetCtrl.text.trim();
              if (street.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter your house/unit/street number')),
                );
                return;
              }
              if (_formSelectedBarangay == null || _formSelectedBarangay!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select your barangay')),
                );
                return;
              }
              final full = AddressInputWidget.buildFullAddress(
                houseStreet: street,
                selectedBarangay: _formSelectedBarangay,
                customBarangay: _formCustomBarangayCtrl.text.trim(),
              );
              setState(() {
                _pickupAddress = full;
                _landmark = _formLandmarkCtrl.text.trim();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Address set! This will be saved when you submit your request.')),
              );
            },
            child: const Text('Save Address'),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingApproval() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, size: 48, color: Colors.green),
            ),
            const SizedBox(height: 16),
            Text('Request Placed!', style: AppTheme.lightTheme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text(
              'Your laundry pickup request has been dispatched to InfinityWash.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textLight, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // Order Timeline Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.softGray,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Order Progress',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textDark),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _selectedPaymentPreference,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentBlue),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Step 1: Request Confirmed
                  _buildTimelineItem(
                    icon: Icons.check_circle,
                    iconColor: Colors.green,
                    title: '1. Request Received',
                    subtitle: 'Our branch is coordinating rider pickup for your address.',
                    isDone: true,
                  ),
                  const SizedBox(height: 16),

                  // Step 2: Pickup & Store Weighing
                  _buildTimelineItem(
                    icon: Icons.scale_outlined,
                    iconColor: AppTheme.accentBlue,
                    title: '2. Pickup & Store Inspection',
                    subtitle: 'Laundry will be verified on our store scale (Full Service: ₱170.00 / load).',
                    isActive: true,
                  ),
                  const SizedBox(height: 16),

                  // Step 3: Verified Bill & Payment
                  _buildTimelineItem(
                    icon: Icons.receipt_long_outlined,
                    iconColor: AppTheme.textLight,
                    title: '3. Verified Bill & Payment',
                    subtitle: _selectedPaymentPreference == 'GCash'
                        ? 'You will receive an alert to review verified weight and pay via GCash.'
                        : 'Exact cash total will be confirmed for payment upon delivery.',
                    isPending: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true); // Return true to trigger refresh
              },
              child: const Text('View in Active Orders'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true); // Return true to trigger refresh
              },
              child: const Text(
                'Back to Home',
                style: TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool isDone = false,
    bool isActive = false,
    bool isPending = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isPending ? 0.08 : 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isPending ? AppTheme.textLight : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isPending ? AppTheme.textLight.withValues(alpha: 0.7) : AppTheme.textLight,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
