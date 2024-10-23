// // file: real_time_recognition_screen.dart

// import 'dart:async';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:fac/database/database_service.dart';
// import 'package:fac/facerecongnition.dart';
// import 'package:flutter/material.dart';
// import 'package:google_ml_kit/google_ml_kit.dart';

// class RealTimeRecognitionScreen extends StatefulWidget {
//   const RealTimeRecognitionScreen({Key? key}) : super(key: key);

//   @override
//   _RealTimeRecognitionScreenState createState() =>
//       _RealTimeRecognitionScreenState();
// }

// class _RealTimeRecognitionScreenState extends State<RealTimeRecognitionScreen>
//     with WidgetsBindingObserver {
//   late CameraController _controller;
//   final FaceRecognitionService _recognitionService = FaceRecognitionService();
//   final DatabaseService _databaseService = DatabaseService();

//   String _statusMessage = '';
//   bool _isProcessing = false;
//   Timer? _recognitionTimer;
//   Timer? _initializationRetryTimer;
//   bool _isCameraInitialized = false;
//   bool _isFaceDetected = false;
//   Rect? _faceRect;
//   double _detectionConfidence = 0.0;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _initializeCamera();
//     _initializeService();
//   }

//   Future<void> _initializeCamera() async {
//     try {
//       print('Initializing camera...');
//       final cameras = await availableCameras();
//       final frontCamera = cameras.firstWhere(
//         (camera) => camera.lensDirection == CameraLensDirection.front,
//         orElse: () => cameras.first,
//       );

//       _controller = CameraController(
//         frontCamera,
//         ResolutionPreset.high,
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.jpeg,
//       );

//       await _controller.initialize();

//       if (_controller.value.isInitialized) {
//         await _controller.setFocusMode(FocusMode.auto);
//         await _controller.setExposureMode(ExposureMode.auto);

//         if (mounted) {
//           setState(() {
//             _isCameraInitialized = true;
//             _startRecognitionTimer();
//           });
//         }
//       }
//     } catch (e) {
//       print('Error initializing camera: $e');
//       _initializationRetryTimer?.cancel();
//       _initializationRetryTimer =
//           Timer(const Duration(seconds: 2), _initializeCamera);
//     }
//   }

//   Future<void> _initializeService() async {
//     try {
//       await _recognitionService.initialize();
//       if (mounted) {
//         setState(() {
//           _statusMessage = 'Ready for face recognition';
//         });
//       }
//     } catch (e) {
//       print('Error initializing service: $e');
//       setState(() {
//         _statusMessage = 'Service initialization failed';
//       });
//     }
//   }

//   void _startRecognitionTimer() {
//     _recognitionTimer?.cancel();
//     _recognitionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
//       if (!_isProcessing && mounted && _recognitionService.isInitialized) {
//         _processFrame();
//       }
//     });
//   }

//   Future<void> _processFrame() async {
//     if (!_controller.value.isInitialized) return;

//     setState(() {
//       _isProcessing = true;
//     });

//     try {
//       XFile image = await _controller.takePicture();
//       File imageFile = File(image.path);

//       // Check face detection and validation
//       final detectionResult = await _recognitionService.detectFace(imageFile);

//       setState(() {
//         _isFaceDetected = detectionResult.isValid;
//         _faceRect = detectionResult.face?.boundingBox;
//         _statusMessage = detectionResult.message;
//       });

//       if (detectionResult.isValid) {
//         List<double> faceEmbedding =
//             await _recognitionService.getFaceEmbedding(imageFile);
//         var matchedUser = await _findMatchingUser(faceEmbedding);

//         if (matchedUser != null) {
//           await _handleRecognizedUser(matchedUser);
//         } else {
//           setState(() {
//             _statusMessage = 'Face not recognized. Please register first.';
//           });
//         }
//       }

//       // Clean up temporary image file
//       try {
//         await imageFile.delete();
//       } catch (e) {
//         print('Error deleting temporary file: $e');
//       }
//     } catch (e) {
//       print('Error during recognition: $e');
//       setState(() {
//         _statusMessage = 'Recognition error: Please try again';
//       });
//     } finally {
//       setState(() {
//         _isProcessing = false;
//       });
//     }
//   }

//   Future<Map<String, dynamic>?> _findMatchingUser(
//       List<double> faceEmbedding) async {
//     try {
//       var users = await _databaseService.getAllUsers();
//       double highestSimilarity = 0;
//       Map<String, dynamic>? matchedUser;

//       for (var doc in users.docs) {
//         var userData = doc.data() as Map<String, dynamic>;
//         var storedEmbeddings =
//             List<Map<String, dynamic>>.from(userData['embeddings']);

