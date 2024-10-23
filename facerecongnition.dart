// file: face_recognition_service.dart

import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class FaceRecognitionService {
  static const double THRESHOLD = 0.7;
  static const int INPUT_SIZE = 112;
  static const int OUTPUT_SIZE = 128;
  static const double MIN_FACE_PERCENTAGE = 0.15;
  static const double MAX_FACE_PERCENTAGE = 0.65;
  static const double MAX_HEAD_ROTATION = 15.0;

  Interpreter? _interpreter;
  late FaceDetector _faceDetector;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('Initializing FaceRecognitionService...');

      final options = InterpreterOptions()..threads = 4;

      _interpreter = await Interpreter.fromAsset(
        'assets/MobileFaceNet.tflite',
        options: options,
      );

      _faceDetector = GoogleMlKit.vision.faceDetector(
        FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: true,
          minFaceSize: 0.15,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

      if (_interpreter != null) {
        var inputShape = _interpreter!.getInputTensor(0).shape;
        var outputShape = _interpreter!.getOutputTensor(0).shape;
        print('Model input shape: $inputShape');
        print('Model output shape: $outputShape');
        _isInitialized = true;
        print('FaceRecognitionService initialized successfully');
      } else {
        throw Exception('Failed to load TensorFlow Lite model');
      }
    } catch (e) {
      print('Error initializing FaceRecognitionService: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<FaceDetectionResult> detectFace(File imageFile) async {
    if (!_isInitialized) {
      throw Exception('FaceRecognitionService is not initialized');
    }
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        print('No face detected');
        return FaceDetectionResult(
            isValid: false,
            message: 'No face detected. Please look at the camera.',
            face: null);
      }

      // Get the first detected face
      final face = faces.first;

      // Calculate face visibility percentage
      final imageSize = await _getImageSize(imageFile);
      final faceArea = face.boundingBox.width * face.boundingBox.height;
      final imageArea = imageSize.width * imageSize.height;
      final facePercentage = faceArea / imageArea;

      // Check face position and size requirements
      final positionValidation = _validateFacePosition(face, imageSize);

      // Debug information
      print('Face bounds: ${face.boundingBox}');
      print('Face landmarks detected: ${face.landmarks.length}');
      print(
          'Face percentage of image: ${(facePercentage * 100).toStringAsFixed(2)}%');
      print('Face position validation: $positionValidation');

      if (facePercentage < MIN_FACE_PERCENTAGE) {
        return FaceDetectionResult(
            isValid: false,
            message: 'Please move closer to the camera',
            face: face);
      }

      if (facePercentage > MAX_FACE_PERCENTAGE) {
        return FaceDetectionResult(
            isValid: false,
            message: 'Please move away from the camera',
            face: face);
      }

      if (!positionValidation.isValid) {
        return FaceDetectionResult(
            isValid: false, message: positionValidation.message, face: face);
      }

      // Check head rotation
      if (face.headEulerAngleY != null &&
          face.headEulerAngleY!.abs() > MAX_HEAD_ROTATION) {
        return FaceDetectionResult(
            isValid: false,
            message: 'Please face directly towards the camera',
            face: face);
      }

      if (face.headEulerAngleZ != null &&
          face.headEulerAngleZ!.abs() > MAX_HEAD_ROTATION) {
        return FaceDetectionResult(
            isValid: false,
            message: 'Please keep your head straight',
            face: face);
      }

      // Validation criteria
      bool meetsRequirements = face.landmarks.length >= 3 &&
          positionValidation.isValid &&
          facePercentage >= MIN_FACE_PERCENTAGE &&
          facePercentage <= MAX_FACE_PERCENTAGE;

      return FaceDetectionResult(
          isValid: meetsRequirements,
          message: meetsRequirements
              ? 'Face detected successfully'
              : 'Please adjust your position',
          face: face);
    } catch (e) {
      print('Error during face detection: $e');
      return FaceDetectionResult(
          isValid: false, message: 'Error during face detection', face: null);
    }
  }

  FacePositionValidation _validateFacePosition(Face face, Size imageSize) {
    final rect = face.boundingBox;

    // Calculate center of the face
    final faceCenterX = rect.center.dx;
    final faceCenterY = rect.center.dy;

    // Calculate acceptable ranges for face center (middle 60% of image)
    final minX = imageSize.width * 0.2;
    final maxX = imageSize.width * 0.8;
    final minY = imageSize.height * 0.2;
    final maxY = imageSize.height * 0.8;

    String message = '';

    if (faceCenterX < minX) {
      message = 'Move your face right';
    } else if (faceCenterX > maxX) {
      message = 'Move your face left';
    }

    if (faceCenterY < minY) {
      message = message.isEmpty ? 'Move your face down' : '$message and down';
    } else if (faceCenterY > maxY) {
      message = message.isEmpty ? 'Move your face up' : '$message and up';
    }

    bool isCentered = faceCenterX >= minX &&
        faceCenterX <= maxX &&
        faceCenterY >= minY &&
        faceCenterY <= maxY;

    return FacePositionValidation(
        isValid: isCentered,
        message: message.isEmpty ? 'Face is well positioned' : message);
  }

  Future<Size> _getImageSize(File imageFile) async {
    final img.Image? image = img.decodeImage(await imageFile.readAsBytes());
    if (image == null) throw Exception('Failed to decode image');
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Future<List<double>> getFaceEmbedding(File imageFile) async {
    if (!_isInitialized || _interpreter == null) {
      throw Exception('FaceRecognitionService is not initialized');
    }

    try {
      // First validate the face
      final detectionResult = await detectFace(imageFile);
      if (!detectionResult.isValid) {
        throw Exception('Invalid face detected: ${detectionResult.message}');
      }

      var bytes = await imageFile.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image');

      var resizedImage =
          img.copyResize(image, width: INPUT_SIZE, height: INPUT_SIZE);
      var input = _imageToByteListFloat32(resizedImage);

      var outputShape = _interpreter!.getOutputTensor(0).shape;
      var outputBuffer = List.generate(
        outputShape[0],
        (_) => List<double>.filled(outputShape[1], 0),
      );

      _interpreter!.run(input, outputBuffer);

      var flattened = outputBuffer.expand((list) => list).toList();

      if (flattened.length != OUTPUT_SIZE) {
        print(
            'Warning: Output size mismatch. Expected $OUTPUT_SIZE, got ${flattened.length}');
      }

      return flattened;
    } catch (e) {
      print('Error getting face embedding: $e');
      rethrow;
    }
  }

  List<List<List<List<double>>>> _imageToByteListFloat32(img.Image image) {
    var convertedBytes = List.generate(
      1,
      (i) => List.generate(
        INPUT_SIZE,
        (y) => List.generate(
          INPUT_SIZE,
          (x) {
            var pixel = image.getPixel(x, y);
            return [
              (pixel.r.toDouble() - 127.5) / 128,
              (pixel.g.toDouble() - 127.5) / 128,
              (pixel.b.toDouble() - 127.5) / 128,
            ];
          },
        ),
      ),
    );
    return convertedBytes;
  }

  double calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      print(
          'Warning: Embedding length mismatch: ${embedding1.length} vs ${embedding2.length}');
      var minLength = min(embedding1.length, embedding2.length);
      embedding1 = embedding1.sublist(0, minLength);
      embedding2 = embedding2.sublist(0, minLength);
    }

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    return dotProduct / (sqrt(norm1) * sqrt(norm2));
  }

  void dispose() {
    _interpreter?.close();
    _faceDetector.close();
    _isInitialized = false;
  }
}

class FaceDetectionResult {
  final bool isValid;
  final String message;
  final Face? face;

  FaceDetectionResult({
    required this.isValid,
    required this.message,
    this.face,
  });
}

class FacePositionValidation {
  final bool isValid;
  final String message;

  FacePositionValidation({
    required this.isValid,
    required this.message,
  });
}
