import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shimmer/shimmer.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:flutter_config/flutter_config.dart';

class Panel1Page extends StatelessWidget {
  const Panel1Page({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ComparativeStudyPage(),
    );
  }
}

class ComparativeStudyPage extends StatelessWidget {
  const ComparativeStudyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F9),
      appBar: AppBar(
        title: const Text("Panel 1", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
      ),
      body: const Padding(
        padding: EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "Panel 1: Geomagnetic Field Variations and Interplanetary Parameters",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20),
              ReportCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportCard extends StatefulWidget {
  const ReportCard({super.key});

  @override
  _ReportCardState createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  final _dateController = TextEditingController();
  final Set<String> _selectedParameters = {};
  final Map<String, String?> _errorMessages = {};
  final Map<String, List<FlSpot>> _dataPointsMap = {};
  bool _isLoading = false; // Single loading state for all graphs
  final Dio _dio = Dio();
  DateTime? selectedDate;
  String? _dateError;

  final List<String> _parameters = [
    "ΔH(nT), Equatorial Electrojet(nT)",
    "IMF Magnitude Avg, nT",
    "Magnitude, Avg IMF Vr, nT",
    "Bx, GSE/GSM, nT",
    "By, GSE, nT",
    "By, GSM, nT",
    "Bz, GSM, nT",
    "Bz, GSE, nT",
    "Dst Index, nT",
  ];

  final Map<String, int> parameterMap = {
    "IMF Magnitude Avg, nT": 8,
    "Magnitude, Avg IMF Vr, nT": 9,
    "Bx, GSE/GSM, nT": 12,
    "By, GSE, nT": 13,
    "By, GSM, nT": 15,
    "Bz, GSM, nT": 16,
    "Bz, GSE, nT": 14,
    "Dst Index, nT": 40,
  };

  Future<void> loadGraphData() async {
    if (_dateController.text.isEmpty || _selectedParameters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date and at least one parameter.")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessages.clear();
      for (var parameter in _selectedParameters) {
        _dataPointsMap[parameter] = [];
        _errorMessages[parameter] = null;
      }
    });

    try {
      // Fetch data for all graphs concurrently
      final futures = <Future>[];
      for (var parameter in _selectedParameters) {
        if (parameter == "ΔH(nT), Equatorial Electrojet(nT)") {
          futures.add(_loadMagneticFieldStrengthData(parameter));
        } else {
          futures.add(_loadOmniData(parameter));
        }
      }
      await Future.wait(futures);
    } catch (e) {
      setState(() {
        for (var parameter in _selectedParameters) {
          _errorMessages[parameter] = "Error loading data: $e";
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadOmniData(String parameter) async {
    List<String> parts = _dateController.text.split('-');
    int year = int.parse(parts[2]);
    int month = int.parse(parts[1]);
    int day = int.parse(parts[0]);

    String formattedDate =
        "$year${month.toString().padLeft(2, '0')}${day.toString().padLeft(2, '0')}";

    final selectedVar = parameterMap[parameter];
    if (selectedVar == null) {
      throw "Unsupported parameter selected.";
    }


    final url = FlutterConfig.get('NASA_BASE_URL');


    _dio.options.headers = {'Content-Type': 'application/x-www-form-urlencoded'};

    final data = {
      'activity': 'retrieve',
      'res': 'hour',
      'spacecraft': 'omni2',
      'start_date': formattedDate,
      'end_date': formattedDate,
      'vars': selectedVar,
    };

    final response = await _dio.post(url, data: FormData.fromMap(data));

    if (response.statusCode == 200) {
      List<FlSpot> spots = _parseOmniData(response.data.toString());
      if (spots.isNotEmpty) {
        setState(() {
          _dataPointsMap[parameter] = spots;
          _errorMessages[parameter] = null;
        });
      } else {
        throw "No data available for selected parameter";
      }
    } else {
      throw 'Failed to retrieve data. Status: ${response.statusCode}';
    }
  }

  List<FlSpot> _parseOmniData(String responseData) {
    List<FlSpot> spots = [];
    List<String> lines = responseData.split('\n');
    bool startReading = false;

    for (String line in lines) {
      if (line.contains("YEAR DOY HR")) {
        startReading = true;
        continue;
      }

      if (startReading && line.trim().isNotEmpty && line.contains(RegExp(r'^\d{4}'))) {
        List<String> parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          int hour = int.parse(parts[2]);
          double value = double.tryParse(parts[3]) ?? 0;
          if (value < 999) {
            spots.add(FlSpot(hour.toDouble(), value));
          }
        }
      }
    }

    spots.sort((a, b) => a.x.compareTo(b.x));
    return spots;
  }

  Future<void> _loadMagneticFieldStrengthData(String parameter) async {
    final dateParts = _dateController.text.split('-');
    final day = int.parse(dateParts[0]);
    final month = int.parse(dateParts[1]);
    final year = int.parse(dateParts[2]);

    final formattedDateForDatabase = "${day.toString().padLeft(2, '0')}"
        "${month.toString().padLeft(2, '0')}"
        "${year.toString().substring(2)}";

    final database = FirebaseDatabase.instance.ref('ppm_data');
    final snapshot = await database.get();

    if (!snapshot.exists) {
      throw "No data found in the database.";
    }

    final Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);
    final List<Map<String, dynamic>> filteredData = data.values
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => entry['date'] == formattedDateForDatabase)
        .toList();

    if (filteredData.isEmpty) {
      throw "No data available for the selected date: $formattedDateForDatabase";
    }

    final Map<int, List<double>> groupedByHour = {};
    for (final entry in filteredData) {
      final timeParts = entry['time'].split(':');
      final hour = int.parse(timeParts[0]);
      final magneticFieldStrength = double.parse(entry['magnetic_field_strength'].toString());
      if (!groupedByHour.containsKey(hour)) {
        groupedByHour[hour] = [];
      }
      groupedByHour[hour]!.add(magneticFieldStrength);
    }

    final List<FlSpot> points = [];
    groupedByHour.forEach((hour, values) {
      final avgStrength = values.reduce((a, b) => a + b) / values.length;
      points.add(FlSpot(hour.toDouble(), avgStrength));
    });

    points.sort((a, b) => a.x.compareTo(b.x));

    setState(() {
      _dataPointsMap[parameter] = points;
      _errorMessages[parameter] = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select Date:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.left,
            ),            const SizedBox(height: 8),
            TextField(
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
            const SizedBox(height: 20),
            const Text(
              "Select Parameters:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.left,
            ),
            Container(
              height: 200,
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
            ElevatedButton(
              onPressed: loadGraphData,
              child: const Text("Load Graph Data", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              ..._selectedParameters.map((parameter) {
                return Column(
                  children: [
                    _buildShimmerEffect(),
                    const SizedBox(height: 10),
                  ],
                );
              })
            else
              ..._selectedParameters.toList().asMap().entries.map((entry) {
                final index = entry.key;
                final parameter = entry.value;
                final isLast = index == _selectedParameters.length - 1;
                return Column(
                  children: [
                    if (_errorMessages[parameter] != null) ...[
                      Text(
                        _errorMessages[parameter]!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      height: 300,
                      child: LineChart(
                        LineChartData(
                          lineBarsData: [
                            LineChartBarData(
                              spots: _dataPointsMap[parameter] ?? [],
                              isCurved: true,
                              gradient: const LinearGradient(
                                colors: [Colors.blue, Colors.lightBlueAccent],
                              ),
                              barWidth: 4,
                              belowBarData: BarAreaData(show: false),
                            ),
                          ],
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              axisNameWidget: Text(
                                parameter,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: parameter == "ΔH(nT), Equatorial Electrojet(nT)" ? 1000 : 2,
                                reservedSize: 40,
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              axisNameWidget: isLast
                                  ? const Text("Hour", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))
                                  : null,
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  return Text("${value.toInt()}h", style: const TextStyle(fontSize: 12));
                                },
                                interval: 4,
                                reservedSize: 30,
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          gridData: const FlGridData(show: true),
                          borderData: FlBorderData(show: true),
                          minX: 0,
                          maxX: 23,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              }),
          ],
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
}