//         for (var embeddingMap in storedEmbeddings) {
//           var embedding = List<double>.from(embeddingMap['values']);
//           double similarity = _recognitionService.calculateSimilarity(
//             faceEmbedding,
//             embedding,
//           );

//           if (similarity > highestSimilarity &&
//               similarity >= FaceRecognitionService.THRESHOLD) {
//             highestSimilarity = similarity;
//             matchedUser = userData;
//             matchedUser['id'] = doc.id;
//             matchedUser['matchConfidence'] = similarity;
//           }
//         }
//       }

//       return matchedUser;
//     } catch (e) {
//       print('Error finding matching user: $e');
//       return null;
//     }
//   }

//   Future<void> _handleRecognizedUser(Map<String, dynamic> user) async {
//     try {
//       bool currentAttendance = user['attendance'] ?? false;

//       // Wait a bit to prevent accidental double-marks
//       await Future.delayed(const Duration(seconds: 2));

//       await _databaseService.updateAttendance(
//         employeeId: user['id'],
//         isCheckIn: !currentAttendance,
//         matchConfidence: user['matchConfidence'],
//       );

//       // setState(() {
//       //   _statusMessage = !currentAttendance
//       //       ? 'Welcome ${user['name']}!\nChecked In Successfully'
//       //       : 'Goodbye ${user['name']}!\nChecked Out Successfully';
//       // });

//       // Show success overlay
//       if (mounted) {
//         _showSuccessOverlay(user['name'], !currentAttendance);
//       }
//     } catch (e) {
//       print('Error handling recognized user: $e');
//       setState(() {
//         _statusMessage = 'Error updating attendance';
//       });
//     }
//   }

//   void _showSuccessOverlay(String userName, bool isCheckIn) {
//     showDialog(
//       context: context,
//       barrierDismissible: true,
//       builder: (BuildContext context) {
//         return Dialog(
//           backgroundColor: Colors.transparent,
//           elevation: 0,
//           child: Container(
//             padding: const EdgeInsets.all(16),
//             decoration: BoxDecoration(
//               color: Colors.green.withOpacity(0.9),
//               borderRadius: BorderRadius.circular(16),
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(
//                   isCheckIn ? Icons.login : Icons.logout,
//                   color: Colors.white,
//                   size: 50,
//                 ),
//                 const SizedBox(height: 16),
//                 Text(
//                   isCheckIn ? 'Welcome $userName!' : 'Goodbye $userName!',
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 24,
//                     fontWeight: FontWeight.bold,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   isCheckIn
//                       ? 'Checked In Successfully'
//                       : 'Checked Out Successfully',
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 16,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );

//     // Auto-dismiss after 3 seconds
//     Future.delayed(const Duration(seconds: 3), () {
//       if (mounted && Navigator.canPop(context)) {
//         Navigator.pop(context);
//       }
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Face Recognition'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: () {
//               _initializeCamera();
//               _initializeService();
//             },
//           ),
//         ],
//       ),
//       body: Stack(
//         children: [
//           // Camera Preview
//           if (_isCameraInitialized)
//             Container(
//               width: double.infinity,
//               height: double.infinity,
//               child: AspectRatio(
//                 aspectRatio: _controller.value.aspectRatio,
//                 child: CameraPreview(_controller),
//               ),
//             )
//           else
//             const Center(
//               child: CircularProgressIndicator(),
//             ),

//           // Face Detection Overlay
//           if (_isCameraInitialized)
//             CustomPaint(
//               painter: FaceOverlayPainter(
//                 isFaceDetected: _isFaceDetected,
//                 faceRect: _faceRect,
//                 previewSize: Size(
//                   MediaQuery.of(context).size.width,
//                   MediaQuery.of(context).size.width /
//                       _controller.value.aspectRatio,
//                 ),
//               ),
//             ),

//           // Status Message
//           Positioned(
//             bottom: 50,
//             left: 0,
//             right: 0,
//             child: Container(
//               padding: const EdgeInsets.all(16),
//               color: Colors.black54,
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Text(
//                     _statusMessage,
//                     style: const TextStyle(
//                       color: Colors.white,
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                     ),
//                     textAlign: TextAlign.center,
//                   ),
//                   if (_isProcessing)
//                     const Padding(
//                       padding: EdgeInsets.only(top: 8),
//                       child: LinearProgressIndicator(
//                         backgroundColor: Colors.white24,
//                         valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _recognitionTimer?.cancel();
//     _initializationRetryTimer?.cancel();
//     _controller.dispose();
//     super.dispose();
//   }
// }

// class FaceOverlayPainter extends CustomPainter {
//   final bool isFaceDetected;
//   final Rect? faceRect;
//   final Size previewSize;

//   FaceOverlayPainter({
//     required this.isFaceDetected,
//     required this.faceRect,
//     required this.previewSize,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 3.0;

