import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../models/transaction_model.dart';
import '../services/voice_alert_service.dart';
import '../utils/ocr_receipt_parser.dart';

/// Camera OCR Scanner Screen allowing cashiers to scan GCash or Maya physical/screenshot receipts.
class OcrScannerScreen extends StatefulWidget {
  const OcrScannerScreen({super.key});

  @override
  State<OcrScannerScreen> createState() => _OcrScannerScreenState();
}

class _OcrScannerScreenState extends State<OcrScannerScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isFlashOn = false;
  final VoiceAlertService _voiceAlert = VoiceAlertService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (kIsWeb) return; // Web uses gallery pick fallback or generic input

    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        final backCamera = _cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );

        _cameraController = CameraController(
          backCamera,
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[OcrScannerScreen] Camera initialization error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  /// Toggles device camera flashlight.
  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (e) {
      debugPrint('[OcrScannerScreen] Flash toggle error: $e');
    }
  }

  /// Processes an image from file path using Google ML Kit TextRecognizer.
  Future<void> _processImageFile(String imagePath) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final String rawText = recognizedText.text;

      await textRecognizer.close();

      if (!mounted) return;
      await _handleRecognizedText(rawText);
    } catch (e) {
      debugPrint('[OcrScannerScreen] OCR Text Recognition Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OCR Recognition Error: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Parses recognized raw text, writes to Firestore, triggers Tagalog voice alert, and closes scanner.
  Future<void> _handleRecognizedText(String rawText) async {
    if (rawText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No text recognized in image. Please realign receipt.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final ocrResult = OcrReceiptParser.parse(rawText);

    if (!ocrResult.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ocrResult.errorMessage ?? 'Failed to parse receipt details.'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    final senderName = ocrResult.sender ?? 'JUAN D.';
    final amount = ocrResult.amount;
    final referenceNo = ocrResult.referenceNo ?? 'NO_REF';
    final walletType = ocrResult.walletType;

    // 1. Sync document to Cloud Firestore `transactions` collection
    try {
      await FirebaseFirestore.instance.collection('transactions').add({
        'sender': senderName,
        'message': rawText,
        'amount': amount,
        'reference_no': referenceNo,
        'ref_number': referenceNo,
        'sender_name': senderName,
        'source': walletType,
        'method': 'OCR',
        'isScam': false,
        'threatLevel': 'LOW',
        'status': TransactionStatus.verified.value,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('[OcrScannerScreen] Successfully saved OCR transaction to Firestore.');
    } catch (e) {
      debugPrint('[OcrScannerScreen] Firestore write warning: $e');
    }

    // 2. Trigger Tagalog Voice Alert: "Naka-scan ng resibo mula kay [senderName] para sa [amount] piso."
    await _voiceAlert.speakOcrReceiptAlert(senderName: senderName, amount: amount);

    if (!mounted) return;

    // 3. Return parsed result to previous screen
    Navigator.pop(context, ocrResult);
  }

  /// Captures current camera frame photo.
  Future<void> _captureAndScan() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) {
      return;
    }

    try {
      final XFile photo = await _cameraController!.takePicture();
      await _processImageFile(photo.path);
    } catch (e) {
      debugPrint('[OcrScannerScreen] Camera capture error: $e');
    }
  }

  /// Fallback: Pick receipt image from device gallery.
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await _processImageFile(image.path);
      }
    } catch (e) {
      debugPrint('[OcrScannerScreen] Gallery pick error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan Receipt (OCR)', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_isCameraInitialized)
            IconButton(
              icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: const Color(0xFF00E676)),
              onPressed: _toggleFlash,
            ),
          IconButton(
            icon: const Icon(Icons.photo_library, color: Colors.white),
            tooltip: 'Pick from Gallery',
            onPressed: _pickFromGallery,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Camera View / Preview
          if (_isCameraInitialized && _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.document_scanner, size: 72, color: Color(0xFF00E676)),
                  const SizedBox(height: 16),
                  const Text(
                    'Camera Feed Unavailable',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Upload a receipt screenshot from Gallery to run OCR scanner.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.image),
                    label: const Text('Pick Receipt Image', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // 2. Rectangle Overlay Guide Frame
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.85,
                      height: MediaQuery.of(context).size.height * 0.55,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF00E676), width: 3),
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.transparent,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E676).withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Align Instructions Header
                  Positioned(
                    top: 32,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.center_focus_strong, color: Color(0xFF00E676)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Align GCash or Maya receipt within frame',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Processing Indicator Overlay
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00E676)),
                    SizedBox(height: 20),
                    Text(
                      'Running Google ML Kit OCR...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Extracting Amount, Ref No., & Sender Details',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),

      // 4. Capture Floating Action Button
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton.large(
          onPressed: _isProcessing ? null : _captureAndScan,
          backgroundColor: const Color(0xFF00E676),
          foregroundColor: Colors.black,
          shape: const CircleBorder(),
          child: const Icon(Icons.camera_alt, size: 36),
        ),
      ),
    );
  }
}
