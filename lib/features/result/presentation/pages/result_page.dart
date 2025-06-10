import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/providers/food_recognition_provider.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/utils/snackbar_utils.dart';

class ResultPage extends StatefulWidget {
  final String imagePath;

  const ResultPage({super.key, required this.imagePath});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final TextEditingController _correctionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final foodProvider = context.read<FoodRecognitionProvider>();
        foodProvider.clearLastData();
        foodProvider.processImageAndFetchDetails(widget.imagePath).catchError((
          e,
        ) {
          if (mounted) {
            SnackbarUtils(
              text: 'Error processing image: ${e.toString()}',
              backgroundColor: Colors.red,
            ).showErrorSnackBar(context);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _correctionController.dispose();
    super.dispose();
  }

  // Dialog untuk koreksi nama makanan
  void _showCorrectionDialog(BuildContext context) {
    final foodProvider = context.read<FoodRecognitionProvider>();
    _correctionController.text = foodProvider.lastPrediction?['label'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Koreksi Nama Makanan'),
          content: TextField(
            controller: _correctionController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Masukkan nama yang benar",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                final correctedName = _correctionController.text.trim();
                if (correctedName.isNotEmpty) {
                  foodProvider.fetchDetailsForCorrectedName(correctedName);
                  Navigator.pop(context);
                }
              },
              child: const Text('Cari'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recognition Result')),
      body: Consumer<FoodRecognitionProvider>(
        builder: (context, provider, child) {
          final meal = provider.lastMealData;
          final nutrition = provider.lastNutritionalData;
          final prediction = provider.lastPrediction;

          String displayImagePath = widget.imagePath;
          if (meal?['strMealThumb'] != null &&
              (meal!['strMealThumb'] as String).isNotEmpty) {
            displayImagePath = meal['strMealThumb'] as String;
          }

          final bool isOverallLoading =
              provider.isIdentifyingFood ||
              provider.isFetchingMealData ||
              provider.isFetchingNutritionalData;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ... (Image display widget tidak berubah)
                displayImagePath.startsWith('http')
                    ? Image.network(
                        displayImagePath,
                        height: 300,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return SizedBox(
                            height: 300,
                            child: Center(
                              child: CircularProgressIndicator(
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            Image.file(
                              File(widget.imagePath),
                              height: 300,
                              fit: BoxFit.cover,
                            ),
                      )
                    : Image.file(
                        File(widget.imagePath),
                        height: 300,
                        fit: BoxFit.cover,
                      ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- BAGIAN NAMA MAKANAN DAN KOREKSI ---
                      if (provider.isIdentifyingFood || prediction == null)
                        _buildShimmerPlaceholder(
                          height: 28,
                          width: 200,
                          margin: const EdgeInsets.only(bottom: 8),
                        )
                      else ...[
                        Text(
                          (prediction['label'] as String)
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Confidence: ${((prediction['confidence'] as double) * 100).toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        // Tombol Koreksi
                        OutlinedButton.icon(
                          onPressed: () => _showCorrectionDialog(context),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Bukan ini? Koreksi'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Tampilan loading atau data
                      if (isOverallLoading && meal == null && nutrition == null)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        if (provider.isFetchingNutritionalData &&
                            nutrition == null)
                          _buildNutritionalInfoShimmer(context)
                        else if (nutrition != null)
                          _buildNutritionalInfoCard(context, nutrition),

                        const SizedBox(height: 10),

                        if (provider.isFetchingMealData && meal == null)
                          _buildMealInfoShimmer(context)
                        else if (meal != null)
                          _buildMealInfoCard(context, meal)
                        else if (!provider.isIdentifyingFood &&
                            prediction != null &&
                            prediction['label'] != 'Unknown Food')
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'Informasi resep detail tidak ditemukan.',
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            Navigator.pushReplacementNamed(context, AppRouter.home),
        child: const Icon(Icons.home),
      ),
    );
  }

   Widget _buildShimmerPlaceholder({
    double? width,
    required double height,
    double borderRadius = 4.0,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

   Widget _buildShimmerNutritionRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildShimmerPlaceholder(height: 16, width: 100),
          _buildShimmerPlaceholder(height: 16, width: 60),
        ],
      ),
    );
  }

  Widget _buildNutritionalInfoShimmer(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShimmerPlaceholder(height: 22, width: 250),
            const SizedBox(height: 12),
            _buildShimmerNutritionRow(),
            _buildShimmerNutritionRow(),
            _buildShimmerNutritionRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildMealInfoShimmer(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShimmerPlaceholder(height: 22, width: 150),
            const SizedBox(height: 10),
            _buildShimmerPlaceholder(
              height: 14,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
            ),
            _buildShimmerPlaceholder(
              height: 14,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
            ),
            const SizedBox(height: 20),
            _buildShimmerPlaceholder(height: 22, width: 150),
            const SizedBox(height: 10),
            _buildShimmerPlaceholder(
              height: 14,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionalInfoCard(
    BuildContext context,
    Map<String, dynamic> nutrition,
  ) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nutritional Information (per serving)',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildNutritionRow('Calories', nutrition['calories']),
            _buildNutritionRow('Carbohydrates', nutrition['carbohydrates']),
            _buildNutritionRow('Protein', nutrition['protein']),
            _buildNutritionRow('Fat', nutrition['fat']),
            _buildNutritionRow('Fiber', nutrition['fiber']),
          ],
        ),
      ),
    );
  }

 Widget _buildNutritionRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: const TextStyle(fontSize: 16))),
          Flexible(
            child: Text(
              value?.toString() ?? 'N/A',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealInfoCard(BuildContext context, Map<String, dynamic> meal) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingredients',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildIngredientsList(meal),
            const SizedBox(height: 24),
            Text(
              'Instructions',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildInstructions(meal),
          ],
        ),
      ),
    );
  }
  Widget _buildIngredientsList(Map<String, dynamic> meal) {
    final ingredients = <Widget>[];
    for (var i = 1; i <= 20; i++) {
      final ingredient = meal['strIngredient$i'];
      final measure = meal['strMeasure$i'];
      if (ingredient != null && ingredient.isNotEmpty && ingredient.trim() != "") {
        ingredients.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text('• $measure $ingredient'),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: ingredients);
  }

  Widget _buildInstructions(Map<String, dynamic> meal) {
    final instructions = meal['strInstructions'] as String?;
    if (instructions == null || instructions.isEmpty) {
      return const Text('No instructions available.');
    }
    return Text(instructions, style: const TextStyle(height: 1.5));
  }
}
