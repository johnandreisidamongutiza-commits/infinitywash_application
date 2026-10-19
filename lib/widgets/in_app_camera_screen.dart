import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/permission_manager.dart';

/// Camera capture UI rendered inside InfinityWash.
class InAppCameraScreen extends StatefulWidget {
  const InAppCameraScreen({super.key});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _initializing = true;
  bool _takingPhoto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', 'No camera found');
      _cameras = cameras;
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _initializing = false);
    } on CameraException catch (error) {
      if (!mounted) return;
      if (error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt') {
        await PermissionManager.showDeniedDialog(
          context,
          AppPermission.camera,
          deniedForever: error.code == 'CameraAccessDeniedWithoutPrompt',
        );
      }
      setState(() {
        _error = error.code == 'CameraAccessDenied'
            ? 'Camera access is off. Allow camera access in your device settings, then try again.'
            : 'The camera could not be opened. Please try again.';
        _initializing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The camera could not be opened. Please try again.';
        _initializing = false;
      });
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) await controller.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _takingPhoto) {
      return;
    }
    setState(() => _takingPhoto = true);
    try {
      final captured = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(File(captured.path));
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not take the photo. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _takingPhoto) return;
    final current = _controller?.description;
    final next = _cameras.firstWhere(
      (camera) => camera.name != current?.name,
      orElse: () => _cameras.first,
    );
    setState(() => _initializing = true);
    await _disposeCamera();
    try {
      final controller = CameraController(
        next,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _initializing = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not switch cameras. Please try again.';
          _initializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Take a photo'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.camera_alt_outlined,
                                color: Colors.white70, size: 44),
                            const SizedBox(height: 12),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _initializeCamera,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      )
                    : _initializing || controller == null ||
                            !controller.value.isInitialized
                        ? const CircularProgressIndicator(color: Colors.white)
                        : _buildSquarePreview(controller),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: _cameras.length > 1 ? _switchCamera : null,
                    tooltip: 'Switch camera',
                    color: Colors.white,
                    icon: const Icon(Icons.flip_camera_android, size: 30),
                  ),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: FloatingActionButton(
                      heroTag: 'capture_photo',
                      backgroundColor: AppTheme.accentBlue,
                      onPressed: _initializing || _error != null || _takingPhoto
                          ? null
                          : _capture,
                      child: _takingPhoto
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.camera_alt, size: 30),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquarePreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                // Swap the sensor dimensions so the portrait preview is upright.
                width: previewSize.height,
                height: previewSize.width,
                child: CameraPreview(controller),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