//     // Draw guide oval
//     paint.color = isFaceDetected ? Colors.green : Colors.white;
//     final center = Offset(size.width / 2, size.height / 2);
//     final ovalRect = Rect.fromCenter(
//       center: center,
//       width: size.width * 0.6,
//       height: size.height * 0.4,
//     );
//     canvas.drawOval(ovalRect, paint);

//     // Draw face rectangle if detected
//     if (isFaceDetected && faceRect != null) {
//       // Scale face rect to match preview size
//       final scaleX = size.width / previewSize.width;
//       final scaleY = size.height / previewSize.height;

//       final scaledRect = Rect.fromLTRB(
//         faceRect!.left * scaleX,
//         faceRect!.top * scaleY,
//         faceRect!.right * scaleX,
//         faceRect!.bottom * scaleY,
//       );

//       canvas.drawRect(scaledRect, paint);
//     }

//     // Add guide text
//     if (!isFaceDetected) {
//       final textSpan = TextSpan(
//         text: 'Position your face within the oval',
//         style: TextStyle(
//           color: Colors.white,
//           fontSize: 16,
//           backgroundColor: Colors.black54,
//         ),
//       );
//       final textPainter = TextPainter(
//         text: textSpan,
//         textDirection: TextDirection.ltr,
//       );
//       textPainter.layout();
//       textPainter.paint(
//         canvas,
//         Offset(
//           (size.width - textPainter.width) / 2,
//           center.dy + size.height * 0.25,
//         ),
//       );
//     }
//   }

//   @override
//   bool shouldRepaint(FaceOverlayPainter oldDelegate) {
//     return isFaceDetected != oldDelegate.isFaceDetected ||
//         faceRect != oldDelegate.faceRect;
//   }
// }

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:fac/database/database_service.dart';
import 'package:fac/facerecongnition.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:intl/intl.dart';

class RealTimeRecognitionScreen extends StatefulWidget {
  const RealTimeRecognitionScreen({Key? key}) : super(key: key);

  @override
  _RealTimeRecognitionScreenState createState() =>
      _RealTimeRecognitionScreenState();
}

class _RealTimeRecognitionScreenState extends State<RealTimeRecognitionScreen> {
  late CameraController _controller;
  final FaceRecognitionService _recognitionService = FaceRecognitionService();
  final DatabaseService _databaseService = DatabaseService();

  bool _isProcessing = false;
  Timer? _recognitionTimer;
  Timer? _initializationRetryTimer;
  bool _isCameraInitialized = false;
  bool _isFaceDetected = false;
  bool _showSuccessOverlay = false;
  String _recognizedName = '';
  bool _isCheckIn = true;
  DateTime? _lastRecognitionTime;
  Rect? _faceRect;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeService();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller.initialize();

