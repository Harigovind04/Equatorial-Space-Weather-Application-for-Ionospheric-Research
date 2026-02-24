import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:dio/dio.dart';

class Panel4Page extends StatelessWidget {
  const Panel4Page({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Panel 2',
      home: SpaceWeatherHome(),
    );
  }
}

class SpaceWeatherHome extends StatefulWidget {
  const SpaceWeatherHome({super.key});

  @override
  _SpaceWeatherHomeState createState() => _SpaceWeatherHomeState();
}

class _SpaceWeatherHomeState extends State<SpaceWeatherHome> {
  DateTime? selectedDate;
  late Interpreter _interpreter;
  List<FlSpot> _modelhourlyDataPoints = [];
  List<FlSpot> _modelminutelyDataPoints = [];
  bool isLoading = false;
  bool isModelLoaded = false;
  List<FlSpot> _hourlyDataPoints = [];
  List<FlSpot> _minutelyDataPoints = [];
  List<FlSpot> _symHHourlyDataPoints = [];
  List<FlSpot> _symHMinutelyDataPoints = [];
  String? _errorMessage;
  final Dio _dio = Dio();

  Future<void> fetchGraphs() async {
    if (selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date.")),
      );
      return;
    }

    final dateString1 = DateFormat('dd-MM-yyyy').format(selectedDate!);
    final dateString2 = DateFormat('ddMMyy').format(selectedDate!);

    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    await _magneticFieldStrength(dateString2);
    await _loadSymHFromOmni(dateString1);
    await processTECGraphs(dateString2);

