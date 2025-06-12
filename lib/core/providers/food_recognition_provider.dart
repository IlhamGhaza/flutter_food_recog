import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/env.dart';

class FoodRecognitionProvider extends ChangeNotifier {
  Interpreter? _interpreter;
  List<String>? _labels; // Kita gunakan lagi variabel ini
  bool _isModelLoaded = false;
  bool _isProcessing = false;
  Map<String, dynamic>? _lastPrediction;
  Map<String, dynamic>? _lastMealData;
  Map<String, dynamic>? _lastNutritionalData;

  bool _isIdentifyingFood = false;
  bool _isFetchingMealData = false;
  bool _isFetchingNutritionalData = false;

  bool get isModelLoaded => _isModelLoaded;
  bool get isProcessing => _isProcessing;
  Map<String, dynamic>? get lastPrediction => _lastPrediction;
  Map<String, dynamic>? get lastMealData => _lastMealData;
  Map<String, dynamic>? get lastNutritionalData => _lastNutritionalData;

  bool get isIdentifyingFood => _isIdentifyingFood;
  bool get isFetchingMealData => _isFetchingMealData;
  bool get isFetchingNutritionalData => _isFetchingNutritionalData;

  FoodRecognitionProvider() {
    loadModel();
  }

  // KEMBALIKAN FUNGSI loadModel KE VERSI YANG MEMUAT LABELS.TXT
  Future<void> loadModel() async {
    if (_isModelLoaded) return;
    try {
      _isProcessing = true;
      notifyListeners();

      // Memuat model
      final modelFile = await _getModelFile('assets/aiy.tflite', 'aiy.tflite');
      final options = InterpreterOptions();
      _interpreter = Interpreter.fromFile(modelFile, options: options);

      // Memuat file label yang benar dari assets
      await _loadLabels();

      _isModelLoaded = true;
      debugPrint("LOG: Model and labels loaded successfully from assets.");
    } catch (e) {
      debugPrint('LOG: Error loading model or labels: $e');
      _isModelLoaded = false;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
  
  // FUNGSI UNTUK MEMBACA LABELS.TXT
  Future<void> _loadLabels() async {
    final labelsData = await rootBundle.loadString('assets/labels.txt');
    // Langsung split tanpa sorting, menjaga urutan asli
    _labels = labelsData.split('\n').map((label) => label.trim()).where((l) => l.isNotEmpty).toList();
    debugPrint("LOG: Loaded ${_labels?.length ?? 0} labels from file.");
  }


  Future<File> _getModelFile(String assetPath, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelPath = path.join(appDir.path, fileName);
    final modelFile = File(modelPath);

    if (!await modelFile.exists()) {
      final modelData = await rootBundle.load(assetPath);
      await modelFile.writeAsBytes(modelData.buffer.asUint8List());
    }
    return modelFile;
  }

  void clearLastData() {
    _lastPrediction = null;
    _lastMealData = null;
    _lastNutritionalData = null;
    _isIdentifyingFood = false;
    _isFetchingMealData = false;
    _isFetchingNutritionalData = false;
    _isProcessing = false;
    notifyListeners();
  }
  
  Future<void> processImageAndFetchDetails(String imagePath) async {
    try {
      _isProcessing = true;
      _isIdentifyingFood = true;
      _lastMealData = null;
      _lastNutritionalData = null;
      _lastPrediction = null;
      notifyListeners();
      debugPrint("==================================================");
      debugPrint("LOG: Starting food recognition process...");

      final foodName = await _getFoodNameFromImageWithTFLite(imagePath);
      _isIdentifyingFood = false;

      if (foodName == null || foodName == "Unknown Food") {
        _lastPrediction ??= {'label': 'Unknown Food', 'confidence': _lastPrediction?['confidence'] ?? 0.0};
        debugPrint("LOG: Food not recognized or confidence too low. Ending process.");
        _isProcessing = false;
        notifyListeners();
        debugPrint("==================================================");
        return;
      }
      notifyListeners();

      _isFetchingMealData = true;
      notifyListeners();
      await _fetchMealData(foodName);
      _isFetchingMealData = false;
      notifyListeners();
      
      final finalFoodNameForNutrition = _lastMealData?['strMeal'] as String? ?? foodName;
      _isFetchingNutritionalData = true;
      notifyListeners();
      await _fetchNutritionalData(finalFoodNameForNutrition);
      _isFetchingNutritionalData = false;
      notifyListeners();

    } catch (e) {
      debugPrint('LOG: ERROR in prediction process: $e');
      _lastPrediction = {'label': 'Error', 'confidence': 0.0, 'error': e.toString()};
    } finally {
      _isIdentifyingFood = false;
      _isFetchingMealData = false;
      _isFetchingNutritionalData = false;
      _isProcessing = false;
      notifyListeners();
      debugPrint("LOG: Food recognition process finished.");
      debugPrint("==================================================");
    }
  }

  Future<void> fetchDetailsForCorrectedName(String correctedName) async {
    _isFetchingMealData = true;
    _isFetchingNutritionalData = true;
    _lastMealData = null;
    _lastNutritionalData = null;
    notifyListeners();

    if (_lastPrediction != null) {
      _lastPrediction!['label'] = correctedName;
    } else {
      _lastPrediction = {'label': correctedName, 'confidence': 1.0};
    }

    debugPrint("LOG: User corrected name to '$correctedName'. Fetching new details...");

    await _fetchMealData(correctedName);
    _isFetchingMealData = false;
    notifyListeners();

    await _fetchNutritionalData(correctedName);
    _isFetchingNutritionalData = false;
    notifyListeners();
    
    debugPrint("LOG: Process finished for corrected name '$correctedName'.");
  }

  Future<String?> _getFoodNameFromImageWithTFLite(String imagePath) async {
    if (!_isModelLoaded || _interpreter == null || _labels == null) {
      debugPrint("LOG: Model/labels not loaded, attempting to load now...");
      await loadModel();
      if (!_isModelLoaded) return "Error: Model/labels failed to load";
    }

    final imageData = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(imageData)!;
    final resizedImage = img.copyResize(image, width: 224, height: 224);
    
    final inputBytes = resizedImage.getBytes(order: img.ChannelOrder.rgb);
    final input = inputBytes.reshape([1, 224, 224, 3]);

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final output = List.generate(
      outputShape.reduce((a, b) => a * b),
      (_) => 0,
    ).reshape(outputShape);
    
    _interpreter!.run(input, output);

    final result = output[0] as List<int>;
    double maxConfidence = 0.0;
    int maxIndex = -1;

    for (int i = 0; i < result.length; i++) {
      final confidence = result[i] / 255.0;
      if (confidence > maxConfidence) {
        maxConfidence = confidence;
        maxIndex = i;
      }
    }
    
    if (maxIndex != -1 && maxIndex < _labels!.length && maxConfidence > 0.5) {
      final foodName = _labels![maxIndex].replaceAll('_', ' ');
      _lastPrediction = {'label': foodName, 'confidence': maxConfidence};
      debugPrint("LOG: TFLite recognized index $maxIndex -> '$foodName' with confidence ${(maxConfidence * 100).toStringAsFixed(1)}%");
      return foodName;
    } else {
      _lastPrediction = {'label': 'Unknown Food', 'confidence': maxConfidence};
      debugPrint("LOG: TFLite could not recognize food with high confidence. Max confidence: ${(maxConfidence * 100).toStringAsFixed(1)}%");
      return "Unknown Food";
    }
  }

  Future<void> _fetchMealData(String foodLabel) async {
    final apiFoodLabel = foodLabel.replaceAll(' ', '_');
    debugPrint("LOG: Fetching meal data for: '$foodLabel' (using URL parameter: '$apiFoodLabel')");
    
    try {
      final uri = Uri.parse('https://www.themealdb.com/api/json/v1/1/search.php?s=$apiFoodLabel');
      debugPrint("LOG: TheMealDB API URL: $uri");

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['meals'] != null && data['meals'].isNotEmpty) {
          _lastMealData = data['meals'][0];
          debugPrint("LOG: SUCCESS - Meal data found for '$foodLabel'. Recipe: ${_lastMealData?['strMeal']}");
        } else {
          _lastMealData = null;
          debugPrint("LOG: FAILED - Meal data NOT found for '$foodLabel' in TheMealDB.");
        }
      } else {
        _lastMealData = null;
        debugPrint("LOG: FAILED - TheMealDB API returned status code ${response.statusCode}");
      }
    } catch (e) {
      debugPrint('LOG: ERROR fetching meal data: $e');
      _lastMealData = null;
    }
  }

  Future<void> _fetchNutritionalData(String foodName) async {
    debugPrint("LOG: Fetching nutritional data for: '$foodName' using Gemini.");
    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: Env.geminiApiKey,
      );
      final prompt =
          'Provide typical nutritional data (calories, carbohydrates, protein, fat, fiber) for a standard serving of $foodName. Please respond in a clean JSON format. Each value should be a single, static string representing a typical value, not a range. For example: {"calories": "250 kcal", "carbohydrates": "30g", "protein": "10g", "fat": "12g", "fiber": "3g"}.';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      if (response.text != null) {
        String jsonString =
            response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
        _lastNutritionalData = json.decode(jsonString);
        debugPrint("LOG: Nutritional data from Gemini received successfully.");
      } else {
        debugPrint("LOG: Gemini did not return text for nutritional data.");
      }
    } catch (e) {
      debugPrint('LOG: ERROR fetching nutritional data from Gemini: $e');
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }
}