      if (_controller.value.isInitialized) {
        await _controller.setFocusMode(FocusMode.auto);
        await _controller.setExposureMode(ExposureMode.auto);

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
            _startRecognitionTimer();
          });
        }
      }
    } catch (e) {
      print('Error initializing camera: $e');
      _initializationRetryTimer?.cancel();
      _initializationRetryTimer =
          Timer(Duration(seconds: 2), _initializeCamera);
    }
  }

  Future<void> _initializeService() async {
    try {
      await _recognitionService.initialize();
    } catch (e) {
      print('Error initializing service: $e');
    }
  }

  void _startRecognitionTimer() {
    _recognitionTimer?.cancel();
    _recognitionTimer = Timer.periodic(Duration(milliseconds: 500), (_) {
      if (!_isProcessing && mounted && _recognitionService.isInitialized) {
        _processFrame();
      }
    });
  }

  Future<void> _processFrame() async {
    if (!_controller.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _isFaceDetected = false;
    });

    try {
      XFile image = await _controller.takePicture();
      File imageFile = File(image.path);

      final detectionResult = await _recognitionService.detectFace(imageFile);
      setState(() {
        _isFaceDetected = detectionResult.isValid;
        _faceRect = detectionResult.face?.boundingBox;
      });

      if (detectionResult.isValid) {
        List<double> faceEmbedding =
            await _recognitionService.getFaceEmbedding(imageFile);
        var matchedUser = await _findMatchingUser(faceEmbedding);

        if (matchedUser != null) {
          await _handleRecognizedUser(matchedUser);
        }
      }

      await imageFile.delete();
    } catch (e) {
      print('Error during recognition: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _findMatchingUser(
      List<double> faceEmbedding) async {
    try {
      var users = await _databaseService.getAllUsers();
      double highestSimilarity = 0;
      Map<String, dynamic>? matchedUser;

      for (var doc in users.docs) {
        var userData = doc.data() as Map<String, dynamic>;
        var storedEmbeddings =
            List<Map<String, dynamic>>.from(userData['embeddings']);

        for (var embeddingMap in storedEmbeddings) {
          var embedding = List<double>.from(embeddingMap['values']);
          double similarity = _recognitionService.calculateSimilarity(
            faceEmbedding,
            embedding,
          );

          if (similarity > highestSimilarity &&
              similarity >= FaceRecognitionService.THRESHOLD) {
            highestSimilarity = similarity;
            matchedUser = userData;
            matchedUser['id'] = doc.id;
            matchedUser['matchConfidence'] = similarity;
          }
        }
      }

      return matchedUser;
    } catch (e) {
      print('Error finding matching user: $e');
      return null;
    }
  }

  Future<void> _handleRecognizedUser(Map<String, dynamic> user) async {
    try {
      bool currentAttendance = user['attendance'] ?? false;

      await _databaseService.updateAttendance(
        employeeId: user['id'],
        isCheckIn: !currentAttendance,
        matchConfidence: user['matchConfidence'],
      );

      setState(() {
        _lastRecognitionTime = DateTime.now();
        _recognizedName = user['name'].toString();
        _isCheckIn = !currentAttendance;
        _showSuccessOverlay = true;
      });

      // Auto hide success overlay after 3 seconds
      Timer(Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showSuccessOverlay = false;
          });
        }
      });
    } catch (e) {
      print('Error handling recognized user: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraInitialized)
            Container(
              width: double.infinity,
              height: double.infinity,
              child: CameraPreview(_controller),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.green),
            ),

          // Navigation Buttons at Top
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          Positioned(
            top: 40,
            right: 10,
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                _initializeCamera();
                _initializeService();
              },
            ),
          ),

          // "Face Recognition" Text
          Positioned(
            top: 45,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Face Recognition',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Face Detection Status at Top
          if (_isFaceDetected)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8),
                color: Colors.black45,
                child: Column(
                  children: [
                    Text(
                      'Face detected successfully',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 40),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Face Detection Overlay
          if (_isCameraInitialized)
            CustomPaint(
              painter: FaceOverlayPainter(
                isFaceDetected: _isFaceDetected,
                faceRect: _faceRect,
                previewSize: Size(
                  MediaQuery.of(context).size.width,
                  MediaQuery.of(context).size.width /
                      _controller.value.aspectRatio,
                ),
              ),
            ),

          // Success Message Overlay
          if (_showSuccessOverlay)
            Container(
              width: double.infinity,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(top: 600),
                child: Container(
                  //width: double.infinity,
                  // margin: EdgeInsets.symmetric(horizontal: 40),
                  // padding: EdgeInsets.all(70),
                  decoration: BoxDecoration(
                    color: Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.done,
                            //_isCheckIn ? Icons.login : Icons.logout,
                            color: Colors.white,
                            size: 32,
                          ),
                          // Sized
                          Text(
                            ' ${_recognizedName.toLowerCase()}!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      // Icon(
                      //   _isCheckIn ? Icons.login : Icons.logout,
                      //   color: Colors.white,
                      //   size: 32,
                      // ),
                      // SizedBox(height: 10),

                      SizedBox(height: 4),
                      Text(
                        _isCheckIn
                            ? 'Punched In Successfully'
                            : 'Punched Out Successfully',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_lastRecognitionTime != null) ...[
                            //SizedBox(height: 8),
                            Text(
                              DateFormat('hh:mm a')
                                  .format(_lastRecognitionTime!),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Text(
                              DateFormat('dd MMM yyyy')
                                  .format(_lastRecognitionTime!),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recognitionTimer?.cancel();
    _initializationRetryTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }
}

class FaceOverlayPainter extends CustomPainter {
  final bool isFaceDetected;
  final Rect? faceRect;
  final Size previewSize;

  FaceOverlayPainter({
    required this.isFaceDetected,
    required this.faceRect,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw guide oval
    paint.color = isFaceDetected ? Colors.green : Colors.white;
    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.6,
      height: size.height * 0.4,
    );
    canvas.drawOval(ovalRect, paint);

    // Draw face rectangle if detected
    if (isFaceDetected && faceRect != null) {
      final scaleX = size.width / previewSize.width;
      final scaleY = size.height / previewSize.height;

      final scaledRect = Rect.fromLTRB(
        faceRect!.left * scaleX,
        faceRect!.top * scaleY,
        faceRect!.right * scaleX,
        faceRect!.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, paint);
    }

    // Draw guide text
    if (!isFaceDetected) {
      final textSpan = TextSpan(
        text: 'Position your face within the oval',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          backgroundColor: Colors.black54,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        // textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          center.dy + size.height * 0.25,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(FaceOverlayPainter oldDelegate) {
    return isFaceDetected != oldDelegate.isFaceDetected ||
        faceRect != oldDelegate.faceRect;
  }
}
