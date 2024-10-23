import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:fac/database/database_service.dart';
import 'package:fac/facerecongnition.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({Key? key}) : super(key: key);

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _employeeIdController = TextEditingController();
  final FaceRecognitionService _recognitionService = FaceRecognitionService();
  final DatabaseService _databaseService = DatabaseService();

  late AnimationController _animationController;
  late Animation<double> _animation;

  CameraController? _cameraController;
  List<File> capturedImages = [];
  List<List<double>> faceEmbeddings = [];
  int currentStep = 0;
  final int totalSteps = 7;
  String _statusMessage = '';
  bool _isProcessing = false;
  bool _isCameraInitialized = false;
  bool _isShowingGuide = false;
  double _captureProgress = 0.0;

  @override
  void initState() {
    super.initState();
    print("Initializing Registration Screen");
    _initializeCamera();
    _initializeService();
    _initializeAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print("Showing initial face guide");
      _showFaceGuide();
    });
  }

  void _initializeAnimation() {
    print("Initializing animation controller");
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController)
      ..addListener(() {
        print("Animation value: ${_animation.value}");
        setState(() {});
      });
    _animationController.repeat(reverse: true);
  }

  Future<void> _initializeCamera() async {
    print("Initializing camera");
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          print("Camera initialized successfully");
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        _statusMessage = 'Error initializing camera: $e';
      });
    }
  }

  Future<void> _initializeService() async {
    try {
      await _recognitionService.initialize();
      if (mounted) {
        setState(() {
          _statusMessage = 'Ready to capture faces';
          print("Service initialized successfully");
        });
      }
    } catch (e) {
      print('Error initializing service: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Error initializing service: $e';
        });
      }
    }
  }

  void _showFaceGuide() {
    print("Showing face guide for step: $currentStep");
    setState(() {
      _isShowingGuide = true;
    });

    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isShowingGuide = false;
          print("Face guide hidden");
        });
      }
    });
  }

  Future<void> _captureImage() async {
    if (_isProcessing || currentStep >= totalSteps) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturing image...';
    });

    try {
      print("Starting image capture for step: $currentStep");
      final XFile photo = await _cameraController!.takePicture();
      File imageFile = File(photo.path);

      // Get face detection result
      final detectionResult = await _recognitionService.detectFace(imageFile);

      if (detectionResult.isValid) {
        print('Face detected, processing...');
        await _processImage(imageFile);

        capturedImages.add(imageFile);
        setState(() {
          currentStep++;
          _captureProgress = currentStep / totalSteps;
          _statusMessage =
              'Image ${currentStep} of $totalSteps captured successfully';
          print("Capture progress: $_captureProgress");
        });

        if (currentStep < totalSteps) {
          _showFaceGuide();
        } else {
          await _processRegistration();
        }
      } else {
        setState(() {
          _statusMessage = detectionResult.message;
          if (detectionResult.message.contains('quality')) {
            _statusMessage += '\nPlease ensure:';
            _statusMessage += '\n- Good lighting';
            _statusMessage += '\n- Face clearly visible';
            _statusMessage += '\n- No motion blur';
          }
          print("Face detection failed: ${detectionResult.message}");
        });
      }
    } catch (e) {
      print('Error capturing image: $e');
      setState(() {
        _statusMessage = 'Error capturing image: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  img.Image adjustBrightness(img.Image image, int amount) {
    var brightened = img.Image.from(image);
    for (var y = 0; y < brightened.height; y++) {
      for (var x = 0; x < brightened.width; x++) {
        var pixel = brightened.getPixel(x, y);
        var r = (pixel.r + amount).clamp(0, 255);
        var g = (pixel.g + amount).clamp(0, 255);
        var b = (pixel.b + amount).clamp(0, 255);
        brightened.setPixelRgba(x, y, r, g, b, pixel.a);
      }
    }
    return brightened;
  }

  Future<void> _processImage(File imageFile) async {
    try {
      final detectionResult = await _recognitionService.detectFace(imageFile);
      if (detectionResult.isValid) {
        List<double> originalEmbedding =
            await _recognitionService.getFaceEmbedding(imageFile);
        faceEmbeddings.add(originalEmbedding);

        // Create augmented images for better recognition
        final imageBytes = await imageFile.readAsBytes();
        final originalImage = img.decodeImage(imageBytes);
        if (originalImage != null) {
          print("Creating augmented images");
          // Rotate image slightly
          var rotatedImage = img.copyRotate(originalImage, angle: 5);
          await _processAugmentedImage(rotatedImage);

          rotatedImage = img.copyRotate(originalImage, angle: -5);
          await _processAugmentedImage(rotatedImage);

          // Adjust brightness
          var brighterImage = adjustBrightness(originalImage, 30);
          await _processAugmentedImage(brighterImage);

          var darkerImage = adjustBrightness(originalImage, -30);
          await _processAugmentedImage(darkerImage);

          print("Augmented images processed successfully");
        }
      } else {
        throw Exception(detectionResult.message);
      }
    } catch (e) {
      print('Error processing image: $e');
      throw e;
    }
  }

  Future<void> _processAugmentedImage(img.Image augmentedImage) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
        '${tempDir.path}/temp_aug_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(img.encodeJpg(augmentedImage));

    try {
      List<double> augEmbedding =
          await _recognitionService.getFaceEmbedding(tempFile);
      faceEmbeddings.add(augEmbedding);
      print("Augmented embedding added");
    } catch (e) {
      print('Error processing augmented image: $e');
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<void> _processRegistration() async {
    if (_nameController.text.isEmpty || _employeeIdController.text.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter name and employee ID';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing registration...';
    });

    try {
      print("Registering user with ${faceEmbeddings.length} embeddings");
      await _databaseService.registerUser(
        employeeId: _employeeIdController.text,
        name: _nameController.text,
        faceEmbeddings: faceEmbeddings,
      );

      setState(() {
        _statusMessage = 'Registration successful!';
      });

      _showSuccessDialog();
      _resetRegistration();
    } catch (e) {
      print('Error during registration: $e');
      setState(() {
        _statusMessage = 'Error during registration: $e';
      });
      _showErrorDialog(e.toString());
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _resetRegistration() {
    setState(() {
      _nameController.clear();
      _employeeIdController.clear();
      capturedImages.clear();
      faceEmbeddings.clear();
      currentStep = 0;
      _captureProgress = 0.0;
      _statusMessage = 'Ready to capture faces';
      print("Registration reset");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Registration'),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () => _showInstructions(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_isCameraInitialized && _cameraController != null)
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 400,
                    child: ClipOval(
                      child: AspectRatio(
                        aspectRatio: _cameraController!.value.aspectRatio,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                  if (_isShowingGuide)
                    AnimatedFaceGuide(
                      step: currentStep,
                      animation: _animation,
                      guideMessage: _statusMessage,
                    ),
                ],
              )
            else
              Container(
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.shade200,
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),

            const SizedBox(height: 20),

            // Progress indicator
            LinearProgressIndicator(
              value: _captureProgress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Progress: ${((_captureProgress) * 100).toInt()}%',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _employeeIdController,
              decoration: InputDecoration(
                labelText: 'Employee ID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed:
                  (_isProcessing || _isShowingGuide) ? null : _captureImage,
              icon: Icon(_isProcessing ? Icons.hourglass_empty : Icons.camera),
              label: Text(_isProcessing ? 'Processing...' : 'Capture Image'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color:
                    _statusMessage.contains('Error') ? Colors.red : Colors.blue,
              ),
            ),

            if (_isProcessing)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  void _showInstructions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Registration Instructions'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. Enter your full name and employee ID'),
              Text('2. Position your face within the circle'),
              Text('3. Keep your face steady and well-lit'),
              Text('4. Follow the on-screen guides for different angles'),
              Text('5. Complete all ${totalSteps} required captures'),
              Text('6. Maintain good lighting throughout the process'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Success'),
        content: Text('Registration completed successfully!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text('Registration failed: $error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    print("Disposing registration screen");
    _animationController.dispose();
    _cameraController?.dispose();
    _nameController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }
} // Animated Face Guide for showing step-by-step face capture instructions

class AnimatedFaceGuide extends StatelessWidget {
  final int step;
  final Animation<double> animation;
  final String? guideMessage;

  const AnimatedFaceGuide({
    Key? key,
    required this.step,
    required this.animation,
    this.guideMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          painter: FaceGuidePainter(
            step: step,
            animationValue: animation.value,
          ),
          child: Container(),
        ),
        if (guideMessage != null)
          Positioned(
            bottom: 100,
            left: 20,
            right: 20,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                guideMessage!,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

// Custom painter for drawing face guide with animations
class FaceGuidePainter extends CustomPainter {
  final int step;
  final double animationValue;

  FaceGuidePainter({required this.step, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width * 0.3;

    canvas.save();

    // Different animations based on current step
    switch (step) {
      case 0: // Front face
        // No translation, just center
        break;
      case 1: // Slight left
        canvas.translate(-radius * 0.2 * animationValue, 0);
        break;
      case 2: // Slight right
        canvas.translate(radius * 0.2 * animationValue, 0);
        break;
      case 3: // Slight up
        canvas.translate(0, -radius * 0.2 * animationValue);
        break;
      case 4: // Slight down
        canvas.translate(0, radius * 0.2 * animationValue);
        break;
      case 5: // Left side
        canvas.translate(-radius * 0.3 * animationValue, 0);
        break;
      case 6: // Right side
        canvas.translate(radius * 0.3 * animationValue, 0);
        break;
    }

    // Draw face oval guide
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: radius * 1.2,
        height: radius * 1.6,
      ),
      paint,
    );

    // Draw eyes
    final eyeRadius = radius * 0.1;
    final leftEyeCenter =
        Offset(centerX - radius * 0.3, centerY - radius * 0.3);
    final rightEyeCenter =
        Offset(centerX + radius * 0.3, centerY - radius * 0.3);
    canvas.drawCircle(leftEyeCenter, eyeRadius, paint);
    canvas.drawCircle(rightEyeCenter, eyeRadius, paint);

    // Draw mouth
    final mouthRect = Rect.fromCenter(
      center: Offset(centerX, centerY + radius * 0.4),
      width: radius * 0.6,
      height: radius * 0.1,
    );
    canvas.drawArc(mouthRect, 0, math.pi, false, paint);

    // Draw direction arrow based on step
    final arrowPaint = Paint()
      ..color = Colors.red.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (step > 0) {
      Offset start, end;
      switch (step) {
        case 1: // Left
          start = Offset(centerX + radius * 0.8, centerY);
          end = Offset(centerX + radius * 1.2, centerY);
          _drawArrow(canvas, start, end, arrowPaint);
          break;
        case 2: // Right
          start = Offset(centerX - radius * 0.8, centerY);
          end = Offset(centerX - radius * 1.2, centerY);
          _drawArrow(canvas, start, end, arrowPaint);
          break;
        case 3: // Up
          start = Offset(centerX, centerY + radius * 0.8);
          end = Offset(centerX, centerY + radius * 1.2);
          _drawArrow(canvas, start, end, arrowPaint);
          break;
        case 4: // Down
          start = Offset(centerX, centerY - radius * 0.8);
          end = Offset(centerX, centerY - radius * 1.2);
          _drawArrow(canvas, start, end, arrowPaint);
          break;
        case 5: // Left side
          start = Offset(centerX + radius * 0.8, centerY);
          end = Offset(centerX + radius * 1.4, centerY);
          _drawArrow(canvas, start, end, arrowPaint);
          break;
        case 6: // Right side
          start = Offset(centerX - radius * 0.8, centerY);
          end = Offset(centerX - radius * 1.4, centerY);
          _drawArrow(canvas, start, end, arrowPaint);
          break;
      }
    }

    // Draw step instructions
    final instructionText = _getStepInstructions();
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 20,
      backgroundColor: Colors.black54,
      fontWeight: FontWeight.bold,
    );

    final textSpan = TextSpan(
      text: instructionText,
      style: textStyle,
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout(maxWidth: size.width * 0.8);
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        centerY - radius * 1.2,
      ),
    );

    canvas.restore();
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);

    final arrowSize = 15.0;
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);

    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowSize * math.cos(angle - math.pi / 6),
        end.dy - arrowSize * math.sin(angle - math.pi / 6),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - arrowSize * math.cos(angle + math.pi / 6),
        end.dy - arrowSize * math.sin(angle + math.pi / 6),
      );

    canvas.drawPath(arrowPath, paint);
  }

  String _getStepInstructions() {
    switch (step) {
      case 0:
        return 'Look straight at the camera';
      case 1:
        return 'Turn slightly left';
      case 2:
        return 'Turn slightly right';
      case 3:
        return 'Tilt head up slightly';
      case 4:
        return 'Tilt head down slightly';
      case 5:
        return 'Turn head left';
      case 6:
        return 'Turn head right';
      default:
        return 'Position your face in the oval';
    }
  }

  @override
  bool shouldRepaint(FaceGuidePainter oldDelegate) {
    return step != oldDelegate.step ||
        animationValue != oldDelegate.animationValue;
  }
}