    setState(() {
      isLoading = false;
    });
  }

  Future<void> processTECGraphs(String date) async {
    try {
      if (!isModelLoaded) {
        _interpreter = await Interpreter.fromAsset('assets/tec_model2.tflite');
        print('Model loaded successfully');
        setState(() {
          isModelLoaded = true;
        });
      }

      if (selectedDate == null) {
        //print('Error: selectedDate is null.');
        return;
      }

      final year = selectedDate!.year.toDouble();
      final month = selectedDate!.month.toDouble();
      final day = selectedDate!.day.toDouble();

      final means = [2024.0, 9.0, 17.0, 11.5];
      final stds = [1.5, 3.0, 11.0, 6.0];

      final hourlyInput =
      List.generate(24, (hour) => [year, month, day, hour.toDouble()]);
      final normalizedHourlyData = hourlyInput.map((row) {
        return List.generate(row.length, (i) => (row[i] - means[i]) / stds[i]);
      }).toList();
      final inputTensor1 =
      Float32List.fromList(normalizedHourlyData.expand((e) => e).toList());
      final outputTensor1 = List.filled(24, 0.0).reshape([24, 1]);
      _interpreter.run(inputTensor1, outputTensor1);
      final hourlyPoints = List.generate(24, (index) {
        return FlSpot(index.toDouble(), outputTensor1[index][0]);
      });

      final means2 = [2024.0, 9.0, 17.0, 719.5];
      final stds2 = [1.5, 3.0, 11.0, 415.0];
      final minutelyInput =
      List.generate(1440, (minute) => [year, month, day, minute.toDouble()]);
      final normalizedMinutelyData = minutelyInput.map((row) {
        return List.generate(row.length, (i) => (row[i] - means2[i]) / stds2[i]);
      }).toList();
      final inputTensor2 =
      Float32List.fromList(normalizedMinutelyData.expand((e) => e).toList());
      final outputTensor2 = List.filled(1440, 0.0).reshape([1440, 1]);
      _interpreter.run(inputTensor2, outputTensor2);
      final minutelyPoints = List.generate(1440, (index) {
        return FlSpot(index.toDouble(),
            outputTensor2[index][0] * stds2.last + means2.last);
      });

      setState(() {
        _modelhourlyDataPoints = hourlyPoints;
        _modelminutelyDataPoints = minutelyPoints;
      });
    } catch (e) {
      //print('Error processing graphs: $e');
      setState(() {
        _errorMessage = "Error processing graphs: $e";
      });
    }
  }

  Future<void> _magneticFieldStrength(String date) async {
    try {
      final database = FirebaseDatabase.instance.ref('ppm_data');
      final snapshot = await database.get();

      if (!snapshot.exists) {
        throw "No data found in the database.";
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
      final List<Map<String, dynamic>> filteredData = data.values
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) => entry['date'] == date)
          .toList();

      if (filteredData.isEmpty) {
        throw "No data available for the selected date: $date";
      }

      final Map<int, List<double>> groupedByHour = {};
      final List<FlSpot> minutelyPoints = [];

      for (final entry in filteredData) {
        final timeParts = entry['time'].split(':');
        final hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final value = entry['magnetic_field_strength'];

        groupedByHour.putIfAbsent(hour, () => []).add(value);
        minutelyPoints.add(FlSpot(hour * 60.0 + minute, value));
      }

      final List<FlSpot> hourlyPoints = groupedByHour.entries.map((entry) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        return FlSpot(entry.key.toDouble(), avg);
      }).toList();

      setState(() {
        _hourlyDataPoints = hourlyPoints..sort((a, b) => a.x.compareTo(b.x));
        _minutelyDataPoints = minutelyPoints..sort((a, b) => a.x.compareTo(b.x));
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading magnetic field data: $e";
      });
    }
  }

  Future<void> _loadSymHFromOmni(String date) async {
    try {
      const url = 'https://omniweb.gsfc.nasa.gov/cgi/nx1.cgi';
      _dio.options.headers = {'Content-Type': 'application/x-www-form-urlencoded'};

      String formattedDate = DateFormat('yyyyMMdd').format(selectedDate!);

      final data = {
        'activity': 'retrieve',
        'res': 'min', // Request 1-minute resolution for high-res data
        'spacecraft': 'omni_min', // High Resolution OMNI
        'start_date': formattedDate,
        'end_date': formattedDate,
        'vars': 41, // SYM-H variable ID
      };

      final response = await _dio.post(url, data: FormData.fromMap(data));

      if (response.statusCode == 200) {
        //print("Response Data:\n${response.data.toString()}");
        final parsedData = _parseOmniSymHData(response.data.toString());
        if (parsedData.isNotEmpty) {
          final hourlyPoints = _calculateHourlyAverages(parsedData);
          setState(() {
            _symHMinutelyDataPoints = parsedData;
            _symHHourlyDataPoints = hourlyPoints;
            _errorMessage = null;
          });
        } else {
          throw "No SYM-H data parsed from response";
        }
      } else {
        throw 'Failed to retrieve data. Status: ${response.statusCode}';
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading SYM-H data: $e";
        _symHHourlyDataPoints = [];
        _symHMinutelyDataPoints = [];
      });
    }
  }

  List<FlSpot> _parseOmniSymHData(String responseData) {
    List<FlSpot> minutelyPoints = [];
    List<String> lines = responseData.split('\n');
    bool startReading = false;

    for (String line in lines) {
      if (line.contains("YYYY DOY HR MN")) {
        startReading = true;
        continue;
      }

      if (startReading && line.trim().isNotEmpty && line.contains(RegExp(r'^\d{4}'))) {
        List<String> parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          int hour = int.parse(parts[2]);
          int minute = int.parse(parts[3]);
          double value = double.tryParse(parts[4]) ?? 0;
          // Skip invalid values (OMNI often uses 9999.9 or similar for missing data)
          if (value < 9999) {
            double xValue = hour * 60.0 + minute;
            minutelyPoints.add(FlSpot(xValue, value));
          }
        }
      }
    }

    minutelyPoints.sort((a, b) => a.x.compareTo(b.x));
    return minutelyPoints;
  }

  List<FlSpot> _calculateHourlyAverages(List<FlSpot> minutelyPoints) {
    Map<int, List<double>> hourlyGroups = {};

    for (var point in minutelyPoints) {
      int hour = (point.x / 60).floor();
      hourlyGroups.putIfAbsent(hour, () => []).add(point.y);
    }

    List<FlSpot> hourlyPoints = hourlyGroups.entries.map((entry) {
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      return FlSpot(entry.key.toDouble(), avg);
    }).toList();

    hourlyPoints.sort((a, b) => a.x.compareTo(b.x));
    return hourlyPoints;
  }

  Widget buildGraph(String title, List<FlSpot> points, String xLabel, String yLabel) {
    bool isMinuteDeltaH = title.contains("1-Minute Average ΔH");
    bool isPredictedTecGraph = title == "Hourly Average TEC" || title == "1-Minute Average TEC"; // Exact match for predicted TEC graphs
    bool isdeltaHGraph = title == "Hourly Average ΔH" || title == "1-Minute Average ΔH";

    bool isSymHGraph = title == "Hourly Average SYM-H" || title == "1-Minute Average SYM-H";

    // Default X-axis values
    double minX = 0;
    double maxX = (title.contains("Hourly") ? 23 : 1439); // 23 for hours, 1439 for minutes
    double minY, maxY;

    if (isPredictedTecGraph && points.isNotEmpty) {
      // Dynamically calculate minY and maxY for predicted TEC graphs
      minY = points.map((e) => e.y).reduce((a, b) => a < b ? a : b);
      maxY = points.map((e) => e.y).reduce((a, b) => a > b ? a : b);
      // Add padding for better visualization
      double padding = (maxY - minY) * 0.1; // 10% padding
      minY -= padding;
      maxY += padding;
    }
    else if (isdeltaHGraph && points.isNotEmpty) {
      // Dynamically calculate minY and maxY for predicted TEC graphs
      minY = points.map((e) => e.y).reduce((a, b) => a < b ? a : b);
      maxY = points.map((e) => e.y).reduce((a, b) => a > b ? a : b);
      // Add padding for better visualization
      double padding = (maxY - minY) * 0.1; // 10% padding
      minY -= padding;
      maxY += padding;

    }
    else if (isSymHGraph && points.isNotEmpty) {
      // Dynamically calculate minY and maxY for predicted TEC graphs
      minY = points.map((e) => e.y).reduce((a, b) => a < b ? a : b);
      maxY = points.map((e) => e.y).reduce((a, b) => a > b ? a : b);
      // Add padding for better visualization -
      double padding = (maxY - minY) * 0.1; // 10% padding
      minY -= padding;
      maxY += padding;

    }


    else {
      minY = points.isNotEmpty ? points.map((e) => e.y).reduce((a, b) => a < b ? a : b) : 0;
      maxY = points.isNotEmpty ? points.map((e) => e.y).reduce((a, b) => a > b ? a : b) : 100;
    }


    return SizedBox(
      height: 300,
      child: isLoading
          ? Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          width: double.infinity,
          height: 300,
          color: Colors.white,
        ),
      )
          : LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: Text(yLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toStringAsFixed(2),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: Text(xLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points,
              isCurved: true,
              gradient: const LinearGradient(colors: [Colors.blue, Colors.lightBlueAccent]),
              barWidth: isMinuteDeltaH ? 1 : 3,
              belowBarData: BarAreaData(show: false),
              dotData: FlDotData(show: !title.contains("1-Minute Average ΔH")),
            ),
          ],
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: isMinuteDeltaH ? Colors.grey.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: isMinuteDeltaH ? Colors.grey.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: true),
          lineTouchData: LineTouchData(
            enabled: !isMinuteDeltaH,
            touchSpotThreshold: isMinuteDeltaH ? double.infinity : 10,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (LineBarSpot touchedSpot) => Colors.blue.withOpacity(0.8),
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.x.toInt()} ${xLabel == "Hour" ? "h" : "min"}: ${spot.y.toStringAsFixed(2)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
            getTouchedSpotIndicator: (barData, spotIndexes) {
              if (isMinuteDeltaH) return spotIndexes.map((index) => null).toList();
              return spotIndexes.map((index) => const TouchedSpotIndicatorData(
                FlLine(color: Colors.red, strokeWidth: 2),
                FlDotData(show: true),
              )).toList();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel 2", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Panel 2: Equatorial Ionospheric Prediction Using ML and Disturbances",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text("Select Date: "),
                OutlinedButton(
                  onPressed: () => showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  ).then((date) {
                    if (date != null) setState(() => selectedDate = date);
                  }),
                  child: Text(
                    selectedDate == null ? "Pick a date" : "${selectedDate!.toLocal()}".split(' ')[0],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(onPressed: fetchGraphs, child: const Text("Submit")),
              ],
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 20),
            const Text(
              "Predicted TEC Model",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Hourly Average Graph:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            buildGraph("Hourly Average TEC", _modelhourlyDataPoints, "Hour", "Predicted TEC"),
            const SizedBox(height: 20),
            const Text(
              "1-Minute Average Graph:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            buildGraph("1-Minute Average TEC", _modelminutelyDataPoints, "Minute", "Predicted TEC"),
            const SizedBox(height: 20),
            const Text(
              "ΔH(nT), Equatorial Electrojet(nT)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Hourly Average Graph:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            buildGraph("Hourly Average ΔH", _hourlyDataPoints, "Hour", "ΔH"),
            const SizedBox(height: 20),
            const Text(
              "1-Minute Average Graph:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            buildGraph("1-Minute Average ΔH", _minutelyDataPoints, "Minute", "ΔH"),
            const SizedBox(height: 20),
            const Text(
              "SymH",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Hourly Average Graph:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            buildGraph("Hourly Average SYM-H", _symHHourlyDataPoints, "Hour", "SymH"),
            const SizedBox(height: 20),
            const Text(
              "1-Minute Average Graph:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            buildGraph("1-Minute Average SYM-H", _symHMinutelyDataPoints, "Minute", "SymH"),
          ],
        ),
      ),
    );
  }
}