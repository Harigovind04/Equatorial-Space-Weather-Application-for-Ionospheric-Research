import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_config/flutter_config.dart';

class Panel2Page extends StatelessWidget {
  const Panel2Page({super.key});

  @override
  Widget build(BuildContext context) {
    return const SpaceWeatherHome();
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
  final Set<String> _selectedParameters = {};
  final Set<String> _selectedResolutions = {};
  final Map<String, List<FlSpot>> _dataPointsMap = {};
  bool _isLoading = false; // Single loading state for all graphs
  String? _errorMessage;
  bool isModelLoaded = false;
  final Dio _dio = Dio();
  String? _dateError;
  late TextEditingController _dateController;

  final List<String> _parameters = [
    "ΔH(nT), Equatorial Electrojet(nT)",
    "Predicted TEC",
    "SymH",
  ];

  final List<String> _resolutions = [
    "Hourly Average",
    "1-Minute Average",
  ];

  @override
  void initState() {
    super.initState();
    _initializeDataMaps();
    _dateController = TextEditingController();
  }

  void _initializeDataMaps() {
    for (var param in _parameters) {
      for (var res in _resolutions) {
        final key = "$param - $res";
        _dataPointsMap[key] = [];
      }
    }
  }

  Future<void> fetchGraphs() async {
    if (selectedDate == null || _selectedParameters.isEmpty || _selectedResolutions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date, at least one parameter, and one resolution.")),
      );
      return;
    }

    final dateString1 = DateFormat('dd-MM-yyyy').format(selectedDate!);
    final dateString2 = DateFormat('ddMMyy').format(selectedDate!);

    setState(() {
      _errorMessage = null;
      _isLoading = true; // Set loading to true for all graphs
      // Clear existing data
      for (var param in _selectedParameters) {
        for (var res in _selectedResolutions) {
          _dataPointsMap["$param - $res"] = [];
        }
      }
    });

    try {
      // Fetch data for all graphs concurrently
      final futures = <Future>[];
      for (var param in _selectedParameters) {
        for (var res in _selectedResolutions) {
          if (param == "ΔH(nT), Equatorial Electrojet(nT)") {
            futures.add(_magneticFieldStrength(dateString2, res));
          } else if (param == "Predicted TEC") {
            futures.add(_processTECGraphs(dateString2, res));
          } else if (param == "SymH") {
            futures.add(_loadSymHFromOmni(dateString1, res));
          }
        }
      }
      // Wait for all data fetches to complete
      await Future.wait(futures);
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading graphs: $e";
      });
    } finally {
      setState(() {
        _isLoading = false; // Set loading to false after all graphs are loaded
      });
    }
  }

  Future<void> _processTECGraphs(String date, String resolution) async {
    try {
      if (!isModelLoaded) {
        _interpreter = await Interpreter.fromAsset('assets/tec_model2.tflite');
        setState(() {
          isModelLoaded = true;
        });
      }

      if (selectedDate == null) {
        return;
      }

      final year = selectedDate!.year.toDouble();
      final month = selectedDate!.month.toDouble();
      final day = selectedDate!.day.toDouble();

      List<FlSpot> points;

      if (resolution == "Hourly Average") {
        final means = [2024.0, 9.0, 17.0, 11.5];
        final stds = [1.5, 3.0, 11.0, 6.0];
        final hourlyInput = List.generate(24, (hour) => [year, month, day, hour.toDouble()]);
        final normalizedHourlyData = hourlyInput.map((row) {
          return List.generate(row.length, (i) => (row[i] - means[i]) / stds[i]);
        }).toList();
        final inputTensor = Float32List.fromList(normalizedHourlyData.expand((e) => e).toList());
        final outputTensor = List.filled(24, 0.0).reshape([24, 1]);
        _interpreter.run(inputTensor, outputTensor);
        points = List.generate(24, (index) {
          return FlSpot(index.toDouble(), outputTensor[index][0]);
        });
      } else {
        final means = [2024.0, 9.0, 17.0, 719.5];
        final stds = [1.5, 3.0, 11.0, 415.0];
        final minutelyInput = List.generate(1440, (minute) => [year, month, day, minute.toDouble()]);
        final normalizedMinutelyData = minutelyInput.map((row) {
          return List.generate(row.length, (i) => (row[i] - means[i]) / stds[i]);
        }).toList();
        final inputTensor = Float32List.fromList(normalizedMinutelyData.expand((e) => e).toList());
        final outputTensor = List.filled(1440, 0.0).reshape([1440, 1]);
        _interpreter.run(inputTensor, outputTensor);
        points = List.generate(1440, (index) {
          return FlSpot(index.toDouble(), outputTensor[index][0] * stds.last + means.last);
        });
      }

      setState(() {
        _dataPointsMap["Predicted TEC - $resolution"] = points;
      });
    } catch (e) {
      throw "Error processing TEC graphs: $e";
    }
  }

  Future<void> _magneticFieldStrength(String date, String resolution) async {
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

      List<FlSpot> points;

      if (resolution == "Hourly Average") {
        final Map<int, List<double>> groupedByHour = {};
        for (final entry in filteredData) {
          final timeParts = entry['time'].split(':');
          final hour = int.parse(timeParts[0]);
          final value = entry['magnetic_field_strength'];
          groupedByHour.putIfAbsent(hour, () => []).add(value);
        }
        points = groupedByHour.entries.map((entry) {
          final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
          return FlSpot(entry.key.toDouble(), avg);
        }).toList();
      } else {
        points = filteredData.map((entry) {
          final timeParts = entry['time'].split(':');
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);
          final value = entry['magnetic_field_strength'];
          return FlSpot(hour * 60.0 + minute, value);
        }).toList();
      }

      points.sort((a, b) => a.x.compareTo(b.x));
      setState(() {
        _dataPointsMap["ΔH(nT), Equatorial Electrojet(nT) - $resolution"] = points;
      });
    } catch (e) {
      throw "Error loading magnetic field data: $e";
    }
  }

  Future<void> _loadSymHFromOmni(String date, String resolution) async {
    try {
      final url = FlutterConfig.get('NASA_BASE_URL');

      _dio.options.headers = {'Content-Type': 'application/x-www-form-urlencoded'};

      String formattedDate = DateFormat('yyyyMMdd').format(selectedDate!);
      String res = resolution == "Hourly Average" ? "hour" : "min";
      String spacecraft = "omni_min";

      final data = {
        'activity': 'retrieve',
        'res': res,
        'spacecraft': spacecraft,
        'start_date': formattedDate,
        'end_date': formattedDate,
        'vars': '41',
      };

      final response = await _dio.post(url, data: FormData.fromMap(data));

      print("SymH $resolution Response: ${response.data}");

      if (response.statusCode == 200) {
        List<FlSpot> points;
        if (resolution == "Hourly Average") {
          points = _parseOmniSymHHourlyData(response.data.toString());
        } else {
          points = _parseOmniSymHMinutelyData(response.data.toString());
        }
        print("SymH $resolution Parsed Points: $points");
        if (points.isNotEmpty) {
          setState(() {
            _dataPointsMap["SymH - $resolution"] = points;
          });
        } else {
          throw "No valid Sym-H data parsed from response";
        }
      } else {
        throw 'Failed to retrieve data. Status: ${response.statusCode}';
      }
    } catch (e) {
      print("SymH $resolution Error: $e");
      throw "Error loading Sym-H data: $e";
    }
  }

  List<FlSpot> _parseOmniSymHHourlyData(String responseData) {
    List<FlSpot> minPoints = [];
    List<String> lines = responseData.split('\n');
    bool startReading = false;

    for (String line in lines) {
      if (line.contains("YYYY DOY HR MN")) {
        startReading = true;
        continue;
      }

      if (startReading && line.trim().isNotEmpty && RegExp(r'^\d{4}').hasMatch(line)) {
        List<String> parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          try {
            int hour = int.parse(parts[2]);
            int minute = int.parse(parts[3]);
            double value = double.tryParse(parts[4]) ?? double.nan;
            if (value.isFinite) {
              minPoints.add(FlSpot(hour * 60.0 + minute, value));
            }
          } catch (e) {
            print("Minutely Parse Error on line: $line, Error: $e");
          }
        }
      }
    }

    minPoints.sort((a, b) => a.x.compareTo(b.x));
    Map<int, List<double>> hourlyGroups = {};

    for (var point in minPoints) {
      int hour = (point.x / 60).floor();
      hourlyGroups.putIfAbsent(hour, () => []).add(point.y);
    }

    List<FlSpot> points = hourlyGroups.entries.map((entry) {
      final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
      return FlSpot(entry.key.toDouble(), avg);
    }).toList();

    points.sort((a, b) => a.x.compareTo(b.x));
    return points;
  }

  List<FlSpot> _parseOmniSymHMinutelyData(String responseData) {
    List<FlSpot> points = [];
    List<String> lines = responseData.split('\n');
    bool startReading = false;

    for (String line in lines) {
      if (line.contains("YYYY DOY HR MN")) {
        startReading = true;
        continue;
      }

      if (startReading && line.trim().isNotEmpty && RegExp(r'^\d{4}').hasMatch(line)) {
        List<String> parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          try {
            int hour = int.parse(parts[2]);
            int minute = int.parse(parts[3]);
            double value = double.tryParse(parts[4]) ?? double.nan;
            if (value.isFinite) {
              points.add(FlSpot(hour * 60.0 + minute, value));
            }
          } catch (e) {
            print("Minutely Parse Error on line: $line, Error: $e");
          }
        }
      }
    }

    points.sort((a, b) => a.x.compareTo(b.x));
    return points;
  }

  Widget buildGraph(String title, List<FlSpot> points, String xLabel, String yLabel, bool isLastGraph) {
    bool isMinutely = title.contains("1-Minute Average");
    bool isDeltaH = title.contains("ΔH");
    bool isSymH = title.contains("SymH");

    double minX = 0;
    double maxX = isMinutely ? 1439 : 23;
    double minY, maxY;

    if (points.isNotEmpty) {
      minY = points.map((e) => e.y).reduce((a, b) => a < b ? a : b);
      maxY = points.map((e) => e.y).reduce((a, b) => a > b ? a : b);
      double padding = (maxY - minY) * 0.1;
      minY -= padding;
      maxY += padding;
      if (minY == maxY) {
        minY -= 1;
        maxY += 1;
      }
    } else {
      minY = -10;
      maxY = 10;
    }

    return SizedBox(
      height: 300,
      child: LineChart(
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
                    value.toStringAsFixed(isSymH ? 0 : 2),
                    style: const TextStyle(fontSize: 10),
                  );
                },
                interval: isSymH ? 10 : null,
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: isLastGraph
                  ? Text(xLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
                  : null,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  );
                },
                interval: isMinutely ? 240 : 4,
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points,
              isCurved: true,
              gradient: const LinearGradient(colors: [
                Colors.blue,
                Colors.lightBlueAccent,
              ]),
              barWidth: isMinutely && isDeltaH ? 1 : 3,
              belowBarData: BarAreaData(show: false),
              dotData: FlDotData(show: !(isMinutely && isDeltaH)),
            ),
          ],
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (value) => FlLine(
              color: isMinutely && isDeltaH ? Colors.grey.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: isMinutely && isDeltaH ? Colors.grey.withOpacity(0.1) : Colors.grey.withOpacity(0.3),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: true),
          lineTouchData: LineTouchData(
            enabled: !(isMinutely && isDeltaH),
            touchSpotThreshold: isMinutely && isDeltaH ? double.infinity : 10,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (LineBarSpot touchedSpot) => Colors.blue.withOpacity(0.8),
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.x.toInt()} ${xLabel == "Hour" ? "h" : "min"}: ${spot.y.toStringAsFixed(isSymH ? 0 : 2)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
            getTouchedSpotIndicator: (barData, spotIndexes) {
              if (isMinutely && isDeltaH) return spotIndexes.map((index) => null).toList();
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

  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hourlyGraphs = <Widget>[];
    final minutelyGraphs = <Widget>[];

    // Find the last parameter for each resolution to determine the last graph
    final lastHourlyParam = _selectedParameters.isNotEmpty &&
        _selectedResolutions.contains("Hourly Average")
        ? _selectedParameters.last
        : null;
    final lastMinutelyParam = _selectedParameters.isNotEmpty &&
        _selectedResolutions.contains("1-Minute Average")
        ? _selectedParameters.last
        : null;

    if (_isLoading) {
      // Show shimmer effect for all expected graphs
      for (var param in _selectedParameters) {
        for (var res in _selectedResolutions) {
          final graphWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildShimmerEffect(),
              const SizedBox(height: 8),
            ],
          );
          if (res == "Hourly Average") {
            hourlyGraphs.add(graphWidget);
          } else {
            minutelyGraphs.add(graphWidget);
          }
        }
      }
    } else {
      // Show actual graphs
      for (var param in _selectedParameters) {
        for (var res in _selectedResolutions) {
          final key = "$param - $res";
          final points = _dataPointsMap[key] ?? [];
          final xLabel = res == "Hourly Average" ? "Hour" : "Minute";
          final yLabel = param == "Predicted TEC" ? "Predicted TEC" : param == "SymH" ? "SymH (nT)" : "ΔH(nT), Equatorial Electrojet(nT)";

          bool isLastGraph = false;
          if (res == "Hourly Average" && param == lastHourlyParam) {
            isLastGraph = true;
          } else if (res == "1-Minute Average" && param == lastMinutelyParam) {
            isLastGraph = true;
          }

          final graphWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildGraph("$param - $res", points, xLabel, yLabel, isLastGraph),
              const SizedBox(height: 8),
            ],
          );

          if (res == "Hourly Average") {
            hourlyGraphs.add(graphWidget);
          } else {
            minutelyGraphs.add(graphWidget);
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel 2", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        automaticallyImplyLeading: false,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Select Date: ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: _dateController,
                    decoration: InputDecoration(
                      hintText: 'dd-mm-yyyy',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() {
                              selectedDate = date;
                              _dateController.text = DateFormat('dd-MM-yyyy').format(date);
                              _dateError = null;
                            });
                          }
                        },
                      ),
                      errorText: _dateError,
                    ),
                    keyboardType: TextInputType.datetime,
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          selectedDate = null;
                          _dateError = null;
                        });
                        return;
                      }
                      try {
                        final parsedDate = DateFormat('dd-MM-yyyy').parseStrict(value);
                        if (parsedDate.year < 2000 || parsedDate.isAfter(DateTime.now())) {
                          setState(() {
                            _dateError = 'Date must be between 2000 and today';
                          });
                        } else {
                          setState(() {
                            selectedDate = parsedDate;
                            _dateError = null;
                          });
                        }
                      } catch (e) {
                        setState(() {
                          _dateError = 'Invalid format (use dd-mm-yyyy)';
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              "Select Parameters:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                itemCount: _parameters.length,
                itemBuilder: (context, index) {
                  final parameter = _parameters[index];
                  final isSelected = _selectedParameters.contains(parameter);
                  return CheckboxListTile(
                    title: Text(parameter),
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedParameters.add(parameter);
                        } else {
                          _selectedParameters.remove(parameter);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Select Resolutions:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                itemCount: _resolutions.length,
                itemBuilder: (context, index) {
                  final resolution = _resolutions[index];
                  final isSelected = _selectedResolutions.contains(resolution);
                  return CheckboxListTile(
                    title: Text(resolution),
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedResolutions.add(resolution);
                        } else {
                          _selectedResolutions.remove(resolution);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: fetchGraphs,
              child: const Text("Submit", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 20),
            ...hourlyGraphs,
            ...minutelyGraphs,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dio.close();
    if (isModelLoaded) {
      _interpreter.close();
    }
    super.dispose();
  }
}